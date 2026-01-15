// home_renderer.v
// Home screen with a Breakout app icon (48x48 ROM) and label.

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
    // Icon sprite ROM (48x48 RGB565, row-major)
    // ------------------------------------------------------------
    localparam ICON_W       = 48;
    localparam ICON_H       = 48;
    localparam ICON_PIXELS  = ICON_W * ICON_H;   // 2304

    // Place icon near top-right with margins (like a phone home screen)
    localparam ICON_MARGIN_X = 16;              // space from right edge
    localparam ICON_MARGIN_Y = 16;              // space from top edge

    localparam ICON_X0 = GAME_W - ICON_W - ICON_MARGIN_X;  // 320 - 48 - 16 = 256
    localparam ICON_Y0 = ICON_MARGIN_Y;                    // 16

    // Sprite ROM initialized from hex file generated for the icon
    (* romstyle    = "M9K",
       ramstyle    = "M9K",
       ram_init_file = "breakout_icon_48x48_rgb565.hex" *)
    reg [15:0] icon_mem [0:ICON_PIXELS-1];

    initial begin
        $readmemh("breakout_icon_48x48_rgb565.hex", icon_mem);
    end

    // ------------------------------------------------------------
    // "BREAKOUT" label parameters (simple 6x7 bitmap font)
    // ------------------------------------------------------------
    localparam TEXT_W      = 6;    // pixels per character width
    localparam TEXT_H      = 7;    // pixels per character height
    localparam TEXT_SPACE  = 1;    // 1-pixel column between characters
    localparam LABEL_CHARS = 8;    // "BREAKOUT"

    localparam LABEL_W = LABEL_CHARS*TEXT_W + (LABEL_CHARS-1)*TEXT_SPACE;

    // Center label horizontally under icon, with some vertical spacing
    localparam LABEL_X0 = ICON_X0 + (ICON_W - LABEL_W)/2;
    localparam LABEL_Y0 = ICON_Y0 + ICON_H + 8;   // 8-pixel gap under icon

    // Colors
    localparam [15:0] COL_BG     = 16'hFFFF;  // white background
    localparam [15:0] COL_TEXT   = 16'h0000;  // black label text

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
    // Tiny bitmap font for the label "BREAKOUT"
    // ch index: 0:B 1:R 2:E 3:A 4:K 5:O 6:U 7:T
    // --------------------------------------------------------------------
    function is_text_pixel;
        input [3:0] ch;   // 0..7
        input [2:0] cx;   // 0..5
        input [2:0] cy;   // 0..6
        reg   [5:0] row;
    begin
        row = 6'b000000;
        case (ch)
            4'd0: begin // B
                case (cy)
                    0: row = 6'b111110;
                    1: row = 6'b100001;
                    2: row = 6'b111110;
                    3: row = 6'b100001;
                    4: row = 6'b100001;
                    5: row = 6'b111110;
                    default: row = 6'b000000;
                endcase
            end
            4'd1: begin // R
                case (cy)
                    0: row = 6'b111110;
                    1: row = 6'b100001;
                    2: row = 6'b111110;
                    3: row = 6'b101000;
                    4: row = 6'b100100;
                    5: row = 6'b100010;
                    default: row = 6'b000000;
                endcase
            end
            4'd2: begin // E
                case (cy)
                    0: row = 6'b111110;
                    1: row = 6'b100000;
                    2: row = 6'b111110;
                    3: row = 6'b100000;
                    4: row = 6'b100000;
                    5: row = 6'b111110;
                    default: row = 6'b000000;
                endcase
            end
            4'd3: begin // A
                case (cy)
                    0: row = 6'b011110;
                    1: row = 6'b100001;
                    2: row = 6'b100001;
                    3: row = 6'b111111;
                    4: row = 6'b100001;
                    5: row = 6'b100001;
                    default: row = 6'b000000;
                endcase
            end
            4'd4: begin // K
                case (cy)
                    0: row = 6'b100001;
                    1: row = 6'b100010;
                    2: row = 6'b111100;
                    3: row = 6'b100010;
                    4: row = 6'b100001;
                    5: row = 6'b100001;
                    default: row = 6'b000000;
                endcase
            end
            4'd5: begin // O
                case (cy)
                    0: row = 6'b011110;
                    1: row = 6'b100001;
                    2: row = 6'b100001;
                    3: row = 6'b100001;
                    4: row = 6'b100001;
                    5: row = 6'b011110;
                    default: row = 6'b000000;
                endcase
            end
            4'd6: begin // U
                case (cy)
                    0: row = 6'b100001;
                    1: row = 6'b100001;
                    2: row = 6'b100001;
                    3: row = 6'b100001;
                    4: row = 6'b100001;
                    5: row = 6'b011110;
                    default: row = 6'b000000;
                endcase
            end
            4'd7: begin // T
                case (cy)
                    0: row = 6'b111111;
                    1: row = 6'b001000;
                    2: row = 6'b001000;
                    3: row = 6'b001000;
                    4: row = 6'b001000;
                    5: row = 6'b001000;
                    default: row = 6'b000000;
                endcase
            end
            default: row = 6'b000000;
        endcase

        if (cx < TEXT_W)
            is_text_pixel = row[5 - cx];
        else
            is_text_pixel = 1'b0;
    end
    endfunction

    // --------------------------------------------------------------------
    // Combinational drawing (background, icon, label)
    // --------------------------------------------------------------------
    reg  [8:0]  lx, ly;          // local coords inside icon
    reg  [11:0] icon_addr;       // 0..2303
    reg  [15:0] icon_pixel;

    reg  [8:0]  tx;
    reg  [8:0]  ty;
    reg  [3:0]  char_idx;
    reg  [2:0]  cx, cy;

    always @* begin
        // default background
        pixel_color = COL_BG;

        // ---------- ICON ----------
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

        // ---------- LABEL "BREAKOUT" ----------
        // Only draw if we're in the small label area under the icon
        if ( (game_x >= LABEL_X0) && (game_x < LABEL_X0 + LABEL_W) &&
             (game_y >= LABEL_Y0) && (game_y < LABEL_Y0 + TEXT_H) ) begin

            tx = game_x - LABEL_X0;
            ty = game_y - LABEL_Y0;

            char_idx = tx / (TEXT_W + TEXT_SPACE);      // which letter 0..7
            cx       = tx % (TEXT_W + TEXT_SPACE);      // x within that letter cell
            cy       = ty[2:0];                         // y within letter (0..6)

            if (char_idx < LABEL_CHARS && cx < TEXT_W) begin
                if (is_text_pixel(char_idx, cx, cy))
                    pixel_color = COL_TEXT;   // black text pixel
            end
        end
    end

endmodule
