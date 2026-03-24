// ============================================================
// keypad_renderer.v
// ------------------------------------------------------------
// 4x4 Hex Keypad Renderer (Layout A) - NO HOME BUTTON
// - Draws a centered 4x4 keypad with labels 0-9 and A-F
// - Highlights the most recently selected key (selected_hex)
// - Larger label font via 2x scale of the 4x7 font (8x14)
// RGB565 output.
// ============================================================

`timescale 1ns/1ps

module keypad_renderer #(
    parameter integer GAME_W  = 320,
    parameter integer GAME_H  = 240,

    // Orientation controls (match the other renderers)
    parameter SWAP_XY = 0,
    parameter FLIP_X  = 0,
    parameter FLIP_Y  = 0,

    // Keypad geometry (MUST match keypad_touch_decode)
    // Centered defaults:
    //   total_w = 4*KEY_W + 3*GAP = 264  => KP_X0 = (320-264)/2 = 28
    //   total_h = 4*KEY_H + 3*GAP = 204  => KP_Y0 = (240-204)/2 = 18
    parameter integer KP_X0  = 28,
    parameter integer KP_Y0  = 18,
    parameter integer KEY_W  = 60,
    parameter integer KEY_H  = 45,
    parameter integer GAP    = 8
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        framebufferClk,

    input  wire [3:0]  selected_hex,  // highlight this key
    output reg  [15:0] pixel_color
);

    // --------------------------------------------------------------------
    // Colors (RGB565)
    // --------------------------------------------------------------------
    localparam [15:0] COL_BG         = 16'hFFFF; // white
    localparam [15:0] COL_KEY_FILL   = 16'hC618; // light gray
    localparam [15:0] COL_KEY_BORDER = 16'h7BEF; // darker gray

    // "Transparent-ish" highlight: very light blue/cyan so black text stays readable
    localparam [15:0] COL_HIGHLIGHT  = 16'hD7FF; // pastel cyan (very light)

    localparam [15:0] COL_TEXT       = 16'h0000; // black

    // --------------------------------------------------------------------
    // Scan counters (must match TFT scan: x=0..319, y=0..239)
    // --------------------------------------------------------------------
    localparam integer LCD_W = 320;
    localparam integer LCD_H = 240;

    reg [8:0] x; // 0..319
    reg [8:0] y; // 0..239

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 9'd0;
            y <= 9'd0;
        end else if (framebufferClk) begin
            if (x == LCD_W-1) begin
                x <= 9'd0;
                if (y == LCD_H-1) y <= 9'd0;
                else              y <= y + 9'd1;
            end else begin
                x <= x + 9'd1;
            end
        end
    end

    // --------------------------------------------------------------------
    // Orientation mapping
    // --------------------------------------------------------------------
    wire [8:0] sx = x;
    wire [8:0] sy = y;

    wire [8:0] mx = (FLIP_X) ? (LCD_W-1 - sx) : sx;
    wire [8:0] my = (FLIP_Y) ? (LCD_H-1 - sy) : sy;

    wire [8:0] game_x = (SWAP_XY) ? my : mx;
    wire [8:0] game_y = (SWAP_XY) ? mx : my;

    // --------------------------------------------------------------------
    // font4x7 instance
    // --------------------------------------------------------------------
    localparam integer CHAR_W = 4;
    localparam integer CHAR_H = 7;

    reg  [7:0] font_char;
    reg  [2:0] font_x;
    reg  [2:0] font_y;
    wire       font_bit;

    font4x7 font_inst (
        .char(font_char),
        .x   (font_x),
        .y   (font_y),
        .bit (font_bit)
    );

    // --------------------------------------------------------------------
    // Label scaling (make the key label larger)
    // SCALE = 2  => 4x7 becomes 8x14
    // --------------------------------------------------------------------
    localparam integer SCALE   = 2;
    localparam integer LAB_W   = CHAR_W * SCALE; // 8
    localparam integer LAB_H   = CHAR_H * SCALE; // 14

    // --------------------------------------------------------------------
    // Map keypad cell index -> hex value (Layout A)
    //   1 2 3 A
    //   4 5 6 B
    //   7 8 9 C
    //   E 0 F D
    // --------------------------------------------------------------------
    function [3:0] map_idx;
        input [3:0] i;
        begin
            case (i)
                4'd0:  map_idx = 4'h1;
                4'd1:  map_idx = 4'h2;
                4'd2:  map_idx = 4'h3;
                4'd3:  map_idx = 4'hA;

                4'd4:  map_idx = 4'h4;
                4'd5:  map_idx = 4'h5;
                4'd6:  map_idx = 4'h6;
                4'd7:  map_idx = 4'hB;

                4'd8:  map_idx = 4'h7;
                4'd9:  map_idx = 4'h8;
                4'd10: map_idx = 4'h9;
                4'd11: map_idx = 4'hC;

                4'd12: map_idx = 4'hE;
                4'd13: map_idx = 4'h0;
                4'd14: map_idx = 4'hF;
                4'd15: map_idx = 4'hD;

                default: map_idx = 4'h0;
            endcase
        end
    endfunction

    function [7:0] hex_to_char;
        input [3:0] v;
        begin
            case (v)
                4'h0: hex_to_char = "0";
                4'h1: hex_to_char = "1";
                4'h2: hex_to_char = "2";
                4'h3: hex_to_char = "3";
                4'h4: hex_to_char = "4";
                4'h5: hex_to_char = "5";
                4'h6: hex_to_char = "6";
                4'h7: hex_to_char = "7";
                4'h8: hex_to_char = "8";
                4'h9: hex_to_char = "9";
                4'hA: hex_to_char = "A";
                4'hB: hex_to_char = "B";
                4'hC: hex_to_char = "C";
                4'hD: hex_to_char = "D";
                4'hE: hex_to_char = "E";
                4'hF: hex_to_char = "F";
                default: hex_to_char = "?";
            endcase
        end
    endfunction

    integer r, c;

    reg        in_key;
    reg        is_border;
    reg [3:0]  cell_idx;
    reg [3:0]  cell_hex;
    reg [8:0]  key_x0, key_y0, key_x1, key_y1;

    // Label placement + local offsets
    reg [8:0]  label_x0, label_y0;
    reg [8:0]  dx, dy;

    always @* begin
        // defaults
        pixel_color = COL_BG;

        font_char = 8'h20;
        font_x    = 3'd0;
        font_y    = 3'd0;

        // ------------------------------------------------------------
        // Keypad keys
        // ------------------------------------------------------------
        for (r = 0; r < 4; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                key_x0 = KP_X0 + c*(KEY_W+GAP);
                key_y0 = KP_Y0 + r*(KEY_H+GAP);
                key_x1 = key_x0 + KEY_W - 1;
                key_y1 = key_y0 + KEY_H - 1;

                in_key = (game_x >= key_x0) && (game_x <= key_x1) &&
                         (game_y >= key_y0) && (game_y <= key_y1);

                if (in_key) begin
                    cell_idx = r*4 + c;
                    cell_hex = map_idx(cell_idx);

                    is_border = (game_x == key_x0) || (game_x == key_x1) ||
                                (game_y == key_y0) || (game_y == key_y1);

                    if (is_border)
                        pixel_color = COL_KEY_BORDER;
                    else if (cell_hex == selected_hex)
                        pixel_color = COL_HIGHLIGHT;
                    else
                        pixel_color = COL_KEY_FILL;

                    // ----------------------------------------------------
                    // Draw 1-char label, scaled up (SCALE=2)
                    // ----------------------------------------------------
                    label_x0 = key_x0 + (KEY_W - LAB_W)/2;
                    label_y0 = key_y0 + (KEY_H - LAB_H)/2;

                    if ((game_x >= label_x0) && (game_x < label_x0 + LAB_W) &&
                        (game_y >= label_y0) && (game_y < label_y0 + LAB_H)) begin

                        font_char = hex_to_char(cell_hex);

                        dx = game_x - label_x0; // 0..LAB_W-1
                        dy = game_y - label_y0; // 0..LAB_H-1

                        // SCALE=2 => divide by 2 using >>1
                        font_x = dx[3:1];
                        font_y = dy[3:1];

                        if (font_bit)
                            pixel_color = COL_TEXT;
                    end
                end
            end
        end
    end

endmodule
