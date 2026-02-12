// home_renderer.v
// -----------------------------------------------------------------------------
// Home screen renderer (320x240 game space)
//
// This renderer outputs one pixel per framebufferClk pulse. It maintains an
// internal (x,y) counter that MUST match the TFT driver's scan order.
//
// In the regenerated system:
//  - TFT driver always writes a 320x240 window each frame
//  - framebufferClk pulses exactly once per pixel
//  - This renderer increments x/y exactly once per pulse
//
// Orientation handling:
//  - If the display is mirrored/rotated due to MADCTL, fix it here by toggling
//    SWAP_XY / FLIP_X / FLIP_Y. This keeps the TFT driver stable for students.
// -----------------------------------------------------------------------------

/* `timescale 1ns/1ps

module home_renderer #(
    parameter integer GAME_W  = 320,
    parameter integer GAME_H  = 240,

    // Orientation knobs (set these to make the home screen appear correct)
    // Start with all 0. If mirrored/rotated, toggle one at a time.
    parameter SWAP_XY = 0,
    parameter FLIP_X  = 0,
    parameter FLIP_Y  = 0
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        framebufferClk,   // 1-cycle pulse per pixel from tft_ili9341

    output reg  [15:0] pixel_color       // RGB565
);

    // The scan geometry MUST match tft display window (320x240)
    localparam LCD_W = 320;
    localparam LCD_H = 240;

    // ------------------------------------------------------------
    // Breakout icon sprite ROM (48x48 RGB565, row-major)
    // ------------------------------------------------------------
    localparam ICON_W       = 48;
    localparam ICON_H       = 48;
    localparam ICON_PIXELS  = ICON_W * ICON_H;   // 2304

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

    (* romstyle    = "M9K",
       ramstyle    = "M9K",
       ram_init_file = "breakout_icon_48x48_rgb565.hex" *)
    reg [15:0] icon_mem [0:ICON_PIXELS-1];

    initial begin
        $readmemh("breakout_icon_48x48_rgb565.hex", icon_mem);
    end

    // ------------------------------------------------------------
    // Font parameters (font4x7)
    // ------------------------------------------------------------
    localparam CHAR_W     = 4;
    localparam CHAR_H     = 7;
    localparam CHAR_SPACE = 1;

    // "BREAKOUT" label under Breakout icon
    localparam BREAK_LABEL_CHARS = 8;
    localparam BREAK_LABEL_W     = BREAK_LABEL_CHARS*CHAR_W +
                                   (BREAK_LABEL_CHARS-1)*CHAR_SPACE;
    localparam BREAK_LABEL_X0    = ICON_X0 + (ICON_W - BREAK_LABEL_W)/2;
    localparam BREAK_LABEL_Y0    = ICON_Y0 + ICON_H + 8;

    // "CPE 431" label under GIF icon
    localparam GIF_LABEL_CHARS = 7;
    localparam GIF_LABEL_W     = GIF_LABEL_CHARS*CHAR_W +
                                 (GIF_LABEL_CHARS-1)*CHAR_SPACE;
    localparam GIF_LABEL_X0    = GIF_ICON_X0 + (ICON_W - GIF_LABEL_W)/2;
    localparam GIF_LABEL_Y0    = GIF_ICON_Y0 + ICON_H + 8;

    // "GIF" text inside GIF icon
    localparam GIF_TEXT_CHARS  = 3;
    localparam GIF_TEXT_W      = GIF_TEXT_CHARS*CHAR_W +
                                 (GIF_TEXT_CHARS-1)*CHAR_SPACE;
    localparam GIF_TEXT_X0     = GIF_ICON_X0 + (ICON_W - GIF_TEXT_W)/2;
    localparam GIF_TEXT_Y0     = GIF_ICON_Y0 + (ICON_H - CHAR_H)/2;

    // Colors
    localparam [15:0] COL_BG      = 16'hFFFF;
    localparam [15:0] COL_TEXT    = 16'h0000;
    localparam [15:0] COL_ICONBOX = 16'hFFE0;
    localparam [15:0] COL_BORDER  = 16'h0000;

    // --------------------------------------------------------------------
    // Scan X/Y counters (must match TFT scan: x=0..319, y=0..239)
    // framebufferClk is a 1-cycle pulse, synchronous to clk
    // --------------------------------------------------------------------
    reg [8:0] x; // 0..319
    reg [8:0] y; // 0..239

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 9'd0;
            y <= 9'd0;
        end else begin
            if (framebufferClk) begin
                if (x == LCD_W-1) begin
                    x <= 9'd0;
                    if (y == LCD_H-1) y <= 9'd0;
                    else              y <= y + 9'd1;
                end else begin
                    x <= x + 9'd1;
                end
            end
        end
    end

    // --------------------------------------------------------------------
    // Orientation mapping (fix display rotation/mirroring here)
    // --------------------------------------------------------------------
    wire [8:0] sx = x;
    wire [8:0] sy = y;

    wire [8:0] mx = (FLIP_X) ? (LCD_W-1 - sx) : sx;
    wire [8:0] my = (FLIP_Y) ? (LCD_H-1 - sy) : sy;

    wire [8:0] game_x = (SWAP_XY) ? my : mx; // if swap, x comes from y-space
    wire [8:0] game_y = (SWAP_XY) ? mx : my;

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
    // Draw logic
    // --------------------------------------------------------------------
    reg  [8:0]  lx, ly;
    reg  [11:0] icon_addr;
    reg  [15:0] icon_pixel;

    reg  [8:0]  tx, ty;
    reg  [3:0]  char_idx;
    reg  [2:0]  cx, cy;

    always @* begin
        pixel_color = COL_BG;

        font_char = 8'h20;
        font_x    = 3'd0;
        font_y    = 3'd0;

        // ---------- GIF ICON BOX ----------
        if ( (game_x >= GIF_ICON_X0) && (game_x <= GIF_ICON_X1) &&
             (game_y >= GIF_ICON_Y0) && (game_y <= GIF_ICON_Y1) ) begin

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

            tx = game_x - GIF_TEXT_X0;
            ty = game_y - GIF_TEXT_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "G";
                    1: font_char = "I";
                    2: font_char = "F";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- "CPE 431" label ----------
        if ( (game_x >= GIF_LABEL_X0) &&
             (game_x <  GIF_LABEL_X0 + GIF_LABEL_W) &&
             (game_y >= GIF_LABEL_Y0) &&
             (game_y <  GIF_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - GIF_LABEL_X0;
            ty = game_y - GIF_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
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

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- Breakout icon ----------
        lx         = 9'd0;
        ly         = 9'd0;
        icon_addr  = 12'd0;
        icon_pixel = 16'h0000;

        if ( (game_x >= ICON_X0) && (game_x < ICON_X0 + ICON_W) &&
             (game_y >= ICON_Y0) && (game_y < ICON_Y0 + ICON_H) ) begin

            lx        = game_x - ICON_X0;
            ly        = game_y - ICON_Y0;
            icon_addr = ly * ICON_W + lx;
            icon_pixel= icon_mem[icon_addr];

            pixel_color = icon_pixel;
        end

        // ---------- "BREAKOUT" label ----------
        if ( (game_x >= BREAK_LABEL_X0) &&
             (game_x <  BREAK_LABEL_X0 + BREAK_LABEL_W) &&
             (game_y >= BREAK_LABEL_Y0) &&
             (game_y <  BREAK_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - BREAK_LABEL_X0;
            ty = game_y - BREAK_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
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

                if (font_bit) pixel_color = COL_TEXT;
            end
        end
    end

endmodule */

