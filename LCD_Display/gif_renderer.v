/* ============================================================================
 * gif_renderer.v  (Landscape 320x240 RGB565 framebuffer generator)
 *
 * What this file does:
 *   This module renders the "GIF viewer" home/app screen:
 *     - Gradient background
 *     - A top-centered QUIT button (with text)
 *     - A bordered "GIF box" region (placeholder area for frames)
 *
 * How it works (high level):
 *   1) The TFT driver asserts framebufferClk once per pixel request.
 *   2) On each rising edge of framebufferClk, we advance (x,y) scan counters.
 *   3) We compute the pixel color by checking whether (x,y) falls inside
 *      UI regions (QUIT button, GIF box border/fill) or the background.
 *
 * Output:
 *   - pixel_color : 16-bit RGB565 color for the current scan pixel (x,y)
 *
 * Assumption:
 *   - The ILI9341 is configured for a 320x240 LANDSCAPE address window.
 * ============================================================================
 */

// gif_renderer.v
// GIF app screen (lightweight version):
//  - Gradient background
//  - Top-centered QUIT button with "QUIT" text (font4x7, 2x scaled)
//  - Empty GIF box region (border + fill), no ROM image.

`timescale 1ns/1ps

module gif_renderer #(
    parameter integer GAME_W  = 320,
    parameter integer GAME_H  = 240
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        framebufferClk,   // from tft_ili9341

    output reg  [15:0] pixel_color       // RGB565
);

    // Physical panel dimensions
    // The scan geometry MUST match tft_ili9341.v window (320x240)
    localparam LCD_W = 320;
    localparam LCD_H = 240;

    // --------------------------------------------------------------------
    // Layout: QUIT button + GIF box region (must match LCD_driver_top)
    // --------------------------------------------------------------------
    // QUIT button hitbox from top module:
    localparam [8:0] HOME_X0 = 9'd120;   // 120..199 (80 px wide)
    localparam [8:0] HOME_X1 = 9'd200;
    localparam [8:0] HOME_Y0 = 9'd10;    // 10..39 (30 px tall)
    localparam [8:0] HOME_Y1 = 9'd40;

    // GIF box region: full 320x180 area under the button
    localparam [8:0] GIF_BOX_X0 = 9'd0;
    localparam [8:0] GIF_BOX_Y0 = 9'd50;
    localparam [8:0] GIF_BOX_X1 = 9'd319;
    localparam [8:0] GIF_BOX_Y1 = GIF_BOX_Y0 + 9'd179; // 50..229

    // Colors
    localparam [15:0] COL_BOX_BORDER = 16'hFFFF; // white border
    localparam [15:0] COL_BOX_FILL   = 16'h0000; // black inside
    localparam [15:0] COL_BTN_FILL   = 16'h07E0; // green-ish button
    localparam [15:0] COL_BTN_BORDER = 16'hFFFF; // white
    localparam [15:0] COL_TEXT       = 16'hFFFF; // white text

    // --------------------------------------------------------------------
    // Physical X/Y pixel counters driven by framebufferClk
    // --------------------------------------------------------------------
    reg [8:0] x;  // 0..319
    reg [8:0] y;  // 0..239
    reg       fbclk_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fbclk_d <= 1'b0;
            x       <= 9'd0;
            y       <= 9'd0;
        end else begin
            fbclk_d <= framebufferClk;
            if (framebufferClk && !fbclk_d) begin
                if (x == LCD_W-1) begin
                    x <= 9'd0;
                    if (y == LCD_H-1)
                        y <= 9'd0;
                    else
                        y <= y + 9'd1;
                end else begin
                    x <= x + 9'd1;
                end
            end
        end
    end

    // Map scan coordinates directly into game coordinates (landscape)
    wire [8:0] game_x = x;
    wire [8:0] game_y = y;

    // --------------------------------------------------------------------
    // Simple gradient background (vertical blue-ish)
    // --------------------------------------------------------------------
    // --------------------------------------------------------------------
    // Background generator
    // --------------------------------------------------------------------
    // Simple vertical gradient in RGB565.
    // --------------------------------------------------------------------
    function [15:0] gradient_color;
        input [8:0] gy;
        reg [4:0] b;
        reg [5:0] g;
    begin
        g = 6'd8  + (gy[7:2] >> 1);
        b = 5'd10 + (gy[7:3] >> 1);
        gradient_color = {5'd0, g, b};
    end
    endfunction

    // --------------------------------------------------------------------
    // font4x7 for "QUIT" text in the button (2x scaling -> 8x14)
    // --------------------------------------------------------------------
    localparam FONT_W      = 4;
    localparam FONT_H      = 7;
    localparam HOME_CHARS  = 4;        // "QUIT"
    localparam DIGIT_W     = FONT_W * 2;
    localparam DIGIT_H     = FONT_H * 2;
    localparam HOME_SPACING= 2;        // 2px gap between chars

    localparam integer HOME_TEXT_W =
        HOME_CHARS*DIGIT_W + (HOME_CHARS-1)*HOME_SPACING;

    localparam integer HOME_TEXT_X0 =
        HOME_X0 + ((HOME_X1 - HOME_X0 + 1) - HOME_TEXT_W)/2;
    localparam integer HOME_TEXT_Y0 =
        HOME_Y0 + ((HOME_Y1 - HOME_Y0 + 1) - DIGIT_H)/2;

    // font instance
    wire       font_bit;
    reg  [7:0] font_char;
    reg  [2:0] font_x;
    reg  [2:0] font_y;

    font4x7 font_inst (
        .char(font_char),
        .x   (font_x),
        .y   (font_y),
        .bit (font_bit)
    );

    // locals for QUIT text
    reg  [8:0]  tx, ty;
    reg  [1:0]  char_idx;      // 0..3
    reg  [4:0]  local_x;       // enough for DIGIT_W + spacing
    reg  [4:0]  local_y;       // 0..13

    // --------------------------------------------------------------------
    // Main combinational drawing
    // --------------------------------------------------------------------
    // --------------------------------------------------------------------
    // Pixel selection (UI region tests)
    // --------------------------------------------------------------------
    // Decide if (x,y) is inside:
    //   - QUIT button (border + fill + text)
    //   - GIF box (border + fill)
    // Otherwise draw background gradient.
    // --------------------------------------------------------------------
    always @* begin
        // default: gradient background
        pixel_color = gradient_color(game_y);

        // ---------------- QUIT button ----------------
        if ( (game_x >= HOME_X0) && (game_x <= HOME_X1) &&
             (game_y >= HOME_Y0) && (game_y <= HOME_Y1) ) begin

            // border
            if ( (game_x == HOME_X0) || (game_x == HOME_X1) ||
                 (game_y == HOME_Y0) || (game_y == HOME_Y1) ) begin
                pixel_color = COL_BTN_BORDER;
            end else begin
                pixel_color = COL_BTN_FILL;
            end
        end

        // -------------- GIF box (border + fill) --------------
        if ( (game_x >= GIF_BOX_X0) && (game_x <= GIF_BOX_X1) &&
             (game_y >= GIF_BOX_Y0) && (game_y <= GIF_BOX_Y1) ) begin

            // border
            if ( (game_x == GIF_BOX_X0) || (game_x == GIF_BOX_X1) ||
                 (game_y == GIF_BOX_Y0) || (game_y == GIF_BOX_Y1) ) begin
                pixel_color = COL_BOX_BORDER;
            end else begin
                // interior fill
                pixel_color = COL_BOX_FILL;
            end
        end

        // -------------- "QUIT" text on button (on top) --------
        if ( (game_x >= HOME_TEXT_X0) &&
             (game_x <  HOME_TEXT_X0 + HOME_TEXT_W) &&
             (game_y >= HOME_TEXT_Y0) &&
             (game_y <  HOME_TEXT_Y0 + DIGIT_H) ) begin

            tx = game_x - HOME_TEXT_X0;
            ty = game_y - HOME_TEXT_Y0;

            // which character index 0..3
            char_idx = tx / (DIGIT_W + HOME_SPACING);
            local_x  = tx % (DIGIT_W + HOME_SPACING);
            local_y  = ty;

            if ( (char_idx < HOME_CHARS) &&
                 (local_x < DIGIT_W) && (local_y < DIGIT_H) ) begin
                // map back to 4x7 font coords (2x scaling)
                font_x = local_x[3:1];   // local_x / 2, 0..7 -> 0..3
                font_y = local_y[3:1];   // local_y / 2, 0..13 -> 0..6

                case (char_idx)
                    2'd0: font_char = "H";
                    2'd1: font_char = "O";
                    2'd2: font_char = "M";
                    2'd3: font_char = "E";
                    default: font_char = " ";
                endcase

                if (font_x < FONT_W && font_y < FONT_H) begin
                    if (font_bit)
                        pixel_color = COL_TEXT;
                end
            end
        end
    end

endmodule