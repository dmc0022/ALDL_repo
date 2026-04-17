`timescale 1ns/1ps
`default_nettype none
// TMP117 sensor information:
//    This sensor can read temperatures from -255 to 255 degrees C. This value is 
//    calculated from using the raw 16-bit temperature value read from the sensor
//    with a resolution of 0.0078 C. 

module tmp117_reader_completion_debug #(
    parameter integer CLK_FREQ_HZ  = 50_000_000,
    parameter integer I2C_FREQ_HZ  = 50_000,
    parameter [6:0]  TMP117_ADDR   = 7'h48,
    parameter [23:0] STARTUP_TICKS = 24'd5_000_000,
    parameter [23:0] POLL_DIVIDER  = 24'd10_000_000
)(
    input  wire        clk_50,
    input  wire        reset_n,
    inout  wire        tmp_scl,
    inout  wire        tmp_sda,
    output reg [15:0]  raw_id,
    output wire        busy,
    output reg         tx_done,
    output reg [2:0]   dbg_state,

    output reg         busy_seen,
    output reg         complete_seen,

    output reg [3:0]   latched_master_state,
    output reg [1:0]   latched_master_phase,
    output reg [3:0]   latched_master_bit,
    output reg [7:0]   latched_master_byte,
    output reg         latched_master_last_ack
);

    // TMP117 temperature register
    localparam [7:0] REG_TEMPERATURE = 8'h00;
    localparam integer I2C_DIVIDER_INT = (CLK_FREQ_HZ / (I2C_FREQ_HZ * 4)) - 1;
    localparam [15:0] I2C_DIVIDER = (I2C_DIVIDER_INT < 0) ? 16'd0 : I2C_DIVIDER_INT[15:0];

    reg         enable;
    reg         read_write;
    reg [15:0]  mosi_data;
    reg [7:0]   register_address;
    reg [6:0]   device_address;
    wire [15:0] miso_data;
    wire        i2c_busy;

    wire [3:0]  master_state;
    wire [1:0]  master_phase;
    wire [3:0]  master_bit;
    wire [7:0]  master_byte;
    wire        master_last_ack;

    reg [23:0] start_counter;
    reg [23:0] poll_counter;
    reg        busy_d;

    localparam [2:0]
        R_STARTUP      = 3'd0,
        R_WAIT_POLL    = 3'd1,
        R_ASSERT_EN    = 3'd2,
        R_WAIT_BUSY_HI = 3'd3,
        R_WAIT_BUSY_LO = 3'd4,
        R_CAPTURE      = 3'd5,
        R_DONE         = 3'd6;

    reg [2:0] rstate;

    assign busy = i2c_busy;

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

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            enable                   <= 1'b0;
            read_write               <= 1'b1;
            mosi_data                <= 16'h0000;
            register_address         <= REG_TEMPERATURE;
            device_address           <= TMP117_ADDR;
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
            busy_d  <= i2c_busy;
            tx_done <= 1'b0;

            if (i2c_busy)
                busy_seen <= 1'b1;

            case (rstate)
                R_STARTUP: begin
                    enable    <= 1'b0;
                    dbg_state <= R_STARTUP;
                    if (start_counter >= STARTUP_TICKS)
                        rstate <= R_WAIT_POLL;
                    else
                        start_counter <= start_counter + 1'b1;
                end

                R_WAIT_POLL: begin
                    enable    <= 1'b0;
                    dbg_state <= R_WAIT_POLL;
                    if (!i2c_busy) begin
                        if (poll_counter >= POLL_DIVIDER) begin
                            poll_counter     <= 24'd0;
                            read_write       <= 1'b1;
                            mosi_data        <= 16'h0000;
                            register_address <= REG_TEMPERATURE;
                            device_address   <= TMP117_ADDR;
                            rstate           <= R_ASSERT_EN;
                        end else begin
                            poll_counter <= poll_counter + 1'b1;
                        end
                    end else begin
                        poll_counter <= 24'd0;
                    end
                end

                R_ASSERT_EN: begin
                    enable    <= 1'b1;
                    dbg_state <= R_ASSERT_EN;
                    rstate    <= R_WAIT_BUSY_HI;
                end

                R_WAIT_BUSY_HI: begin
                    enable    <= 1'b1;
                    dbg_state <= R_WAIT_BUSY_HI;
                    if (i2c_busy) begin
                        enable <= 1'b0;
                        rstate <= R_WAIT_BUSY_LO;
                    end
                end

                R_WAIT_BUSY_LO: begin
                    enable    <= 1'b0;
                    dbg_state <= R_WAIT_BUSY_LO;
                    if (busy_d && !i2c_busy)
                        rstate <= R_CAPTURE;
                end

                R_CAPTURE: begin
                    enable                  <= 1'b0;
                    dbg_state               <= R_CAPTURE;
                    raw_id                  <= miso_data;
                    tx_done                 <= 1'b1;
                    complete_seen           <= 1'b1;
                    latched_master_state    <= master_state;
                    latched_master_phase    <= master_phase;
                    latched_master_bit      <= master_bit;
                    latched_master_byte     <= master_byte;
                    latched_master_last_ack <= master_last_ack;
                    rstate                  <= R_DONE;
                end

                R_DONE: begin
                    enable    <= 1'b0;
                    dbg_state <= R_DONE;
                    rstate    <= R_WAIT_POLL;
                end

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
