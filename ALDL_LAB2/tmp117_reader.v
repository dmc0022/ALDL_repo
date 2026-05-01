`timescale 1ns/1ps
`default_nettype none

//=============================================================================
// Module: tmp117_reader
//-----------------------------------------------------------------------------
// Purpose:
//   This module performs repeated I2C reads of the TMP117 temperature register
//   and presents the returned 16-bit sensor word on `raw_id`.
//
//     raw_id = latest 16-bit raw temperature sample from the TMP117
//
// Role in Lab 2:
//   This is the main "sensor interface" module for the lab. You do not
//   need to understand every signal inside the provided low-level I2C master,
//   but you SHOULD understand how this wrapper uses that master to:
//     1) wait for power-up / startup delay,
//     2) periodically request a sensor read,
//     3) wait for the I2C transaction to begin,
//     4) wait for the I2C transaction to complete,
//     5) capture the returned sensor data.
//
// I2C transaction conceptually performed by the underlying master:
//   START
//   send device address + write bit
//   send register pointer (0x00 for temperature)
//   REPEATED START
//   send device address + read bit
//   read two data bytes (MSB then LSB)
//   STOP
//
// Notes:
//   - This module is intentionally polling-based. It continuously re-reads the
//     sensor after a programmable delay so the rest of the design always has a
//     recent temperature value.
//   - The low-level timing and SDA/SCL bit control are handled by i2c_master.
//   - This wrapper is responsible for the higher-level sequencing around that
//     master.
//=============================================================================
module tmp117_reader #(
    // System clock frequency in Hz.
    // Used to compute the I2C clock divider.
    parameter integer CLK_FREQ_HZ  = 50_000_000,

    // Target I2C clock frequency in Hz.
    // 50 kHz is conservative and often easier for bring-up/debug.
	// This value can range from 25k to 400k depending on the device used
    parameter integer I2C_FREQ_HZ  = 50_000,

    // 7-bit TMP117 I2C address.
    // Default TMP117 address is 0x48.
    parameter [6:0]  TMP117_ADDR   = 7'h48,

    // Number of clk_50 cycles to wait after reset before the first read.
    // This gives the board and sensor time to settle after configuration.
    parameter [23:0] STARTUP_TICKS = 24'd5_000_000,

    // Number of clk_50 cycles between completed reads.
    // This controls the sensor polling rate.
    parameter [23:0] POLL_DIVIDER  = 24'd10_000_000
)(
    // 50 MHz FPGA system clock.
    input  wire        clk_50,

    // Active-low reset.
    input  wire        reset_n,

    // External TMP117 I2C pins.
    // These are declared as inout because the lower-level master handles
    // open-drain style driving.
    inout  wire        tmp_scl,
    inout  wire        tmp_sda,

    // Latest 16-bit value read from the sensor.
    output reg [15:0]  raw_id,

    // High whenever the lower-level I2C master is actively performing a
    // transaction.
    output wire        busy,

    // One-clock pulse generated when a read transaction completes and the
    // returned data has just been captured.
    output reg         tx_done,

    // High-level state of THIS wrapper FSM, exposed for debug/LED display.
    output reg [2:0]   dbg_state,

    // Sticky debug flag: set once the lower-level master has ever gone busy.
    // Useful when debugging whether a transaction was even attempted.
    output reg         busy_seen,

    // Sticky debug flag: set once a full transaction has completed and data
    // has been captured.
    output reg         complete_seen,

    // Latched snapshots of the low-level I2C master's debug signals.
    // These are captured at the end of a completed transaction so the design
    // can inspect the master's final internal state.
    output reg [3:0]   latched_master_state,
    output reg [1:0]   latched_master_phase,
    output reg [3:0]   latched_master_bit,
    output reg [7:0]   latched_master_byte,
    output reg         latched_master_last_ack
);

    //-------------------------------------------------------------------------
    // TMP117 register map selection
    //-------------------------------------------------------------------------
    // Register 0x00 = Temperature result register.
    // If you later want a phase that verifies Device ID first, you can switch
    // this register address to 0x0F and expect 0x0117 from the sensor.
    //-------------------------------------------------------------------------
    localparam [7:0] REG_TEMPERATURE = 8'h00;

    //-------------------------------------------------------------------------
    // I2C divider calculation
    //-------------------------------------------------------------------------
    // The provided i2c_master expects a divider value. This expression derives
    // a suitable divider from the system clock and requested I2C frequency.
    //
    // The "* 4" factor comes from the specific timing structure used inside the
    // provided I2C master. 
    //-------------------------------------------------------------------------
    localparam integer I2C_DIVIDER_INT = (CLK_FREQ_HZ / (I2C_FREQ_HZ * 4)) - 1;

    // Clamp negative results to zero as a safety measure.
    localparam [15:0] I2C_DIVIDER = (I2C_DIVIDER_INT < 0) ? 16'd0 : I2C_DIVIDER_INT[15:0];

    //-------------------------------------------------------------------------
    // Control signals driven into the lower-level I2C master
    //-------------------------------------------------------------------------
    reg         enable;            // One-shot transaction request
    reg         read_write;        // 1 = read transaction, 0 = write transaction
    reg [15:0]  mosi_data;         // Write payload (unused here for reads, kept 0)
    reg [7:0]   register_address;  // TMP117 register address to access
    reg [6:0]   device_address;    // Target 7-bit I2C device address

    // Data returned by the lower-level master after a completed read.
    wire [15:0] miso_data;

    // Busy flag from the lower-level master.
    wire        i2c_busy;

    //-------------------------------------------------------------------------
    // Lower-level master debug signals
    //-------------------------------------------------------------------------
    // These come directly from the I2C master and are useful when diagnosing
    // whether the transfer failed at start, address, register, data, or ACK.
    //-------------------------------------------------------------------------
    wire [3:0]  master_state;
    wire [1:0]  master_phase;
    wire [3:0]  master_bit;
    wire [7:0]  master_byte;
    wire        master_last_ack;

    //-------------------------------------------------------------------------
    // Counters and edge-detect helper
    //-------------------------------------------------------------------------
    reg [23:0] start_counter;  // counts startup delay after reset
    reg [23:0] poll_counter;   // counts delay between sensor reads
    reg        busy_d;         // delayed copy of i2c_busy for edge detection

    //-------------------------------------------------------------------------
    // Wrapper FSM state definitions
    //-------------------------------------------------------------------------
    // R_STARTUP      : wait initial startup delay after reset
    // R_WAIT_POLL    : wait until it is time for the next sensor read
    // R_ASSERT_EN    : raise enable to request a transaction from i2c_master
    // R_WAIT_BUSY_HI : wait for i2c_master to acknowledge request by going busy
    // R_WAIT_BUSY_LO : wait for i2c_master to finish the transaction
    // R_CAPTURE      : store returned data and pulse tx_done
    // R_DONE         : small cleanup state before returning to wait state
    //-------------------------------------------------------------------------
    localparam [2:0]
        R_STARTUP      = 3'd0,
        R_WAIT_POLL    = 3'd1,
        R_ASSERT_EN    = 3'd2,
        R_WAIT_BUSY_HI = 3'd3,
        R_WAIT_BUSY_LO = 3'd4,
        R_CAPTURE      = 3'd5,
        R_DONE         = 3'd6;

    // Current state of this wrapper FSM.
    reg [2:0] rstate;

    // Expose the lower-level master's busy signal directly.
    assign busy = i2c_busy;

    //-------------------------------------------------------------------------
    // Lower-level I2C master instance
    //-------------------------------------------------------------------------
    // This module handles the actual I2C signaling on SDA/SCL.
    // We configure it here for:
    //   - 2 data bytes returned from the sensor,
    //   - 1 register-address byte,
    //   - 7-bit device address.
    //-------------------------------------------------------------------------
    i2c_master #(
        .NUMBER_OF_DATA_BYTES(2),
        .NUMBER_OF_REGISTER_BYTES(1),
        .ADDRESS_WIDTH(7),
        .CHECK_FOR_CLOCK_STRETCHING(0),
        .CLOCK_STRETCHING_MAX_COUNT('h00)
    ) u_i2c_master (
        .clock                 (clk_50),
        .reset_n               (reset_n),
        .enable                (enable),
        .read_write            (read_write),
        .mosi_data             (mosi_data),
        .register_address      (register_address),
        .device_address        (device_address),
        .divider               (I2C_DIVIDER),
        .miso_data             (miso_data),
        .busy                  (i2c_busy),

        .dbg_state             (master_state),
        .dbg_process_counter   (master_phase),
        .dbg_bit_counter       (master_bit),
        .dbg_byte_counter      (master_byte),
        .dbg_last_acknowledge  (master_last_ack),

        .external_serial_data  (tmp_sda),
        .external_serial_clock (tmp_scl)
    );

    //-------------------------------------------------------------------------
    // Main control FSM
    //-------------------------------------------------------------------------
    // This always block sequences the read requests.
    // All behavior is synchronous to clk_50 and reset by reset_n.
    //-------------------------------------------------------------------------
    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            // Initialize all control outputs, state, counters, and debug latches.
            enable                   <= 1'b0;
            read_write               <= 1'b1;              // configure for reads
            mosi_data                <= 16'h0000;          // unused in this read-only use case
            register_address         <= REG_TEMPERATURE;   // select temperature register
            device_address           <= TMP117_ADDR;       // select TMP117 address
            raw_id                   <= 16'h0000;
            tx_done                  <= 1'b0;
            dbg_state                <= R_STARTUP;
            rstate                   <= R_STARTUP;
            start_counter            <= 24'd0;
            poll_counter             <= 24'd0;
            busy_d                   <= 1'b0;
            busy_seen                <= 1'b0;
            complete_seen            <= 1'b0;
            latched_master_state     <= 4'h0;
            latched_master_phase     <= 2'b00;
            latched_master_bit       <= 4'h0;
            latched_master_byte      <= 8'h00;
            latched_master_last_ack  <= 1'b0;
        end else begin
            // Keep a delayed copy of busy so we can detect the falling edge when
            // the transaction completes.
            busy_d  <= i2c_busy;

            // tx_done is intended to be a one-clock pulse, so clear it by default
            // every cycle unless we are explicitly asserting it in R_CAPTURE.
            tx_done <= 1'b0;

            // Sticky flag to indicate that the master did in fact begin a
            // transaction at some point after reset.
            if (i2c_busy)
                busy_seen <= 1'b1;

            case (rstate)
                //=============================================================
                // R_STARTUP
                // Wait some time after reset before attempting the first I2C
                // access. This avoids talking to the sensor too early.
                //=============================================================
                R_STARTUP: begin
                    enable    <= 1'b0;
                    dbg_state <= R_STARTUP;

                    if (start_counter >= STARTUP_TICKS)
                        rstate <= R_WAIT_POLL;
                    else
                        start_counter <= start_counter + 1'b1;
                end

                //=============================================================
                // R_WAIT_POLL
                // Idle state between reads.
                // The module waits here until the programmable poll interval
                // expires. Once that happens, it prepares a new temperature-read
                // request and advances to the enable-assert state.
                //=============================================================
                R_WAIT_POLL: begin
                    enable    <= 1'b0;
                    dbg_state <= R_WAIT_POLL;

                    // Only count toward the next poll when the I2C master is idle.
                    if (!i2c_busy) begin
                        if (poll_counter >= POLL_DIVIDER) begin
                            poll_counter     <= 24'd0;

                            // Configure the upcoming transaction.
                            read_write       <= 1'b1;             // read
                            mosi_data        <= 16'h0000;         // unused placeholder
                            register_address <= REG_TEMPERATURE;  // temperature register
                            device_address   <= TMP117_ADDR;      // sensor address

                            rstate           <= R_ASSERT_EN;
                        end else begin
                            poll_counter <= poll_counter + 1'b1;
                        end
                    end else begin
                        // Defensive behavior: if the master is somehow still busy,
                        // do not continue counting the poll interval.
                        poll_counter <= 24'd0;
                    end
                end

                //=============================================================
                // R_ASSERT_EN
                // Raise `enable` for one request window so the lower-level I2C
                // master starts a transaction.
                //=============================================================
                R_ASSERT_EN: begin
                    enable    <= 1'b1;
                    dbg_state <= R_ASSERT_EN;
                    rstate    <= R_WAIT_BUSY_HI;
                end

                //=============================================================
                // R_WAIT_BUSY_HI
                // Wait for the I2C master to acknowledge the request by asserting
                // its busy signal. Once busy goes high, the transaction is in
                // progress and we can drop enable.
                //=============================================================
                R_WAIT_BUSY_HI: begin
                    enable    <= 1'b1;
                    dbg_state <= R_WAIT_BUSY_HI;

                    if (i2c_busy) begin
                        enable <= 1'b0;
                        rstate <= R_WAIT_BUSY_LO;
                    end
                end

                //=============================================================
                // R_WAIT_BUSY_LO
                // Wait for the I2C master to finish the transaction.
                // We detect completion on the busy falling edge:
                //   previous cycle busy_d = 1
                //   current cycle  i2c_busy = 0
                //=============================================================
                R_WAIT_BUSY_LO: begin
                    enable    <= 1'b0;
                    dbg_state <= R_WAIT_BUSY_LO;

                    if (busy_d && !i2c_busy)
                        rstate <= R_CAPTURE;
                end

                //=============================================================
                // R_CAPTURE
                // The read has completed. Capture the returned data, pulse the
                // done flag, and snapshot low-level master debug information.
                //=============================================================
                R_CAPTURE: begin
                    enable                  <= 1'b0;
                    dbg_state               <= R_CAPTURE;

                    // Store the 16-bit temperature word returned by TMP117.
                    raw_id                  <= miso_data;

                    // One-cycle completion pulse.
                    tx_done                 <= 1'b1;

                    // Sticky completion flag for debugging.
                    complete_seen           <= 1'b1;

                    // Save a snapshot of the low-level master's debug outputs.
                    latched_master_state    <= master_state;
                    latched_master_phase    <= master_phase;
                    latched_master_bit      <= master_bit;
                    latched_master_byte     <= master_byte;
                    latched_master_last_ack <= master_last_ack;

                    rstate                  <= R_DONE;
                end

                //=============================================================
                // R_DONE
                // Cleanup / handoff state.
                // After one cycle here, the FSM goes back to waiting for the
                // next poll interval.
                //=============================================================
                R_DONE: begin
                    enable    <= 1'b0;
                    dbg_state <= R_DONE;
                    rstate    <= R_WAIT_POLL;
                end

                //=============================================================
                // default
                // Safety fallback.
                //=============================================================
                default: begin
                    enable    <= 1'b0;
                    dbg_state <= R_STARTUP;
                    rstate    <= R_STARTUP;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
