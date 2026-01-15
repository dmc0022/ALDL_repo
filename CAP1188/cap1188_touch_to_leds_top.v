// cap1188_touch_to_leds_top.v
// CAP1188 touch -> DE10 LEDs + CAP1188 LED pins (auto-linked).
//
// Init sequence:
//   0x71 = 0x00   LED Output Type (open-drain sink)
//   0x73 = 0x00   LED Polarity (inverted: external LED sink)
//   0x72 = 0xFF   Sensor Input LED Linking (C1..C8 linked to LED1..LED8)
//
// Poll loop:
//   touch_status = read(0x03);   // Sensor Input Status (C1..C8)
//   write(0x00, 0x00);           // clear INT / latches
//
// DE10:
//   LEDR[7:0] show touch_status bits.
// CAP1188:
//   LED pins L1..L8 follow touches automatically via linking (0x72).

`default_nettype none

module cap1188_touch_to_leds_top #(
    parameter [6:0] DEV_ADDR = 7'h28   // CAP1188 I2C address
)(
    input  wire       clk_50,
    input  wire       reset_n,   // active-low

    inout  wire       i2c_sda,
    output wire       i2c_scl,

    output wire [9:0] LEDR
);

    // Active-high reset for I2C core
    wire rst = ~reset_n;

    // ------------------------------------------------------------
    // Low-level I2C engine
    // ------------------------------------------------------------
    localparam [2:0] DRVR_CMD_NONE       = 3'd0;
    localparam [2:0] DRVR_CMD_WRITE      = 3'd1;
    localparam [2:0] DRVR_CMD_READ       = 3'd2;
    localparam [2:0] DRVR_CMD_START_COND = 3'd3;
    localparam [2:0] DRVR_CMD_STOP_COND  = 3'd4;

    reg  [2:0] drv_command = DRVR_CMD_NONE;
    reg  [7:0] drv_tx_byte = 8'h00;
    wire       drv_ack;

    wire [7:0] drv_read_byte;
    wire       drv_busy;
    wire       drv_data_valid;
    wire       drv_done;

    // open-drain SDA wiring
    wire sda_in;
    wire sda_out;
    wire scl_out;

    assign sda_in  = i2c_sda;
    assign i2c_scl = scl_out;
    assign i2c_sda = (sda_out) ? 1'bz : 1'b0;

    gI2C_low_level_tx_rx #(
        .TICKS_PER_I2C_CLK_PERIOD(400)   // ~125 kHz at 50 MHz
    ) i2c_core (
        .clk       (clk_50),
        .rst       (rst),
        .command   (drv_command),
        .tx_byte   (drv_tx_byte),
        .ACK       (drv_ack),
        .read_byte (drv_read_byte),
        .busy      (drv_busy),
        .data_valid(drv_data_valid),
        .done      (drv_done),
        .i_sda     (sda_in),
        .o_sda     (sda_out),
        .o_scl     (scl_out)
    );

    // ------------------------------------------------------------
    // CAP1188 registers
    // ------------------------------------------------------------
    wire [7:0] addr_w = {DEV_ADDR, 1'b0};
    wire [7:0] addr_r = {DEV_ADDR, 1'b1};

    localparam [7:0] REG_MAIN_CTRL      = 8'h00;
    localparam [7:0] REG_SENSOR_STATUS  = 8'h03;
    localparam [7:0] REG_LED_OUTPUT_TYP = 8'h71;
    localparam [7:0] REG_LED_POLARITY   = 8'h73;
    localparam [7:0] REG_SENSOR_LED_LNK = 8'h72;

    // Init values
    localparam [7:0] VAL_LED_OUTPUT_TYP = 8'h00; // open-drain
    localparam [7:0] VAL_LED_POLARITY   = 8'h00; // inverted (sink on '1')
    localparam [7:0] VAL_LED_LINK_ALL   = 8'hFF; // link CS1..CS8 -> LED1..LED8
    localparam [7:0] VAL_MAINCLR        = 8'h00; // clear INT by writing 0x00

    reg  [7:0] touch_status = 8'h00;

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    localparam [5:0]
        S_IDLE               = 6'd0,

        // --- Config LED output type: 0x71 = 0x00 ---
        S_W71_START_TRIG     = 6'd1,
        S_W71_START_WAIT     = 6'd2,
        S_W71_ADDR_SETUP     = 6'd3,
        S_W71_ADDR_TRIG      = 6'd4,
        S_W71_ADDR_WAIT      = 6'd5,
        S_W71_REG_SETUP      = 6'd6,
        S_W71_REG_TRIG       = 6'd7,
        S_W71_REG_WAIT       = 6'd8,
        S_W71_DATA_SETUP     = 6'd9,
        S_W71_DATA_TRIG      = 6'd10,
        S_W71_DATA_WAIT      = 6'd11,
        S_W71_STOP_TRIG      = 6'd12,
        S_W71_STOP_WAIT      = 6'd13,

        // --- Config LED polarity: 0x73 = 0x00 ---
        S_W73_START_TRIG     = 6'd14,
        S_W73_START_WAIT     = 6'd15,
        S_W73_ADDR_SETUP     = 6'd16,
        S_W73_ADDR_TRIG      = 6'd17,
        S_W73_ADDR_WAIT      = 6'd18,
        S_W73_REG_SETUP      = 6'd19,
        S_W73_REG_TRIG       = 6'd20,
        S_W73_REG_WAIT       = 6'd21,
        S_W73_DATA_SETUP     = 6'd22,
        S_W73_DATA_TRIG      = 6'd23,
        S_W73_DATA_WAIT      = 6'd24,
        S_W73_STOP_TRIG      = 6'd25,
        S_W73_STOP_WAIT      = 6'd26,

        // --- Link sensors to LEDs: 0x72 = 0xFF ---
        S_W72_START_TRIG     = 6'd27,
        S_W72_START_WAIT     = 6'd28,
        S_W72_ADDR_SETUP     = 6'd29,
        S_W72_ADDR_TRIG      = 6'd30,
        S_W72_ADDR_WAIT      = 6'd31,
        S_W72_REG_SETUP      = 6'd32,
        S_W72_REG_TRIG       = 6'd33,
        S_W72_REG_WAIT       = 6'd34,
        S_W72_DATA_SETUP     = 6'd35,
        S_W72_DATA_TRIG      = 6'd36,
        S_W72_DATA_WAIT      = 6'd37,
        S_W72_STOP_TRIG      = 6'd38,
        S_W72_STOP_WAIT      = 6'd39,

        // --- Poll: read 0x03 ---
        S_R03_START_TRIG     = 6'd40,
        S_R03_START_WAIT     = 6'd41,
        S_R03_ADDRW_SETUP    = 6'd42,
        S_R03_ADDRW_TRIG     = 6'd43,
        S_R03_ADDRW_WAIT     = 6'd44,
        S_R03_REG_SETUP      = 6'd45,
        S_R03_REG_TRIG       = 6'd46,
        S_R03_REG_WAIT       = 6'd47,
        S_R03_RS_TRIG        = 6'd48,
        S_R03_RS_WAIT        = 6'd49,
        S_R03_ADDRR_SETUP    = 6'd50,
        S_R03_ADDRR_TRIG     = 6'd51,
        S_R03_ADDRR_WAIT     = 6'd52,
        S_R03_READ_TRIG      = 6'd53,
        S_R03_READ_WAIT      = 6'd54,
        S_R03_STOP_TRIG      = 6'd55,
        S_R03_STOP_WAIT      = 6'd56,

        // --- Clear INT / latches: write 0x00 = 0x00 ---
        S_W00_START_TRIG     = 6'd57,
        S_W00_START_WAIT     = 6'd58,
        S_W00_ADDR_SETUP     = 6'd59,
        S_W00_ADDR_TRIG      = 6'd60,
        S_W00_ADDR_WAIT      = 6'd61,
        S_W00_REG_SETUP      = 6'd62,
        S_W00_REG_TRIG       = 6'd63,
        S_W00_REG_WAIT       = 6'd64,
        S_W00_DATA_SETUP     = 6'd65,
        S_W00_DATA_TRIG      = 6'd66,
        S_W00_DATA_WAIT      = 6'd67,
        S_W00_STOP_TRIG      = 6'd68,
        S_W00_STOP_WAIT      = 6'd69;

    reg [5:0] state = S_IDLE;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            drv_command  <= DRVR_CMD_NONE;
            drv_tx_byte  <= 8'h00;
            touch_status <= 8'h00;
        end else begin
            drv_command <= DRVR_CMD_NONE; // default

            case (state)
            // ---------------- LED CONFIG -----------------
            S_IDLE: begin
                if (!drv_busy)
                    state <= S_W71_START_TRIG;
            end

            // 0x71 = 0x00
            S_W71_START_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_W71_START_WAIT;
            end
            S_W71_START_WAIT: if (drv_done) state <= S_W71_ADDR_SETUP;

            S_W71_ADDR_SETUP: begin
                drv_tx_byte <= addr_w;
                state       <= S_W71_ADDR_TRIG;
            end
            S_W71_ADDR_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W71_ADDR_WAIT;
            end
            S_W71_ADDR_WAIT: if (drv_done) state <= S_W71_REG_SETUP;

            S_W71_REG_SETUP: begin
                drv_tx_byte <= REG_LED_OUTPUT_TYP;
                state       <= S_W71_REG_TRIG;
            end
            S_W71_REG_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W71_REG_WAIT;
            end
            S_W71_REG_WAIT: if (drv_done) state <= S_W71_DATA_SETUP;

            S_W71_DATA_SETUP: begin
                drv_tx_byte <= VAL_LED_OUTPUT_TYP;
                state       <= S_W71_DATA_TRIG;
            end
            S_W71_DATA_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W71_DATA_WAIT;
            end
            S_W71_DATA_WAIT: if (drv_done) state <= S_W71_STOP_TRIG;

            S_W71_STOP_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_STOP_COND;
                state       <= S_W71_STOP_WAIT;
            end
            S_W71_STOP_WAIT: if (drv_done) state <= S_W73_START_TRIG;

            // 0x73 = 0x00
            S_W73_START_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_W73_START_WAIT;
            end
            S_W73_START_WAIT: if (drv_done) state <= S_W73_ADDR_SETUP;

            S_W73_ADDR_SETUP: begin
                drv_tx_byte <= addr_w;
                state       <= S_W73_ADDR_TRIG;
            end
            S_W73_ADDR_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W73_ADDR_WAIT;
            end
            S_W73_ADDR_WAIT: if (drv_done) state <= S_W73_REG_SETUP;

            S_W73_REG_SETUP: begin
                drv_tx_byte <= REG_LED_POLARITY;
                state       <= S_W73_REG_TRIG;
            end
            S_W73_REG_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W73_REG_WAIT;
            end
            S_W73_REG_WAIT: if (drv_done) state <= S_W73_DATA_SETUP;

            S_W73_DATA_SETUP: begin
                drv_tx_byte <= VAL_LED_POLARITY;
                state       <= S_W73_DATA_TRIG;
            end
            S_W73_DATA_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W73_DATA_WAIT;
            end
            S_W73_DATA_WAIT: if (drv_done) state <= S_W73_STOP_TRIG;

            S_W73_STOP_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_STOP_COND;
                state       <= S_W73_STOP_WAIT;
            end
            S_W73_STOP_WAIT: if (drv_done) state <= S_W72_START_TRIG;

            // 0x72 = 0xFF (link CSx to LEDx)
            S_W72_START_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_W72_START_WAIT;
            end
            S_W72_START_WAIT: if (drv_done) state <= S_W72_ADDR_SETUP;

            S_W72_ADDR_SETUP: begin
                drv_tx_byte <= addr_w;
                state       <= S_W72_ADDR_TRIG;
            end
            S_W72_ADDR_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W72_ADDR_WAIT;
            end
            S_W72_ADDR_WAIT: if (drv_done) state <= S_W72_REG_SETUP;

            S_W72_REG_SETUP: begin
                drv_tx_byte <= REG_SENSOR_LED_LNK;
                state       <= S_W72_REG_TRIG;
            end
            S_W72_REG_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W72_REG_WAIT;
            end
            S_W72_REG_WAIT: if (drv_done) state <= S_W72_DATA_SETUP;

            S_W72_DATA_SETUP: begin
                drv_tx_byte <= VAL_LED_LINK_ALL;
                state       <= S_W72_DATA_TRIG;
            end
            S_W72_DATA_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W72_DATA_WAIT;
            end
            S_W72_DATA_WAIT: if (drv_done) state <= S_W72_STOP_TRIG;

            S_W72_STOP_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_STOP_COND;
                state       <= S_W72_STOP_WAIT;
            end
            S_W72_STOP_WAIT: if (drv_done) state <= S_R03_START_TRIG;

            // ---------------- POLL LOOP ------------------

            // Read 0x03
            S_R03_START_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_R03_START_WAIT;
            end
            S_R03_START_WAIT: if (drv_done) state <= S_R03_ADDRW_SETUP;

            S_R03_ADDRW_SETUP: begin
                drv_tx_byte <= addr_w;
                state       <= S_R03_ADDRW_TRIG;
            end
            S_R03_ADDRW_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_R03_ADDRW_WAIT;
            end
            S_R03_ADDRW_WAIT: if (drv_done) state <= S_R03_REG_SETUP;

            S_R03_REG_SETUP: begin
                drv_tx_byte <= REG_SENSOR_STATUS;
                state       <= S_R03_REG_TRIG;
            end
            S_R03_REG_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_R03_REG_WAIT;
            end
            S_R03_REG_WAIT: if (drv_done) state <= S_R03_RS_TRIG;

            S_R03_RS_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_R03_RS_WAIT;
            end
            S_R03_RS_WAIT: if (drv_done) state <= S_R03_ADDRR_SETUP;

            S_R03_ADDRR_SETUP: begin
                drv_tx_byte <= addr_r;
                state       <= S_R03_ADDRR_TRIG;
            end
            S_R03_ADDRR_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_R03_ADDRR_WAIT;
            end
            S_R03_ADDRR_WAIT: if (drv_done) state <= S_R03_READ_TRIG;

            S_R03_READ_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_READ;
                state       <= S_R03_READ_WAIT;
            end
            S_R03_READ_WAIT: begin
                if (drv_data_valid) begin
                    touch_status <= drv_read_byte;
                end
                if (drv_done) state <= S_R03_STOP_TRIG;
            end

            S_R03_STOP_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_STOP_COND;
                state       <= S_R03_STOP_WAIT;
            end
            S_R03_STOP_WAIT: if (drv_done) state <= S_W00_START_TRIG;

            // Write 0x00 = 0x00 (clear INT / latches)
            S_W00_START_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_START_COND;
                state       <= S_W00_START_WAIT;
            end
            S_W00_START_WAIT: if (drv_done) state <= S_W00_ADDR_SETUP;

            S_W00_ADDR_SETUP: begin
                drv_tx_byte <= addr_w;
                state       <= S_W00_ADDR_TRIG;
            end
            S_W00_ADDR_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W00_ADDR_WAIT;
            end
            S_W00_ADDR_WAIT: if (drv_done) state <= S_W00_REG_SETUP;

            S_W00_REG_SETUP: begin
                drv_tx_byte <= REG_MAIN_CTRL;
                state       <= S_W00_REG_TRIG;
            end
            S_W00_REG_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W00_REG_WAIT;
            end
            S_W00_REG_WAIT: if (drv_done) state <= S_W00_DATA_SETUP;

            S_W00_DATA_SETUP: begin
                drv_tx_byte <= VAL_MAINCLR;
                state       <= S_W00_DATA_TRIG;
            end
            S_W00_DATA_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_WRITE;
                state       <= S_W00_DATA_WAIT;
            end
            S_W00_DATA_WAIT: if (drv_done) state <= S_W00_STOP_TRIG;

            S_W00_STOP_TRIG: if (!drv_busy) begin
                drv_command <= DRVR_CMD_STOP_COND;
                state       <= S_W00_STOP_WAIT;
            end
            S_W00_STOP_WAIT: if (drv_done) state <= S_R03_START_TRIG; // loop

            default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    // DE10 LEDs: show current touch status
    // ------------------------------------------------------------
    assign LEDR[7:0] = touch_status; // 1 = touch detected on Cx
    assign LEDR[9:8] = 2'b00;

endmodule

`default_nettype wire
