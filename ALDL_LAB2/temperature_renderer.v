`timescale 1ns/1ps
`default_nettype none

//==============================================================================
// temperature_renderer
//------------------------------------------------------------------------------
// Purpose:
//   This module generates the pixel data for the LCD screen.
//
// What this module does:
//   1. Tracks the current LCD pixel position (x,y) as pixels are requested.
//   2. Draws a centered "panel" or box on the LCD.
//   3. Displays either:
//        - the temperature value in degrees Celsius, or
//        - a simple invalid/error marker if the sensor data is not valid.
//   4. Outputs one RGB565 pixel color at a time to the LCD pipeline.
//
// Inputs:
//   clk             : Main system clock.
//   reset_n         : Active-low reset.
//   framebufferClk  : One pulse per pixel from the LCD driver. Each pulse means
//                     "advance to the next pixel position."
//   temp_valid      : High when the temperature reading is valid.
//   sensor_present  : High when the sensor appears to be connected/responding.
//   temp_centi_c    : Temperature in hundredths of a degree Celsius.
//                     Example: 2534 means 25.34 C, -575 means -5.75 C.
//
// Output:
//   pixel_color     : Current RGB565 pixel color to send to the LCD.
//
// Notes for students:
//   - This is a renderer only. It does NOT talk to the TMP117 directly.
//   - It assumes another module has already read the TMP117 and converted the
//     raw value into centi-Celsius.
//   - This module is a good example of "draw by coordinates" graphics logic.
//==============================================================================

