`timescale 1ns/1ps
`default_nettype none

module aldl_system_top #(
    parameter [6:0] CAP_ADDR0    = 7'h28,
    parameter [6:0] CAP_ADDR1    = 7'h29,
    parameter [6:0] CAP_ADDR2    = 7'h2A,
    parameter       CAP_EN0      = 1'b1,
    parameter       CAP_EN1      = 1'b1,
    parameter       CAP_EN2      = 1'b1,
    parameter [6:0] FT6336_ADDR  = 7'h38,
    parameter [6:0] TMP117_ADDR  = 7'h48
)(
    input  wire        clk_50,
    input  wire        reset_n,

    output wire        lcd_cs,
    output wire        lcd_rst,
    output wire        lcd_rs,
    output wire        lcd_sck,
    output wire        lcd_mosi,
    output wire        bl_pwm,
    output wire        sd_cs,
    output wire        debug_led,

    output wire [3:0]  led_touch_y,
    output wire [3:0]  led_paddle_x,

    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,

    output wire        CTP_SCL,
    inout  wire        CTP_SDA,
    output wire        CTP_RST,
    input  wire        CTP_INT,

    output wire        TMP_SCL,
    inout  wire        TMP_SDA,

    output wire [9:0]  LEDR
);

    // -------------------------------------------------------------------------
    // Shared touch / CAP1188 signals
    // -------------------------------------------------------------------------
    wire        touch_valid;
    wire        touch_down;
    wire [11:0] touch_x;
    wire [11:0] touch_y;

    wire [7:0]  cap_touch_status_0;
    wire [7:0]  cap_touch_status_1;
    wire [7:0]  cap_touch_status_2;

    // -------------------------------------------------------------------------
    // TMP117 signals
    // -------------------------------------------------------------------------
    wire [15:0] tmp_raw_word;
    wire        tmp_busy;
    wire        tmp_tx_done;
    wire [2:0]  tmp_dbg_state;
    wire        tmp_busy_seen;
    wire        tmp_complete_seen;
    wire [3:0]  tmp_master_state;
    wire [1:0]  tmp_master_phase;
    wire [3:0]  tmp_master_bit;
    wire [7:0]  tmp_master_byte;
    wire        tmp_master_last_ack;

    reg         temp_valid_r;
    reg         temp_sensor_present_r;
    reg signed [15:0] temp_raw_latched;

    wire signed [31:0] temp_centi_c_wide = $signed(temp_raw_latched) * 32'sd25;
    wire signed [15:0] temp_centi_c      = temp_centi_c_wide >>> 5; // raw * 25 / 32

    // -------------------------------------------------------------------------
    // Touch / CAP1188 hub 
    // -------------------------------------------------------------------------
    i2c_touch_hub #(
        .DEV_ADDR0   (CAP_ADDR0),
        .DEV_ADDR1   (CAP_ADDR1),
        .DEV_ADDR2   (CAP_ADDR2),
        .ENABLE_DEV0 (CAP_EN0),
        .ENABLE_DEV1 (CAP_EN1),
        .ENABLE_DEV2 (CAP_EN2),
        .FT6336_ADDR (FT6336_ADDR)
    ) touch_hub_inst (
        .clk_50             (clk_50),
        .reset_n            (reset_n),
        .i2c_sda            (CTP_SDA),
        .i2c_scl            (CTP_SCL),
        .CTP_RST            (CTP_RST),
        .CTP_INT            (CTP_INT),
        .touch_valid        (touch_valid),
        .touch_down         (touch_down),
        .touch_x            (touch_x),
        .touch_y            (touch_y),
        .cap_touch_status_0 (cap_touch_status_0),
        .cap_touch_status_1 (cap_touch_status_1),
        .cap_touch_status_2 (cap_touch_status_2),
        .LEDR               ()
    );

    // -------------------------------------------------------------------------
    // TMP117 reader on the separate Qwiic bus
    // -------------------------------------------------------------------------
    tmp117_reader_completion_debug #(
        .CLK_FREQ_HZ   (50_000_000),
        .I2C_FREQ_HZ   (50_000),
        .TMP117_ADDR   (TMP117_ADDR),
        .STARTUP_TICKS (24'd5_000_000),
        .POLL_DIVIDER  (24'd10_000_000)
    ) tmp117_inst (
        .clk_50                  (clk_50),
        .reset_n                 (reset_n),
        .tmp_scl                 (TMP_SCL),
        .tmp_sda                 (TMP_SDA),
        .raw_id                  (tmp_raw_word),
        .busy                    (tmp_busy),
        .tx_done                 (tmp_tx_done),
        .dbg_state               (tmp_dbg_state),
        .busy_seen               (tmp_busy_seen),
        .complete_seen           (tmp_complete_seen),
        .latched_master_state    (tmp_master_state),
        .latched_master_phase    (tmp_master_phase),
        .latched_master_bit      (tmp_master_bit),
        .latched_master_byte     (tmp_master_byte),
        .latched_master_last_ack (tmp_master_last_ack)
    );

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            temp_valid_r          <= 1'b0;
            temp_sensor_present_r <= 1'b0;
            temp_raw_latched      <= 16'sd0;
        end else begin
            if (tmp_tx_done) begin
                temp_raw_latched      <= $signed(tmp_raw_word);
                temp_valid_r          <= 1'b1;
                temp_sensor_present_r <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // LCD core (existing apps + TEMP app fed from TMP117)
    // -------------------------------------------------------------------------
    LCD_driver_core_shared_touch lcd_core_inst (
        .clk_50              (clk_50),
        .reset_n             (reset_n),
        .lcd_cs              (lcd_cs),
        .lcd_rst             (lcd_rst),
        .lcd_rs              (lcd_rs),
        .lcd_sck             (lcd_sck),
        .lcd_mosi            (lcd_mosi),
        .bl_pwm              (bl_pwm),
        .sd_cs               (sd_cs),
        .debug_led           (debug_led),
        .led_touch_y         (led_touch_y),
        .led_paddle_x        (led_paddle_x),
        .HEX0                (HEX0),
        .touch_valid         (touch_valid),
        .touch_down          (touch_down),
        .touch_x             (touch_x),
        .touch_y             (touch_y),
        .temp_valid_in       (temp_valid_r),
        .temp_sensor_present (temp_sensor_present_r),
        .temp_centi_c_in     (temp_centi_c)
    );

    // -------------------------------------------------------------------------
    // Keep previous touch/CAP LED behavior, and use the upper two LEDs for TMP117
    // status so integration can be verified without disturbing the rest.
    // -------------------------------------------------------------------------
    assign LEDR[0] = touch_valid;
    assign LEDR[1] = touch_down;
    assign LEDR[2] = cap_touch_status_0[0];
    assign LEDR[3] = cap_touch_status_0[1];
    assign LEDR[4] = cap_touch_status_0[2];
    assign LEDR[5] = cap_touch_status_0[3];
    assign LEDR[6] = cap_touch_status_1[0];
    assign LEDR[7] = cap_touch_status_1[1];
    assign LEDR[8] = temp_valid_r;
    assign LEDR[9] = temp_sensor_present_r;

    // HEX1..HEX5 are unused here. HEX0 is still driven by the LCD core.
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

endmodule

`default_nettype wire
