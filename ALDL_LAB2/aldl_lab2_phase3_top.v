`timescale 1ns/1ps
`default_nettype none

//==============================================================================
// A.L.D.L. Lab 2 - Phase III Top File
//------------------------------------------------------------------------------
// Module Name:
//   aldl_lab2_phase3_top
//
// Purpose:
//   This is the Phase III top-level file for the TMP117 lab. This phase keeps
//   the same communication and conversion path developed in Phases I and II, but
//   now integrates the LCD so the temperature can be rendered graphically.
//
// Recommended learning objective for Phase III:
//   "Can I integrate my verified sensor path into a minimal display system?"
//
// What this top file does:
//   1. Instantiates the provided tmp117_reader module.
//   2. Converts the raw sensor reading into centi-degrees Celsius.
//   3. Displays the integer temperature on the 7-segment displays.
//   4. Instantiates the TFT LCD driver.
//   5. Instantiates the temperature-only LCD renderer.
//   6. Keeps the design intentionally small by excluding touch, menus, games,
//      home screens, and all other sensor-board apps.
//
// Why this is a good Phase III structure:
//   - It reuses the same proven sensor path from earlier phases.
//   - It adds only one major new subsystem: the LCD pipeline.
//   - It is much faster to compile than the full sensor-board project.
//==============================================================================

module aldl_lab2_phase3_top (
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

    //==========================================================================
    // Reader interface
    //--------------------------------------------------------------------------
    // The Phase III top uses the exact same sensor-read interface as the earlier
    // phases. That way, students can focus on system integration rather than
    // re-debugging the sensor path.
    //==========================================================================
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

    //==========================================================================
    // Valid-data latch
    //--------------------------------------------------------------------------
    // After the first completed read, we allow both the 7-segment display and
    // the LCD renderer to treat the sensor as active.
    //
    // In a larger final project you might separate "sensor present" and
    // "temperature valid" more carefully. For this lab build, a successful read
    // is enough to enable the display path.
    //==========================================================================
    reg temp_display_valid;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            temp_display_valid <= 1'b0;
        else if (tx_done)
            temp_display_valid <= 1'b1;
    end

    wire sensor_present = temp_display_valid;
    wire temp_valid     = temp_display_valid;

    //==========================================================================
    // Conversion logic (same as Phase II)
    //--------------------------------------------------------------------------
    // This is intentionally unchanged from the previous phase. Students should
    // see that system integration is easier when the earlier phases already
    // proved the sensor and conversion logic are working.
    //
    // TMP117 scale:
    //   1 LSB = 1/128 degrees C
    //
    // Convert to centi-Celsius:
    //   temp_centi_c = raw * 100 / 128 = raw * 25 / 32
    //==========================================================================
    wire signed [15:0] raw_temp_signed = raw_temp_word;
    wire signed [31:0] temp_centi_c_long = raw_temp_signed * 32'sd25;
    wire signed [15:0] temp_centi_c = temp_centi_c_long / 32'sd32;

    //==========================================================================
    // Minimal LCD path
    //--------------------------------------------------------------------------
    // This phase intentionally uses a stripped-down LCD path:
    //   tft_ili9341        -> handles LCD initialization + pixel streaming
    //   temperature_renderer -> decides what pixel color to draw
    //
    // We DO NOT use:
    //   - home screen
    //   - touch input
    //   - keypad app
    //   - breakout app
    //   - GIF app
    //
    // That keeps compile time lower and keeps the lab focused on the
    // temperature-sensor learning objectives.
    //==========================================================================
    wire [15:0] lcd_pixel;
    wire        framebufferClk;

    // Always keep backlight on and disable SD chip select.
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

    //--------------------------------------------------------------------------
    // The temperature renderer is the "graphics layer" for this lab.
    // It receives the already-converted temperature and decides what to draw
    // at each pixel location on the LCD.
    //--------------------------------------------------------------------------
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

    //==========================================================================
    // 7-segment display
    //--------------------------------------------------------------------------
    // We keep the integer-Celsius 7-segment output from Phase II because it
    // provides a second, very useful proof of operation during bring-up.
    //
    // This is especially helpful in lab because:
    //   - If the LCD formatting is wrong, the HEX display can still confirm that
    //     the conversion path is working.
    //   - If the LCD is disconnected, the 7-segment still provides feedback.
    //==========================================================================
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

    //==========================================================================
    // Debug LEDs
    //--------------------------------------------------------------------------
    // These remain valuable in Phase III because they let students separate:
    //   - sensor communication issues
    // from
    //   - LCD/display integration issues
    //==========================================================================
    assign LEDR[0]   = busy_seen;
    assign LEDR[1]   = complete_seen;
    assign LEDR[2]   = temp_display_valid;
    assign LEDR[6:3] = latched_master_state;
    assign LEDR[8:7] = latched_master_phase;
    assign LEDR[9]   = dbg_state[0];

    //==========================================================================
    // Local 4-bit hex to 7-segment decoder
    //==========================================================================
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
                default: hex7 = 7'b0001110; // F
            endcase
        end
    endfunction

endmodule

`default_nettype wire
