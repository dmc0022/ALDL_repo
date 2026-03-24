// cap1188_touch_to_leds_top.v
// CAP1188 touch -> DE10 LEDs + CAP1188 LED pins (auto-linked).
//
// UPDATED: Multi-device (3x CAP1188) on the same I2C bus.
//
// Init sequence per device:
//   0x71 = 0x00   LED Output Type (open-drain sink)
//   0x73 = 0x00   LED Polarity (inverted: external LED sink)
//   0x72 = 0xFF   Sensor Input LED Linking (C1..C8 linked to LED1..LED8)
//
// Poll loop per device:
//   touch_status = read(0x03);   // Sensor Input Status (C1..C8)
//   write(0x00, 0x00);           // clear INT / latches
//
// DE10:
//   LEDR[7:0] shows OR of touch bits across all 3 devices.
// CAP1188:
//   Each chip's LED pins L1..L8 follow touches automatically via linking (0x72).

`default_nettype none

module cap1188_touch_to_leds_top #(
    // Set these to match your hardware strap resistors / ADDR_COMM settings:
    // Common CAP1188 7-bit addresses are 0x28..0x2C
    parameter [6:0] DEV_ADDR0 = 7'h28,
    parameter [6:0] DEV_ADDR1 = 7'h2A,
    parameter [6:0] DEV_ADDR2 = 7'h2C
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

    // ------------------------------------------------------------
    // Multi-device selection
    // ------------------------------------------------------------
    reg  [1:0] dev_idx = 2'd0;     // 0..2
    reg        init_done = 1'b0;   // 0 = still initializing devices, 1 = polling forever

    wire [6:0] cur_dev_addr =
        (dev_idx == 2'd0) ? DEV_ADDR0 :
        (dev_idx == 2'd1) ? DEV_ADDR1 :
                            DEV_ADDR2;

    wire [7:0] addr_w = {cur_dev_addr, 1'b0};
    wire [7:0] addr_r = {cur_dev_addr, 1'b1};

    // Per-device touch status storage
    reg [7:0] touch_status_0 = 8'h00;
    reg [7:0] touch_status_1 = 8'h00;
    reg [7:0] touch_status_2 = 8'h00;

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

    // helper: advance device index 0->1->2->0
    wire [1:0] dev_idx_next = (dev_idx == 2'd2) ? 2'd0 : (dev_idx + 2'd1);

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            state          <= S_IDLE;
            drv_command    <= DRVR_CMD_NONE;
            drv_tx_byte    <= 8'h00;

            dev_idx        <= 2'd0;
            init_done      <= 1'b0;

            touch_status_0 <= 8'h00;
            touch_status_1 <= 8'h00;
            touch_status_2 <= 8'h00;
        end else begin
            drv_command <= DRVR_CMD_NONE; // default

            case (state)
            // ---------------- START -----------------
            S_IDLE: begin
                if (!drv_busy) begin
                    state <= S_W71_START_TRIG;
                end
            end

            // ---------------- INIT PER DEVICE -----------------
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
            S_W72_STOP_WAIT: if (drv_done) begin
                // After finishing init on a device, move to next device until all 3 are done.
                if (!init_done) begin
                    if (dev_idx == 2'd2) begin
                        // finished device 2 -> init done, start polling at device 0
                        init_done <= 1'b1;
                        dev_idx   <= 2'd0;
                        state     <= S_R03_START_TRIG;
                    end else begin
                        // init next device
                        dev_idx <= dev_idx_next;
                        state   <= S_W71_START_TRIG;
                    end
                end else begin
                    // should not happen (init_done forces us into poll loop),
                    // but keep safe behavior:
                    state <= S_R03_START_TRIG;
                end
            end

            // ---------------- POLL LOOP (ROUNDS ROBIN OVER 3 DEVICES) ------------------

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
                drv_command <= DRVR_CMD_START_COND; // repeated start
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
                    // Store to the currently selected device slot
                    case (dev_idx)
                        2'd0: touch_status_0 <= drv_read_byte;
                        2'd1: touch_status_1 <= drv_read_byte;
                        2'd2: touch_status_2 <= drv_read_byte;
                        default: ;
                    endcase
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
            S_W00_STOP_WAIT: if (drv_done) begin
                // Next device in round-robin
                dev_idx <= dev_idx_next;
                state   <= S_R03_START_TRIG;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    // DE10 LEDs: show OR of all touch status bits across devices
    // ------------------------------------------------------------
    wire [7:0] touch_or = touch_status_0 | touch_status_1 | touch_status_2;

    assign LEDR[7:0] = touch_or;
    assign LEDR[9:8] = 2'b00;

endmodule

`default_nettype wire
