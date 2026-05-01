`timescale 1ns/1ps
`default_nettype none

module aldl_lab2 (
    input  wire       clk_50,
    input  wire       reset_n,

    // LCD pins
    output wire       lcd_cs,
    output wire       lcd_rst,
    output wire       lcd_rs,
    output wire       lcd_sck,
    output wire       lcd_mosi,
    output wire       bl_pwm,
    output wire       sd_cs,

    // TMP117 I2C bus
    inout  wire       TMP_SCL,
    inout  wire       TMP_SDA,

    // 7-segment displays
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,

    // Debug LEDs
    output wire [9:0] LEDR
);

    // -------------------------------------------------------------------------
    // TMP117 reader interface
    // -------------------------------------------------------------------------
    wire [15:0] raw_temp_word;
    wire        busy;
    wire        tx_done;
    wire [2:0]  dbg_state;
    wire        busy_seen;
    wire        complete_seen;
    wire [3:0]  latched_master_state;
    wire [1:0]  latched_master_phase;
    wire [3:0]  latched_master_bit;
    wire [7:0]  latched_master_byte;
    wire        latched_master_last_ack;

    tmp117_reader #(
        .CLK_FREQ_HZ  (50_000_000),
        .I2C_FREQ_HZ  (50_000),
        .TMP117_ADDR  (7'h48),
        .STARTUP_TICKS(24'd5_000_000),
        .POLL_DIVIDER (24'd10_000_000)
    ) u_tmp117 (
        .clk_50                  (clk_50),
        .reset_n                 (reset_n),
        .tmp_scl                 (TMP_SCL),
        .tmp_sda                 (TMP_SDA),
        .raw_id                  (raw_temp_word),
        .busy                    (busy),
        .tx_done                 (tx_done),
        .dbg_state               (dbg_state),
        .busy_seen               (busy_seen),
        .complete_seen           (complete_seen),
        .latched_master_state    (latched_master_state),
        .latched_master_phase    (latched_master_phase),
        .latched_master_bit      (latched_master_bit),
        .latched_master_byte     (latched_master_byte),
        .latched_master_last_ack (latched_master_last_ack)
    );

    // -------------------------------------------------------------------------
    // Convert TMP117 raw temperature to centi-degrees Celsius.
    // TMP117 LSB = 0.0078125 C = 1/128 C.
    // centiC = raw * 100 / 128 = raw * 25 / 32
    // -------------------------------------------------------------------------
    wire signed [15:0] raw_temp_signed = raw_temp_word;
    wire signed [31:0] temp_centi_c_long = raw_temp_signed * 32'sd25;
    wire signed [15:0] temp_centi_c = temp_centi_c_long / 32'sd32;

    // Latch a "display valid" flag after the first completed read so both the
    // LCD and 7-segment stay enabled after the sensor starts responding.
    reg temp_display_valid;
    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            temp_display_valid <= 1'b0;
        else if (tx_done)
            temp_display_valid <= 1'b1;
    end

    wire sensor_present = temp_display_valid;
    wire temp_valid     = temp_display_valid;

    // -------------------------------------------------------------------------
    // Minimal LCD path: drive the TFT directly with the temperature renderer.
    // -------------------------------------------------------------------------
    wire [15:0] lcd_pixel;
    wire        framebufferClk;

    assign bl_pwm = 1'b1;
    assign sd_cs  = 1'b1;

    tft_ili9341 #(
        .INPUT_CLK_MHZ(50)
    ) u_tft (
        .clk            (clk_50),
        .reset_n        (reset_n),
        .tft_sdo        (1'b0),
        .tft_sck        (lcd_sck),
        .tft_sdi        (lcd_mosi),
        .tft_dc         (lcd_rs),
        .tft_reset      (lcd_rst),
        .tft_cs         (lcd_cs),
        .framebufferData(lcd_pixel),
        .framebufferClk (framebufferClk)
    );

    temperature_renderer #(
        .GAME_W(320),
        .GAME_H(240)
    ) u_temp_renderer (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .temp_valid    (temp_valid),
        .sensor_present(sensor_present),
        .temp_centi_c  (temp_centi_c),
        .pixel_color   (lcd_pixel)
    );

    // -------------------------------------------------------------------------
    // 7-segment display: integer Celsius for quick debug/proof of operation.
    // Format: [HEX5 HEX4 HEX3 HEX2 HEX1 HEX0] = [blank blank sign/100s 10s 1s C]
    // -------------------------------------------------------------------------
    wire        temp_negative = temp_centi_c[15];
    wire [15:0] temp_abs_centi = temp_negative ? -temp_centi_c : temp_centi_c;
    wire [15:0] temp_whole_c   = temp_abs_centi / 16'd100;

    wire [3:0] temp_ones     = temp_whole_c % 10;
    wire [3:0] temp_tens     = (temp_whole_c / 10) % 10;
    wire [3:0] temp_hundreds = (temp_whole_c / 100) % 10;

    wire show_hundreds = (temp_whole_c >= 100);
    wire show_tens     = (temp_whole_c >= 10);

    localparam [6:0] SEG_BLANK = 7'b1111111;
    localparam [6:0] SEG_MINUS = 7'b0111111;
    localparam [6:0] SEG_C     = 7'b1000110;

    assign HEX5 = SEG_BLANK;
    assign HEX4 = SEG_BLANK;
    assign HEX3 = temp_negative ? SEG_MINUS : (show_hundreds ? hex7(temp_hundreds) : SEG_BLANK);
    assign HEX2 = show_hundreds ? hex7(temp_tens) : (show_tens ? hex7(temp_tens) : SEG_BLANK);
    assign HEX1 = temp_display_valid ? hex7(temp_ones) : SEG_BLANK;
    assign HEX0 = temp_display_valid ? SEG_C : SEG_BLANK;

    // -------------------------------------------------------------------------
    // Debug LEDs
    // -------------------------------------------------------------------------
    assign LEDR[0] = busy_seen;
    assign LEDR[1] = complete_seen;
    assign LEDR[2] = temp_display_valid;
    assign LEDR[6:3] = latched_master_state;
    assign LEDR[8:7] = latched_master_phase;
    assign LEDR[9] = dbg_state[0];

    function [6:0] hex7(input [3:0] v);
        begin
            case (v)
                4'h0: hex7 = 7'b1000000;
                4'h1: hex7 = 7'b1111001;
                4'h2: hex7 = 7'b0100100;
                4'h3: hex7 = 7'b0110000;
                4'h4: hex7 = 7'b0011001;
                4'h5: hex7 = 7'b0010010;
                4'h6: hex7 = 7'b0000010;
                4'h7: hex7 = 7'b1111000;
                4'h8: hex7 = 7'b0000000;
                4'h9: hex7 = 7'b0010000;
                4'hA: hex7 = 7'b0001000;
                4'hB: hex7 = 7'b0000011;
                4'hC: hex7 = 7'b1000110;
                4'hD: hex7 = 7'b0100001;
                4'hE: hex7 = 7'b0000110;
                default: hex7 = 7'b0001110;
            endcase
        end
    endfunction

endmodule

`default_nettype wire
