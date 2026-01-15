// ft6336_touch.v
// FT6336G capacitive touch driver using gI2C_low_level_tx_rx I2C master
// POLLING-BASED VERSION (does NOT rely on CTP_INT)
// - clk: 50 MHz
// - I2C: ~100 kHz (TICKS_PER_I2C_CLK_PERIOD = 500 for 50 MHz)
// - Periodically polls FT6336 for TD_STATUS, P1_XH, P1_XL, P1_YH, P1_YL
// - Outputs 12-bit touch_x/touch_y, touch_down, touch_valid

`timescale 1ns/1ps
`default_nettype none

module ft6336_touch #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer I2C_FREQ_HZ = 100_000,
    // Polling rate: e.g. 200 Hz -> every 5 ms
    parameter integer POLL_HZ     = 200
)(
    input  wire        clk,
    input  wire        reset_n,   // active low

    // FT6336 pins
    output wire        CTP_SCL,
    inout  wire        CTP_SDA,
    output reg         CTP_RST,
    input  wire        CTP_INT,   // UNUSED in this version (polled)

    // Decoded touch info
    output reg         touch_valid, // one-cycle pulse when new sample ready
    output reg         touch_down,  // 1 when at least one touch
    output reg [11:0]  touch_x,
    output reg [11:0]  touch_y
);

    //----------------------------------------------------------------------
    // I2C master instantiation (gI2C_low_level_tx_rx)
    //----------------------------------------------------------------------

    // TICKS_PER_I2C_CLK_PERIOD = clk / I2C_freq
    // For 50 MHz and 100 kHz: 50e6 / 1e5 = 500
    localparam integer TICKS_PER_I2C_CLK_PERIOD = CLK_FREQ_HZ / I2C_FREQ_HZ;

    // Polling interval in clock cycles
    localparam integer POLL_INTERVAL_TICKS = CLK_FREQ_HZ / POLL_HZ;
    localparam integer POLL_W              = $clog2(POLL_INTERVAL_TICKS);

    // Low-level I2C signals
    reg  [2:0] i2c_command;   // pulse commands into gI2C
    reg  [7:0] i2c_tx_byte;
    reg        i2c_ack;

    wire [7:0] i2c_read_byte;
    wire       i2c_busy;
    wire       i2c_data_valid;
    wire       i2c_done;

    // SDA open-drain wiring
    wire sda_out;     // from low-level driver: 0=drive low, 1=release (Hi-Z)
    wire sda_in;      // to low-level driver

    assign CTP_SDA = (sda_out == 1'b0) ? 1'b0 : 1'bz;
    assign sda_in  = CTP_SDA;

    // SCL driven by low-level I2C master
    wire scl_out;
    assign CTP_SCL = scl_out;

    // Active-high reset for gI2C (invert reset_n)
    wire i2c_rst = ~reset_n;

    gI2C_low_level_tx_rx #(
        .TICKS_PER_I2C_CLK_PERIOD(TICKS_PER_I2C_CLK_PERIOD)
    ) i2c_master (
        .clk        (clk),
        .rst        (i2c_rst),
        .command    (i2c_command),
        .tx_byte    (i2c_tx_byte),
        .ACK        (i2c_ack),
        .read_byte  (i2c_read_byte),
        .busy       (i2c_busy),
        .data_valid (i2c_data_valid),
        .done       (i2c_done),
        .i_sda      (sda_in),
        .o_sda      (sda_out),
        .o_scl      (scl_out)
    );

    //----------------------------------------------------------------------
    // FT6336 high-level polling FSM
    //----------------------------------------------------------------------

    // FT6336 I2C address: 0x38 -> write 0x70, read 0x71
    localparam [7:0] FT_ADDR_W       = 8'h70;
    localparam [7:0] FT_ADDR_R       = 8'h71;
    localparam [7:0] REG_TD_STATUS   = 8'h02;  // starting register address

    // Commands for gI2C (must match gI2C_low_level_tx_rx localparams)
    localparam [2:0]
        DRVR_CMD_NONE       = 3'd0,
        DRVR_CMD_WRITE      = 3'd1,
        DRVR_CMD_READ       = 3'd2,
        DRVR_CMD_START_COND = 3'd3,
        DRVR_CMD_STOP_COND  = 3'd4;

    // FSM states: explicit REQ/WAIT for each I2C step to ensure 1-cycle command pulses
    localparam [5:0]
        ST_RST_HOLD      = 6'd0,
        ST_RST_REL       = 6'd1,
        ST_IDLE           = 6'd2,  // wait for poll timer
        ST_START1_REQ    = 6'd3,
        ST_START1_WAIT   = 6'd4,
        ST_ADDRW_REQ     = 6'd5,
        ST_ADDRW_WAIT    = 6'd6,
        ST_REG_REQ       = 6'd7,
        ST_REG_WAIT      = 6'd8,
        ST_START2_REQ    = 6'd9,
        ST_START2_WAIT   = 6'd10,
        ST_ADDRR_REQ     = 6'd11,
        ST_ADDRR_WAIT    = 6'd12,
        ST_READ0_REQ     = 6'd13,
        ST_READ0_WAIT    = 6'd14,
        ST_READ1_REQ     = 6'd15,
        ST_READ1_WAIT    = 6'd16,
        ST_READ2_REQ     = 6'd17,
        ST_READ2_WAIT    = 6'd18,
        ST_READ3_REQ     = 6'd19,
        ST_READ3_WAIT    = 6'd20,
        ST_READ4_REQ     = 6'd21,
        ST_READ4_WAIT    = 6'd22,
        ST_STOP_REQ      = 6'd23,
        ST_STOP_WAIT     = 6'd24,
        ST_PROCESS       = 6'd25;

    reg [5:0] state;

    // CTP_RST power-on reset timer (~2 ms)
    localparam integer RST_COUNT_MAX = 100_000; // at 50 MHz -> 2 ms
    localparam integer RST_W         = $clog2(RST_COUNT_MAX);
    reg [RST_W-1:0] rst_cnt;

    // Polling timer
    reg [POLL_W-1:0] poll_cnt;

    // Registers to hold FT6336 bytes
    reg [7:0] td_status;
    reg [7:0] p1_xh, p1_xl, p1_yh, p1_yl;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state       <= ST_RST_HOLD;
            CTP_RST     <= 1'b0;
            rst_cnt     <= {RST_W{1'b0}};
            poll_cnt    <= {POLL_W{1'b0}};

            i2c_command <= DRVR_CMD_NONE;
            i2c_tx_byte <= 8'h00;
            i2c_ack     <= 1'b1;

            td_status   <= 8'h00;
            p1_xh       <= 8'h00;
            p1_xl       <= 8'h00;
            p1_yh       <= 8'h00;
            p1_yl       <= 8'h00;

            touch_valid <= 1'b0;
            touch_down  <= 1'b0;
            touch_x     <= 12'd0;
            touch_y     <= 12'd0;
        end else begin
            // Default: no I2C command this cycle, no touch_valid pulse
            i2c_command <= DRVR_CMD_NONE;
            touch_valid <= 1'b0;

            case (state)
                //----------------------------------------------------------
                // Hold FT6336 in reset, then release
                //----------------------------------------------------------
                ST_RST_HOLD: begin
                    CTP_RST <= 1'b0;
                    rst_cnt <= rst_cnt + 1'b1;
                    if (rst_cnt == RST_COUNT_MAX-1) begin
                        rst_cnt <= {RST_W{1'b0}};
                        state   <= ST_RST_REL;
                    end
                end

                ST_RST_REL: begin
                    CTP_RST  <= 1'b1;
                    poll_cnt <= {POLL_W{1'b0}};
                    state    <= ST_IDLE;
                end

                //----------------------------------------------------------
                // IDLE: wait until poll timer expires, then start a read
                //----------------------------------------------------------
                ST_IDLE: begin
                    // Increment poll timer until we reach POLL_INTERVAL_TICKS
                    if (poll_cnt == POLL_INTERVAL_TICKS-1) begin
                        poll_cnt <= {POLL_W{1'b0}};
                        state    <= ST_START1_REQ;  // begin transaction
                    end else begin
                        poll_cnt <= poll_cnt + 1'b1;
                    end
                end

                //----------------------------------------------------------
                // First transaction: send START + address(write) + reg 0x02
                //----------------------------------------------------------
                ST_START1_REQ: begin
                    i2c_command <= DRVR_CMD_START_COND;
                    state       <= ST_START1_WAIT;
                end

                ST_START1_WAIT: begin
                    if (i2c_done) begin
                        i2c_tx_byte <= FT_ADDR_W;
                        state       <= ST_ADDRW_REQ;
                    end
                end

                ST_ADDRW_REQ: begin
                    i2c_command <= DRVR_CMD_WRITE;
                    state       <= ST_ADDRW_WAIT;
                end

                ST_ADDRW_WAIT: begin
                    if (i2c_done) begin
                        i2c_tx_byte <= REG_TD_STATUS;
                        state       <= ST_REG_REQ;
                    end
                end

                ST_REG_REQ: begin
                    i2c_command <= DRVR_CMD_WRITE;
                    state       <= ST_REG_WAIT;
                end

                ST_REG_WAIT: begin
                    if (i2c_done) begin
                        state <= ST_START2_REQ; // repeated START
                    end
                end

                //----------------------------------------------------------
                // Second transaction: START + address(read) + 5 data bytes
                //----------------------------------------------------------
                ST_START2_REQ: begin
                    i2c_command <= DRVR_CMD_START_COND;
                    state       <= ST_START2_WAIT;
                end

                ST_START2_WAIT: begin
                    if (i2c_done) begin
                        i2c_tx_byte <= FT_ADDR_R;
                        state       <= ST_ADDRR_REQ;
                    end
                end

                ST_ADDRR_REQ: begin
                    i2c_command <= DRVR_CMD_WRITE;
                    state       <= ST_ADDRR_WAIT;
                end

                ST_ADDRR_WAIT: begin
                    if (i2c_done) begin
                        // Next: TD_STATUS, ACK after this byte
                        i2c_ack <= 1'b1;
                        state   <= ST_READ0_REQ;
                    end
                end

                // READ0: TD_STATUS
                ST_READ0_REQ: begin
                    i2c_command <= DRVR_CMD_READ;
                    state       <= ST_READ0_WAIT;
                end

                ST_READ0_WAIT: begin
                    if (i2c_data_valid) begin
                        td_status <= i2c_read_byte;
                    end
                    if (i2c_done) begin
                        // Next: P1_XH, ACK
                        i2c_ack <= 1'b1;
                        state   <= ST_READ1_REQ;
                    end
                end

                // READ1: P1_XH
                ST_READ1_REQ: begin
                    i2c_command <= DRVR_CMD_READ;
                    state       <= ST_READ1_WAIT;
                end

                ST_READ1_WAIT: begin
                    if (i2c_data_valid) begin
                        p1_xh <= i2c_read_byte;
                    end
                    if (i2c_done) begin
                        // Next: P1_XL, ACK
                        i2c_ack <= 1'b1;
                        state   <= ST_READ2_REQ;
                    end
                end

                // READ2: P1_XL
                ST_READ2_REQ: begin
                    i2c_command <= DRVR_CMD_READ;
                    state       <= ST_READ2_WAIT;
                end

                ST_READ2_WAIT: begin
                    if (i2c_data_valid) begin
                        p1_xl <= i2c_read_byte;
                    end
                    if (i2c_done) begin
                        // Next: P1_YH, ACK
                        i2c_ack <= 1'b1;
                        state   <= ST_READ3_REQ;
                    end
                end

                // READ3: P1_YH
                ST_READ3_REQ: begin
                    i2c_command <= DRVR_CMD_READ;
                    state       <= ST_READ3_WAIT;
                end

                ST_READ3_WAIT: begin
                    if (i2c_data_valid) begin
                        p1_yh <= i2c_read_byte;
                    end
                    if (i2c_done) begin
                        // Next: P1_YL, NACK after last byte
                        i2c_ack <= 1'b0;
                        state   <= ST_READ4_REQ;
                    end
                end

                // READ4: P1_YL (last byte, NACK)
                ST_READ4_REQ: begin
                    i2c_command <= DRVR_CMD_READ;
                    state       <= ST_READ4_WAIT;
                end

                ST_READ4_WAIT: begin
                    if (i2c_data_valid) begin
                        p1_yl <= i2c_read_byte;
                    end
                    if (i2c_done) begin
                        state <= ST_STOP_REQ;
                    end
                end

                //----------------------------------------------------------
                // STOP and process result
                //----------------------------------------------------------
                ST_STOP_REQ: begin
                    i2c_command <= DRVR_CMD_STOP_COND;
                    state       <= ST_STOP_WAIT;
                end

                ST_STOP_WAIT: begin
                    if (i2c_done) begin
                        state <= ST_PROCESS;
                    end
                end

                ST_PROCESS: begin
                    // Decode TD_STATUS and coordinates
                    // td_status[3:0] = number of touch points
                    if (td_status[3:0] != 4'd0) begin
                        touch_down  <= 1'b1;
                        touch_x     <= {p1_xh[3:0], p1_xl};
                        touch_y     <= {p1_yh[3:0], p1_yl};
                        touch_valid <= 1'b1;   // one-cycle pulse
                    end else begin
                        touch_down <= 1'b0;
                        // keep last x/y; no new valid pulse
                    end
                    // Back to idle/polling
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
