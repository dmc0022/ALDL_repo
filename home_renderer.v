// home_renderer.v
// Home screen with:
//   - Breakout app icon (48x48 ROM) + "BREAKOUT" label
//   - GIF app icon box (48x48) + "GIF" text and "CPE 431" label
//
// Uses font4x7 (4x7) for all text.

`timescale 1ns/1ps

module home_renderer #(
    parameter integer GAME_W  = 320,
    parameter integer GAME_H  = 240
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        framebufferClk,   // from tft_ili9341

    output reg  [15:0] pixel_color       // RGB565
);

    // Physical panel dimensions
    localparam LCD_W = 240;
    localparam LCD_H = 320;

    // ------------------------------------------------------------
    // Breakout icon sprite ROM (48x48 RGB565, row-major)
    // ------------------------------------------------------------
    localparam ICON_W       = 48;
    localparam ICON_H       = 48;
    localparam ICON_PIXELS  = ICON_W * ICON_H;   // 2304

    // Shared margins (must match top-level ICON_MARGIN_X/Y)
    localparam ICON_MARGIN_X = 16;
    localparam ICON_MARGIN_Y = 16;

    // Breakout icon position (top-right)
    localparam ICON_X0 = GAME_W - ICON_W - ICON_MARGIN_X;  // 256
    localparam ICON_Y0 = ICON_MARGIN_Y;                    // 16

    // GIF icon position (top-left)
    localparam GIF_ICON_X0 = ICON_MARGIN_X;                // 16
    localparam GIF_ICON_Y0 = ICON_MARGIN_Y;                // 16
    localparam GIF_ICON_X1 = GIF_ICON_X0 + ICON_W - 1;     // 63
    localparam GIF_ICON_Y1 = GIF_ICON_Y0 + ICON_H - 1;     // 63

    // Sprite ROM initialized from hex file generated for the Breakout icon
    (* romstyle    = "M9K",
       ramstyle    = "M9K",
       ram_init_file = "breakout_icon_48x48_rgb565.hex" *)
    reg [15:0] icon_mem [0:ICON_PIXELS-1];

    initial begin
        $readmemh("breakout_icon_48x48_rgb565.hex", icon_mem);
    end

    // ------------------------------------------------------------
    // Font parameters (font4x7, no scaling here)
    // ------------------------------------------------------------
    localparam CHAR_W     = 4;    // 4 pixels wide
    localparam CHAR_H     = 7;    // 7 pixels tall
    localparam CHAR_SPACE = 1;    // 1-pixel column between characters

    // "BREAKOUT" label under Breakout icon
    localparam BREAK_LABEL_CHARS = 8;    // B R E A K O U T
    localparam BREAK_LABEL_W     = BREAK_LABEL_CHARS*CHAR_W +
                                   (BREAK_LABEL_CHARS-1)*CHAR_SPACE;
    localparam BREAK_LABEL_X0    = ICON_X0 + (ICON_W - BREAK_LABEL_W)/2;
    localparam BREAK_LABEL_Y0    = ICON_Y0 + ICON_H + 8;   // 8-pixel gap

    // "CPE 431" label under GIF icon
    localparam GIF_LABEL_CHARS = 7;   // C P E ' ' 4 3 1
    localparam GIF_LABEL_W     = GIF_LABEL_CHARS*CHAR_W +
                                 (GIF_LABEL_CHARS-1)*CHAR_SPACE;
    localparam GIF_LABEL_X0    = GIF_ICON_X0 + (ICON_W - GIF_LABEL_W)/2;
    localparam GIF_LABEL_Y0    = GIF_ICON_Y0 + ICON_H + 8;

    // "GIF" text inside GIF icon
    localparam GIF_TEXT_CHARS  = 3;   // G I F
    localparam GIF_TEXT_W      = GIF_TEXT_CHARS*CHAR_W +
                                 (GIF_TEXT_CHARS-1)*CHAR_SPACE;
    localparam GIF_TEXT_X0     = GIF_ICON_X0 + (ICON_W - GIF_TEXT_W)/2;
    localparam GIF_TEXT_Y0     = GIF_ICON_Y0 + (ICON_H - CHAR_H)/2;

    // Colors
    localparam [15:0] COL_BG      = 16'hFFFF;  // white background
    localparam [15:0] COL_TEXT    = 16'h0000;  // black text
    localparam [15:0] COL_ICONBOX = 16'hFFE0;  // yellow GIF icon fill
    localparam [15:0] COL_BORDER  = 16'h0000;  // black border

    // --------------------------------------------------------------------
    // Physical X/Y pixel counters driven by framebufferClk
    // --------------------------------------------------------------------
    reg [8:0] x;  // 0..239
    reg [8:0] y;  // 0..319
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

    // Same rotation as breakout_renderer
    wire [8:0] game_x = y;                 // 0..319
    wire [8:0] game_y = LCD_W - 1 - x;     // 0..239

    // --------------------------------------------------------------------
    // font4x7 instance
    // --------------------------------------------------------------------
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
    // Combinational drawing (background, GIF icon+text, Breakout icon+label)
    // --------------------------------------------------------------------
    reg  [8:0]  lx, ly;          // local coords inside Breakout icon
    reg  [11:0] icon_addr;       // 0..2303
    reg  [15:0] icon_pixel;

    reg  [8:0]  tx;
    reg  [8:0]  ty;
    reg  [3:0]  char_idx;
    reg  [2:0]  cx, cy;

    always @* begin
        // default background
        pixel_color = COL_BG;

        // default font inputs
        font_char = 8'h20;  // space
        font_x    = 3'd0;
        font_y    = 3'd0;

        // ---------- GIF ICON BOX (left) ----------
        if ( (game_x >= GIF_ICON_X0) && (game_x <= GIF_ICON_X1) &&
             (game_y >= GIF_ICON_Y0) && (game_y <= GIF_ICON_Y1) ) begin

            // border
            if (game_x == GIF_ICON_X0 || game_x == GIF_ICON_X1 ||
                game_y == GIF_ICON_Y0 || game_y == GIF_ICON_Y1)
                pixel_color = COL_BORDER;
            else
                pixel_color = COL_ICONBOX;
        end

        // ---------- "GIF" text inside GIF icon ----------
        if ( (game_x >= GIF_TEXT_X0) &&
             (game_x <  GIF_TEXT_X0 + GIF_TEXT_W) &&
             (game_y >= GIF_TEXT_Y0) &&
             (game_y <  GIF_TEXT_Y0 + CHAR_H) ) begin

            tx = game_x - GIF_TEXT_X0;   // 0..GIF_TEXT_W-1
            ty = game_y - GIF_TEXT_Y0;   // 0..CHAR_H-1

            char_idx = tx / (CHAR_W + CHAR_SPACE);  // 0..2
            cx       = tx % (CHAR_W + CHAR_SPACE);  // 0..(CHAR_W+SPACE-1)
            cy       = ty[2:0];                     // 0..6

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "G";
                    1: font_char = "I";
                    2: font_char = "F";
                    default: font_char = " ";
                endcase

                font_x = cx;   // 0..3
                font_y = cy;   // 0..6

                if (font_bit)
                    pixel_color = COL_TEXT;
            end
        end

        // ---------- GIF LABEL "CPE 431" under GIF icon ----------
        if ( (game_x >= GIF_LABEL_X0) &&
             (game_x <  GIF_LABEL_X0 + GIF_LABEL_W) &&
             (game_y >= GIF_LABEL_Y0) &&
             (game_y <  GIF_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - GIF_LABEL_X0;
            ty = game_y - GIF_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);  // 0..6
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "C";
                    1: font_char = "P";
                    2: font_char = "E";
                    3: font_char = " ";
                    4: font_char = "4";
                    5: font_char = "3";
                    6: font_char = "1";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit)
                    pixel_color = COL_TEXT;
            end
        end

        // ---------- EXISTING BREAKOUT ICON (ROM) ----------
        lx        = 9'd0;
        ly        = 9'd0;
        icon_addr = 12'd0;
        icon_pixel= 16'h0000;

        if ( (game_x >= ICON_X0) && (game_x < ICON_X0 + ICON_W) &&
             (game_y >= ICON_Y0) && (game_y < ICON_Y0 + ICON_H) ) begin

            lx        = game_x - ICON_X0;
            ly        = game_y - ICON_Y0;
            icon_addr = ly * ICON_W + lx;
            icon_pixel= icon_mem[icon_addr];

            pixel_color = icon_pixel;
        end

        // ---------- BREAKOUT LABEL "BREAKOUT" ----------
        if ( (game_x >= BREAK_LABEL_X0) &&
             (game_x <  BREAK_LABEL_X0 + BREAK_LABEL_W) &&
             (game_y >= BREAK_LABEL_Y0) &&
             (game_y <  BREAK_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - BREAK_LABEL_X0;
            ty = game_y - BREAK_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);  // 0..7
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "B";
                    1: font_char = "R";
                    2: font_char = "E";
                    3: font_char = "A";
                    4: font_char = "K";
                    5: font_char = "O";
                    6: font_char = "U";
                    7: font_char = "T";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit)
                    pixel_color = COL_TEXT;
            end
        end
    end

endmodule
