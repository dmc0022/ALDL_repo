// cap1188_idtest_top.v
// Simple I2C test: read CAP1188 Product ID (reg 0xFD)
// and display it on DE10-Lite LEDs.
//
//  - LEDR[7:0] = product ID read from 0xFD
//  - LEDR[8]   = 1 when I2C transaction finished
//  - LEDR[9]   = 1 if product ID == 0x50 (CAP1188)

`default_nettype none

module cap1188_idtest_top #(
    parameter [6:0] DEV_ADDR = 7'h28   // CAP1188 I2C address (ADDR_COMM strapped)
)(
    input  wire       clk_50,
    input  wire       reset_n,     // active-low

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
        .TICKS_PER_I2C_CLK_PERIOD(400)   // ~125 kHz at 50 MHz clk
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
    // CAP1188 addressing & Product ID register
    // ------------------------------------------------------------
    wire [7:0] addr_w = {DEV_ADDR, 1'b0};
    wire [7:0] addr_r = {DEV_ADDR, 1'b1};

    localparam [7:0] REG_PRODUCT_ID = 8'hFD;
    localparam [7:0] EXPECT_ID      = 8'h50;  // expected CAP1188 Product ID

    reg  [7:0] product_id = 8'h00;

    // ------------------------------------------------------------
    // FSM: write reg address (0xFD), then repeated-start + read 1 byte
    // ------------------------------------------------------------
    localparam [4:0]
        S_IDLE            = 5'd0,

        // Write phase: send device addr (write), then reg addr 0xFD
        S_W_START_TRIG    = 5'd1,
        S_W_START_WAIT    = 5'd2,
        S_W_ADDR_SETUP    = 5'd3,
        S_W_ADDR_TRIG     = 5'd4,
        S_W_ADDR_WAIT     = 5'd5,
        S_W_REG_SETUP     = 5'd6,
        S_W_REG_TRIG      = 5'd7,
        S_W_REG_WAIT      = 5'd8,

        // Repeated START, now read
        S_R_START_TRIG    = 5'd9,
        S_R_START_WAIT    = 5'd10,
        S_R_ADDR_SETUP    = 5'd11,
        S_R_ADDR_TRIG     = 5'd12,
        S_R_ADDR_WAIT     = 5'd13,
        S_R_READ_TRIG     = 5'd14,
        S_R_READ_WAIT     = 5'd15,
        S_R_STOP_TRIG     = 5'd16,
        S_R_STOP_WAIT     = 5'd17,

        S_DONE            = 5'd18;

    reg [4:0] state = S_IDLE;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            drv_command  <= DRVR_CMD_NONE;
            drv_tx_byte  <= 8'h00;
            product_id   <= 8'h00;
        end else begin
            // default: no new command unless we set it
            drv_command <= DRVR_CMD_NONE;

            case (state)
            // ------------------------------------------------
            S_IDLE: begin
                if (!drv_busy)
                    state <= S_W_START_TRIG;
            end

            // --- Write device addr (write) & reg=0xFD ---
            S_W_START_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_START_COND;
                    state       <= S_W_START_WAIT;
                end
            end
            S_W_START_WAIT: if (drv_done) state <= S_W_ADDR_SETUP;

            S_W_ADDR_SETUP: begin
                drv_tx_byte <= addr_w;  // write addr
                state       <= S_W_ADDR_TRIG;
            end
            S_W_ADDR_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    state       <= S_W_ADDR_WAIT;
                end
            end
            S_W_ADDR_WAIT: if (drv_done) state <= S_W_REG_SETUP;

            S_W_REG_SETUP: begin
                drv_tx_byte <= REG_PRODUCT_ID; // 0xFD
                state       <= S_W_REG_TRIG;
            end
            S_W_REG_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    state       <= S_W_REG_WAIT;
                end
            end
            S_W_REG_WAIT: if (drv_done) state <= S_R_START_TRIG;

            // --- Repeated START then read 1 byte ---
            S_R_START_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_START_COND;
                    state       <= S_R_START_WAIT;
                end
            end
            S_R_START_WAIT: if (drv_done) state <= S_R_ADDR_SETUP;

            S_R_ADDR_SETUP: begin
                drv_tx_byte <= addr_r;  // read addr
                state       <= S_R_ADDR_TRIG;
            end
            S_R_ADDR_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    state       <= S_R_ADDR_WAIT;
                end
            end
            S_R_ADDR_WAIT: if (drv_done) state <= S_R_READ_TRIG;

            S_R_READ_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_READ; // read 1 byte
                    state       <= S_R_READ_WAIT;
                end
            end

            S_R_READ_WAIT: begin
                if (drv_data_valid) begin
                    product_id <= drv_read_byte;
                end
                if (drv_done) begin
                    state <= S_R_STOP_TRIG;
                end
            end

            S_R_STOP_TRIG: begin
                if (!drv_busy) begin
                    drv_command <= DRVR_CMD_STOP_COND;
                    state       <= S_R_STOP_WAIT;
                end
            end
            S_R_STOP_WAIT: if (drv_done) state <= S_DONE;

            S_DONE: begin
                state <= S_DONE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    // LED mapping
    // ------------------------------------------------------------
    assign LEDR[7:0] = product_id;           // show ID byte
    assign LEDR[8]   = (state == S_DONE);    // transaction finished
    assign LEDR[9]   = (product_id == EXPECT_ID);  // 1 if matches 0x50

endmodule

`default_nettype wire
