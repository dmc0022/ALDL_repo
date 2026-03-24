`timescale 1ns/1ps
`default_nettype none

module aldl_system_top #(
    parameter [6:0] CAP_ADDR0    = 7'h28,
    parameter [6:0] CAP_ADDR1    = 7'h29,
    parameter [6:0] CAP_ADDR2    = 7'h00,
    parameter       CAP_EN0      = 1'b1,
    parameter       CAP_EN1      = 1'b1,
    parameter       CAP_EN2      = 1'b0,
    parameter [6:0] FT6336_ADDR  = 7'h38
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

    wire        touch_valid;
    wire        touch_down;
    wire [11:0] touch_x;
    wire [11:0] touch_y;

    wire [7:0] cap_touch_status_0;
    wire [7:0] cap_touch_status_1;
    wire [7:0] cap_touch_status_2;

    // Restore LCD + touch/CAP operation and leave TMP bus idle.
    assign TMP_SCL = 1'b1;
    assign TMP_SDA = 1'bz;

    // Unused 7-seg digits off
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

    // Simple LED mapping for CAP1188 + touch debug
    assign LEDR[0] = touch_valid;
    assign LEDR[1] = touch_down;
    assign LEDR[2] = cap_touch_status_0[0];
    assign LEDR[3] = cap_touch_status_0[1];
    assign LEDR[4] = cap_touch_status_0[2];
    assign LEDR[5] = cap_touch_status_0[3];
    assign LEDR[6] = cap_touch_status_1[0];
    assign LEDR[7] = cap_touch_status_1[1];
    assign LEDR[8] = cap_touch_status_1[2];
    assign LEDR[9] = cap_touch_status_1[3];

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
        .temp_valid_in       (1'b0),
        .temp_sensor_present (1'b0),
        .temp_centi_c_in     (16'sd0)
    );

endmodule

`default_nettype wire