module temperature_renderer #(
    parameter integer GAME_W = 320,  // LCD width  in pixels
    parameter integer GAME_H = 240   // LCD height in pixels
)(
    input  wire               clk,
    input  wire               reset_n,
    input  wire               framebufferClk,
    input  wire               temp_valid,
    input  wire               sensor_present,
    input  wire signed [15:0] temp_centi_c,
    output reg  [15:0]        pixel_color
);

    //==========================================================================
    // Current pixel coordinate counters
    //--------------------------------------------------------------------------
    // The LCD driver requests pixels in raster order:
    //   (0,0), (1,0), (2,0), ... (319,0), then next row, etc.
    //
    // Each pulse on framebufferClk means:
    //   "Move to the next pixel location."
    //
    // This renderer keeps track of the current (x,y) position so it knows what
    // should be drawn at that location.
    //==========================================================================
    reg [9:0] x;
    reg [8:0] y;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 10'd0;
            y <= 9'd0;
        end else if (framebufferClk) begin
            if (x == GAME_W-1) begin
                x <= 10'd0;
                if (y == GAME_H-1) y <= 9'd0;
                else               y <= y + 9'd1;
            end else begin
                x <= x + 10'd1;
            end
        end
    end

    //==========================================================================
    // Helper function: in_rect
    //--------------------------------------------------------------------------
    // Returns 1 when pixel (px,py) lies inside the rectangle whose upper-left
    // corner is (x0,y0) and whose size is w-by-h.
    //
    // This is the basic building block used to draw:
    //   - the large outer panel
    //   - the inner fill
    //   - the colored accent bar
    //   - the decimal point
    //   - the minus sign
    //==========================================================================
    function automatic in_rect;
        input integer px, py, x0, y0, w, h;
        begin
            in_rect = (px >= x0) && (px < (x0 + w)) &&
                      (py >= y0) && (py < (y0 + h));
        end
    endfunction

    //==========================================================================
    // Helper function: seg_on
    //--------------------------------------------------------------------------
    // This function implements a 7-segment decoder for digits 0 through 9.
    //
    // Inputs:
    //   val : the digit to draw
    //   seg : which segment is being checked
    //
    // Segment numbering used here:
    //        ---0---
    //       |       |
    //       5       1
    //       |       |
    //        ---6---
    //       |       |
    //       4       2
    //       |       |
    //        ---3---
    //
    // Output:
    //   1 if that segment should be lit for the given digit, else 0.
    //
    // This lets us draw large custom digits directly on the LCD without using
    // a font ROM for the main temperature number.
    //==========================================================================
    function automatic seg_on;
        input [3:0] val;
        input [2:0] seg;
        begin
            case (val)
                4'd0: seg_on = (seg != 3'd6);
                4'd1: seg_on = (seg == 3'd1) || (seg == 3'd2);
                4'd2: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd6) || (seg == 3'd4) || (seg == 3'd3);
                4'd3: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd6) || (seg == 3'd2) || (seg == 3'd3);
                4'd4: seg_on = (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd1) || (seg == 3'd2);
                4'd5: seg_on = (seg == 3'd0) || (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd2) || (seg == 3'd3);
                4'd6: seg_on = (seg == 3'd0) || (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd4) || (seg == 3'd2) || (seg == 3'd3);
                4'd7: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd2);
                4'd8: seg_on = 1'b1;
                4'd9: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd2) || (seg == 3'd3) || (seg == 3'd5) || (seg == 3'd6);
                default: seg_on = 1'b0;
            endcase
        end
    endfunction

    //==========================================================================
    // Helper function: digit_pixel
    //--------------------------------------------------------------------------
    // Draws one LARGE 7-segment-style digit at position (x0,y0).
    //
    // Inputs:
    //   px, py : current screen pixel being tested
    //   x0, y0 : upper-left corner of the digit
    //   val    : decimal digit 0..9
    //
    // Output:
    //   1 if the pixel belongs to one of the active segments for that digit.
    //
    // The digit is built from 7 rectangular bars:
    //   - three horizontal bars
    //   - four vertical bars
    //
    // This approach is simple and fast for synthesis, and it avoids needing a
    // large bitmap or font for the main number display.
    //==========================================================================
    function automatic digit_pixel;
        input integer px, py, x0, y0;
        input [3:0] val;
        integer lx, ly;
        begin
            lx = px - x0;
            ly = py - y0;
            digit_pixel = 1'b0;

            // Digit bounding box: 30 x 56 pixels
            if ((lx >= 0) && (lx < 30) && (ly >= 0) && (ly < 56)) begin
                // Top horizontal segment
                if (seg_on(val,3'd0) && (ly >= 0  && ly < 5  && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
                // Upper-right vertical segment
                if (seg_on(val,3'd1) && (lx >= 25 && lx < 30 && ly >= 6  && ly < 24)) digit_pixel = 1'b1;
                // Lower-right vertical segment
                if (seg_on(val,3'd2) && (lx >= 25 && lx < 30 && ly >= 31 && ly < 49)) digit_pixel = 1'b1;
                // Bottom horizontal segment
                if (seg_on(val,3'd3) && (ly >= 51 && ly < 56 && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
                // Lower-left vertical segment
                if (seg_on(val,3'd4) && (lx >= 0  && lx < 5  && ly >= 31 && ly < 49)) digit_pixel = 1'b1;
                // Upper-left vertical segment
                if (seg_on(val,3'd5) && (lx >= 0  && lx < 5  && ly >= 6  && ly < 24)) digit_pixel = 1'b1;
                // Middle horizontal segment
                if (seg_on(val,3'd6) && (ly >= 25 && ly < 30 && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
            end
        end
    endfunction

    //==========================================================================
    // Helper function: c_pixel
    //--------------------------------------------------------------------------
    // Draws a block-style "C" for the degrees Celsius label.
    //
    // Inputs:
    //   px, py : current pixel being tested
    //   x0, y0 : upper-left corner of the letter
    //
    // Output:
    //   1 if the pixel lies inside the "C" shape.
    //==========================================================================
    function automatic c_pixel;
        input integer px, py, x0, y0;
        integer lx, ly;
        begin
            lx = px - x0;
            ly = py - y0;
            c_pixel = 1'b0;
            if ((lx >= 0) && (lx < 20) && (ly >= 0) && (ly < 30)) begin
                if ((ly >= 0  && ly < 4  && lx >= 4 && lx < 18) ||
                    (ly >= 26 && ly < 30 && lx >= 4 && lx < 18) ||
                    (lx >= 0  && lx < 4  && ly >= 4 && ly < 26))
                    c_pixel = 1'b1;
            end
        end
    endfunction

    //==========================================================================
    // Layout constants
    //--------------------------------------------------------------------------
    // These constants define where the panel box and temperature characters are
    // drawn on the 320x240 LCD.
    //==========================================================================
    localparam integer PANEL_X = 36;
    localparam integer PANEL_Y = 52;
    localparam integer PANEL_W = 248;
    localparam integer PANEL_H = 136;

    localparam integer DIGIT_Y = 95;
    localparam integer MINUS_X = 54;
    localparam integer TENS_X  = 86;
    localparam integer ONES_X  = 122;
    localparam integer TENTHS_X= 170;
    localparam integer DP_X    = 158;
    localparam integer DEG_X   = 214;
    localparam integer DEG_Y   = 104;
    localparam integer C_X     = 232;
    localparam integer C_Y     = 108;

    //==========================================================================
    // Color constants (RGB565)
    //--------------------------------------------------------------------------
    // These are 16-bit LCD colors:
    //   COL_BG     : entire background color
    //   COL_PANEL  : inside of the black temperature box
    //   COL_BORDER : white border around the panel
    //   COL_TEXT   : white digits and symbols
    //   COL_ACCENT : green accent bar and degree/C symbol
    //   COL_WARN   : red accent bar if the data is invalid
    //==========================================================================
    localparam [15:0] COL_BG     = 16'h0841;
    localparam [15:0] COL_PANEL  = 16'h0000;
    localparam [15:0] COL_BORDER = 16'hFFFF;
    localparam [15:0] COL_TEXT   = 16'hFFFF;
    localparam [15:0] COL_ACCENT = 16'h07E0;
    localparam [15:0] COL_WARN   = 16'hF800;

    //==========================================================================
    // Temperature formatting logic
    //--------------------------------------------------------------------------
    // invalid:
    //   True if the sensor is missing OR the reading is not yet valid.
    //
    // neg_temp:
    //   Indicates whether the temperature is negative.
    //
    // abs_temp:
    //   Absolute value of temp_centi_c so the renderer can draw the digits
    //   without needing separate logic for negative values.
    //
    // whole / frac:
    //   Splits the centi-Celsius number into:
    //     - whole degrees
    //     - fractional hundredths
    //
    // tens / ones / tenths:
    //   Extracts decimal digits for display.
    //
    // Example:
    //   temp_centi_c = 2534
    //   whole        = 25
    //   frac         = 34
    //   tens         = 2
    //   ones         = 5
    //   tenths       = 3
    //
    // The display therefore shows:
    //   25.3 C
    //
    // This renderer intentionally shows only one decimal place on the LCD.
    //==========================================================================
    wire invalid = !(sensor_present && temp_valid);

    wire        neg_temp = temp_centi_c[15];
    wire signed [15:0] abs_temp = neg_temp ? -temp_centi_c : temp_centi_c;
    wire [15:0] abs_u    = abs_temp[15:0];

    wire [15:0] whole    = abs_u / 16'd100;
    wire [15:0] frac     = abs_u % 16'd100;

    wire [3:0] tens      = (whole / 10) % 10;
    wire [3:0] ones      = whole % 10;
    wire [3:0] tenths    = frac / 10;

    wire show_minus = neg_temp && !invalid;
    wire show_tens  = (whole >= 10);

    //==========================================================================
    // Main combinational rendering block
    //--------------------------------------------------------------------------
    // This block decides the color of the CURRENT pixel at coordinate (x,y).
    //
    // Drawing order matters:
    //   1. Start with background color.
    //   2. Draw outer panel border.
    //   3. Draw inner panel fill.
    //   4. Draw accent bar at top.
    //   5. Draw either:
    //        - invalid marker, or
    //        - minus sign, digits, decimal point, degree symbol, and C.
    //
    //  The visible "top layer" is simply whatever condition is checked last for 
	//  that pixel.
    //==========================================================================
    always @* begin
        // Default: full-screen background
        pixel_color = COL_BG;

        // Draw outer panel border
        if (in_rect(x, y, PANEL_X, PANEL_Y, PANEL_W, PANEL_H))
            pixel_color = COL_BORDER;

        // Draw inner black panel
        if (in_rect(x, y, PANEL_X+4, PANEL_Y+4, PANEL_W-8, PANEL_H-8))
            pixel_color = COL_PANEL;

        // Draw a small bar near the top of the panel.
        // Green = valid reading
        // Red   = invalid/missing sensor
        if (in_rect(x, y, PANEL_X+12, PANEL_Y+12, PANEL_W-24, 8))
            pixel_color = invalid ? COL_WARN : COL_ACCENT;

        if (invalid) begin
            //------------------------------------------------------------------
            // If data is invalid, draw a simple centered horizontal line.
            // This visually indicates "no temperature available".
            //------------------------------------------------------------------
            if (in_rect(x, y, 144, 118, 32, 6))
                pixel_color = COL_TEXT;
        end else begin
            //------------------------------------------------------------------
            // Valid display path
            //------------------------------------------------------------------

            // Draw minus sign if the temperature is negative
            if (show_minus && in_rect(x, y, MINUS_X, 120, 20, 5))
                pixel_color = COL_TEXT;

            // Tens digit (only shown for 10C and above)
            if (show_tens && digit_pixel(x, y, TENS_X, DIGIT_Y, tens))
                pixel_color = COL_TEXT;

            // Ones digit
            if (digit_pixel(x, y, ONES_X, DIGIT_Y, ones))
                pixel_color = COL_TEXT;

            // Decimal point
            if (in_rect(x, y, DP_X, 136, 5, 5))
                pixel_color = COL_TEXT;

            // Tenths digit
            if (digit_pixel(x, y, TENTHS_X, DIGIT_Y, tenths))
                pixel_color = COL_TEXT;

            // Degree symbol = hollow square/ring
            if (in_rect(x, y, DEG_X, DEG_Y, 10, 10) &&
                !in_rect(x, y, DEG_X+2, DEG_Y+2, 6, 6))
                pixel_color = COL_ACCENT;

            // Letter C
            if (c_pixel(x, y, C_X, C_Y))
                pixel_color = COL_ACCENT;
        end
    end
endmodule

`default_nettype wire