// home_renderer.v
// -----------------------------------------------------------------------------
// Home screen renderer (320x240 game space)
//
// This renderer outputs one pixel per framebufferClk pulse. It maintains an
// internal (x,y) counter that MUST match the TFT driver's scan order.
//
// In the regenerated system:
//  - TFT driver always writes a 320x240 window each frame
//  - framebufferClk pulses once per pixel
//
// Home screen contents:
//  - Breakout icon sprite at top-right + "BREAKOUT" label
//  - GIF icon box at top-left + "GIF" inside + "CPE 431" label
//  - KEYPAD icon box at top-center + "KEY" inside + "KEYPAD" label
//
// IMPORTANT:
//  - The icon geometry constants MUST match the hitbox geometry
//    inside LCD_driver_top.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module home_renderer #(
    parameter integer GAME_W  = 320,
    parameter integer GAME_H  = 240,
    parameter SWAP_XY = 0,
    parameter FLIP_X  = 0,
    parameter FLIP_Y  = 0
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        framebufferClk,
    output reg  [15:0] pixel_color
);

    localparam LCD_W = 320;
    localparam LCD_H = 240;

    // ------------------------------------------------------------
    // Breakout icon sprite ROM (48x48 RGB565, row-major)
    // ------------------------------------------------------------
    localparam ICON_W       = 48;
    localparam ICON_H       = 48;
    localparam ICON_PIXELS  = ICON_W * ICON_H;   // 2304

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

    // KEYPAD icon position (top-center)
    localparam KEYPAD_ICON_X0 = (GAME_W - ICON_W)/2;          // 136
    localparam KEYPAD_ICON_Y0 = ICON_MARGIN_Y;                // 16
    localparam KEYPAD_ICON_X1 = KEYPAD_ICON_X0 + ICON_W - 1;  // 183
    localparam KEYPAD_ICON_Y1 = KEYPAD_ICON_Y0 + ICON_H - 1;  // 63

    (* romstyle    = "M9K",
       ramstyle    = "M9K",
       ram_init_file = "breakout_icon_48x48_rgb565.hex" *)
    reg [15:0] icon_mem [0:ICON_PIXELS-1];

    initial begin
        $readmemh("breakout_icon_48x48_rgb565.hex", icon_mem);
    end

    // ------------------------------------------------------------
    // Font parameters (font4x7)
    // ------------------------------------------------------------
    localparam CHAR_W     = 4;
    localparam CHAR_H     = 7;
    localparam CHAR_SPACE = 1;

    // "BREAKOUT" label under Breakout icon
    localparam BREAK_LABEL_CHARS = 8;
    localparam BREAK_LABEL_W     = BREAK_LABEL_CHARS*CHAR_W +
                                   (BREAK_LABEL_CHARS-1)*CHAR_SPACE;
    localparam BREAK_LABEL_X0    = ICON_X0 + (ICON_W - BREAK_LABEL_W)/2;
    localparam BREAK_LABEL_Y0    = ICON_Y0 + ICON_H + 8;

    // "CPE 431" label under GIF icon
    localparam GIF_LABEL_CHARS = 7;
    localparam GIF_LABEL_W     = GIF_LABEL_CHARS*CHAR_W +
                                 (GIF_LABEL_CHARS-1)*CHAR_SPACE;
    localparam GIF_LABEL_X0    = GIF_ICON_X0 + (ICON_W - GIF_LABEL_W)/2;
    localparam GIF_LABEL_Y0    = GIF_ICON_Y0 + ICON_H + 8;

    // "KEYPAD" label under KEYPAD icon
    localparam KEYPAD_LABEL_CHARS = 6;
    localparam KEYPAD_LABEL_W     = KEYPAD_LABEL_CHARS*CHAR_W +
                                    (KEYPAD_LABEL_CHARS-1)*CHAR_SPACE;
    localparam KEYPAD_LABEL_X0    = KEYPAD_ICON_X0 + (ICON_W - KEYPAD_LABEL_W)/2;
    localparam KEYPAD_LABEL_Y0    = KEYPAD_ICON_Y0 + ICON_H + 8;

    // "KEY" text inside KEYPAD icon (keeps it uncluttered)
    localparam KEYPAD_TEXT_CHARS  = 3;
    localparam KEYPAD_TEXT_W      = KEYPAD_TEXT_CHARS*CHAR_W +
                                    (KEYPAD_TEXT_CHARS-1)*CHAR_SPACE;
    localparam KEYPAD_TEXT_X0     = KEYPAD_ICON_X0 + (ICON_W - KEYPAD_TEXT_W)/2;
    localparam KEYPAD_TEXT_Y0     = KEYPAD_ICON_Y0 + (ICON_H - CHAR_H)/2;

    // "GIF" text inside GIF icon
    localparam GIF_TEXT_CHARS  = 3;
    localparam GIF_TEXT_W      = GIF_TEXT_CHARS*CHAR_W +
                                 (GIF_TEXT_CHARS-1)*CHAR_SPACE;
    localparam GIF_TEXT_X0     = GIF_ICON_X0 + (ICON_W - GIF_TEXT_W)/2;
    localparam GIF_TEXT_Y0     = GIF_ICON_Y0 + (ICON_H - CHAR_H)/2;

    // Colors
    localparam [15:0] COL_BG      = 16'hFFFF;
    localparam [15:0] COL_TEXT    = 16'h0000;
    localparam [15:0] COL_ICONBOX = 16'hFFE0;
    localparam [15:0] COL_BORDER  = 16'h0000;

    // --------------------------------------------------------------------
    // Scan X/Y counters (must match TFT scan: x=0..319, y=0..239)
    // framebufferClk is a 1-cycle pulse, synchronous to clk
    // --------------------------------------------------------------------
    reg [8:0] x; // 0..319
    reg [8:0] y; // 0..239

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 9'd0;
            y <= 9'd0;
        end else begin
            if (framebufferClk) begin
                if (x == LCD_W-1) begin
                    x <= 9'd0;
                    if (y == LCD_H-1) y <= 9'd0;
                    else              y <= y + 9'd1;
                end else begin
                    x <= x + 9'd1;
                end
            end
        end
    end

    // --------------------------------------------------------------------
    // Orientation mapping (fix display rotation/mirroring here)
    // --------------------------------------------------------------------
    wire [8:0] sx = x;
    wire [8:0] sy = y;

    wire [8:0] mx = (FLIP_X) ? (LCD_W-1 - sx) : sx;
    wire [8:0] my = (FLIP_Y) ? (LCD_H-1 - sy) : sy;

    wire [8:0] game_x = (SWAP_XY) ? my : mx; // if swap, x comes from y-space
    wire [8:0] game_y = (SWAP_XY) ? mx : my;

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
    // Draw logic
    // --------------------------------------------------------------------
    reg  [8:0]  lx, ly;
    reg  [11:0] icon_addr;
    reg  [15:0] icon_pixel;

    reg  [8:0]  tx, ty;
    reg  [3:0]  char_idx;
    reg  [2:0]  cx, cy;

    always @* begin
        pixel_color = COL_BG;

        font_char = 8'h20;
        font_x    = 3'd0;
        font_y    = 3'd0;

        // ---------- GIF ICON BOX ----------
        if ( (game_x >= GIF_ICON_X0) && (game_x <= GIF_ICON_X1) &&
             (game_y >= GIF_ICON_Y0) && (game_y <= GIF_ICON_Y1) ) begin

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

            tx = game_x - GIF_TEXT_X0;
            ty = game_y - GIF_TEXT_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "G";
                    1: font_char = "I";
                    2: font_char = "F";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- "CPE 431" label ----------
        if ( (game_x >= GIF_LABEL_X0) &&
             (game_x <  GIF_LABEL_X0 + GIF_LABEL_W) &&
             (game_y >= GIF_LABEL_Y0) &&
             (game_y <  GIF_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - GIF_LABEL_X0;
            ty = game_y - GIF_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
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

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- KEYPAD ICON BOX ----------
        if ( (game_x >= KEYPAD_ICON_X0) && (game_x <= KEYPAD_ICON_X1) &&
             (game_y >= KEYPAD_ICON_Y0) && (game_y <= KEYPAD_ICON_Y1) ) begin

            if (game_x == KEYPAD_ICON_X0 || game_x == KEYPAD_ICON_X1 ||
                game_y == KEYPAD_ICON_Y0 || game_y == KEYPAD_ICON_Y1)
                pixel_color = COL_BORDER;
            else
                pixel_color = COL_ICONBOX;
        end

        // ---------- "KEY" text inside KEYPAD icon ----------
        if ( (game_x >= KEYPAD_TEXT_X0) &&
             (game_x <  KEYPAD_TEXT_X0 + KEYPAD_TEXT_W) &&
             (game_y >= KEYPAD_TEXT_Y0) &&
             (game_y <  KEYPAD_TEXT_Y0 + CHAR_H) ) begin

            tx = game_x - KEYPAD_TEXT_X0;
            ty = game_y - KEYPAD_TEXT_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "K";
                    1: font_char = "E";
                    2: font_char = "Y";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- "KEYPAD" label ----------
        if ( (game_x >= KEYPAD_LABEL_X0) &&
             (game_x <  KEYPAD_LABEL_X0 + KEYPAD_LABEL_W) &&
             (game_y >= KEYPAD_LABEL_Y0) &&
             (game_y <  KEYPAD_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - KEYPAD_LABEL_X0;
            ty = game_y - KEYPAD_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
            cx       = tx % (CHAR_W + CHAR_SPACE);
            cy       = ty[2:0];

            if (cx < CHAR_W && cy < CHAR_H) begin
                case (char_idx)
                    0: font_char = "K";
                    1: font_char = "E";
                    2: font_char = "Y";
                    3: font_char = "P";
                    4: font_char = "A";
                    5: font_char = "D";
                    default: font_char = " ";
                endcase

                font_x = cx;
                font_y = cy;

                if (font_bit) pixel_color = COL_TEXT;
            end
        end

        // ---------- Breakout icon ----------
        lx         = 9'd0;
        ly         = 9'd0;
        icon_addr  = 12'd0;
        icon_pixel = 16'h0000;

        if ( (game_x >= ICON_X0) && (game_x < ICON_X0 + ICON_W) &&
             (game_y >= ICON_Y0) && (game_y < ICON_Y0 + ICON_H) ) begin

            lx        = game_x - ICON_X0;
            ly        = game_y - ICON_Y0;
            icon_addr = ly * ICON_W + lx;
            icon_pixel= icon_mem[icon_addr];

            pixel_color = icon_pixel;
        end

        // ---------- "BREAKOUT" label ----------
        if ( (game_x >= BREAK_LABEL_X0) &&
             (game_x <  BREAK_LABEL_X0 + BREAK_LABEL_W) &&
             (game_y >= BREAK_LABEL_Y0) &&
             (game_y <  BREAK_LABEL_Y0 + CHAR_H) ) begin

            tx = game_x - BREAK_LABEL_X0;
            ty = game_y - BREAK_LABEL_Y0;

            char_idx = tx / (CHAR_W + CHAR_SPACE);
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

                if (font_bit) pixel_color = COL_TEXT;
            end
        end
    end

endmodule

