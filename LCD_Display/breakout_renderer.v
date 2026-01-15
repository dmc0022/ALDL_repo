// breakout_renderer.v
// Sprite-based Breakout renderer with:
//  - Sprite ROMs for bricks, paddle, and ball
//  - Gradient blue background
//  - Larger text for SCORE / PLAY / QUIT (scaled 2x from 4x7 -> 8x14)
//  - No green Game Over panel; just buttons on background
//  - Score digits separated by 4 pixels for better readability
//  - Animated paddle flash on ball hit
//  - Brick destroy flash (white ghost bricks for a few frames)

`timescale 1ns/1ps

module breakout_renderer (
    input  wire        clk,             // 50 MHz
    input  wire        reset_n,         // active-low reset
    input  wire        framebufferClk,  // from tft_ili9341

    // Positions in GAME coordinates (0..319 x 0..239)
    input  wire [8:0]  paddle_x_center, // paddle center X
    input  wire [8:0]  ball_x_pix,      // ball top-left X
    input  wire [8:0]  ball_y_pix,      // ball top-left Y

    // Brick alive bits and score
    input  wire [47:0] bricks_alive,    // 6*8
    input  wire [9:0]  score,

    // Game over flag (show UI instead of gameplay)
    input  wire        game_over,

    output reg [15:0]  pixel_color      // RGB565
);

    // --------------------------------------------------------------------
    // Physical / logical layout parameters
    // --------------------------------------------------------------------
    // Physical panel dimensions
    localparam LCD_W = 240;
    localparam LCD_H = 320;

    // Logical game dimensions (landscape)
    localparam GAME_W = 320;
    localparam GAME_H = 240;

    // HUD (home/score) reserved region
    localparam HUD_H  = 24;            // top 24 pixels

    // Brick layout in game coordinates
    localparam BRICK_ROWS   = 6;
    localparam BRICK_COLS   = 8;

    // Brick sprite size  (from brick_green_reduced.png: 32x9)
    localparam SPR_BRICK_W  = 32;
    localparam SPR_BRICK_H  = 9;

    localparam BRICK_W      = SPR_BRICK_W;
    localparam BRICK_H      = SPR_BRICK_H;
    localparam BRICK_X_SP   = 3;
    localparam BRICK_Y_SP   = 4;
    localparam BRICK_X0     = 5;
    localparam BRICK_Y0     = HUD_H + 8;

    // Paddle sprite geometry (from paddle_yellow_reduced.png: 32x9)
    localparam SPR_PADDLE_W   = 32;
    localparam SPR_PADDLE_H   = 9;
    localparam SPR_PADDLE_X0  = 0;
    localparam SPR_PADDLE_Y0  = 0;

    localparam PADDLE_W     = SPR_PADDLE_W;
    localparam PADDLE_H     = SPR_PADDLE_H;
    localparam PADDLE_Y     = GAME_H - 30;

    // Ball sprite geometry (from ball_yellow_reduced.png: 8x8)
    localparam SPR_BALL_W   = 8;
    localparam SPR_BALL_H   = 8;
    localparam SPR_BALL_X0  = 0;
    localparam SPR_BALL_Y0  = 0;

    localparam BALL_SIZE    = SPR_BALL_W;   // 8

    // BASE font size (logical 4x7) and scaled on-screen size (8x14)
    localparam FONT_W       = 4;
    localparam FONT_H       = 7;
    localparam DIGIT_W      = FONT_W * 2;   // 8 pixels on screen
    localparam DIGIT_H      = FONT_H * 2;   // 14 pixels on screen

    // Extra spacing between score digits
    localparam DIGIT_SPACING = 4;
    localparam SCORE_TOTAL_W = 3*DIGIT_W + 2*DIGIT_SPACING; // 3 digits + 2 gaps

    // Score placement
    localparam SCORE_Y0     = 4;   // within HUD
    // Right-aligned (digits only, including spacing), 4-pixel right margin
    localparam SCORE_X0     = GAME_W - SCORE_TOTAL_W - 4;

    // "Score:" label (6 characters)
    localparam LABEL_LEN    = 6;   // "Score:"
    localparam LABEL_X0     = SCORE_X0 - 1 - LABEL_LEN*DIGIT_W;
    localparam LABEL_Y0     = SCORE_Y0;

    // Game Over UI geometry (in game coordinates)
    // NOTE: we no longer draw a colored panel background; only buttons.
    localparam GO_PANEL_X0  = 60;
    localparam GO_PANEL_Y0  = 50;
    localparam GO_PANEL_W   = 200;
    localparam GO_PANEL_H   = 140;

    // Buttons (must match top-level hit-test)
    localparam PLAY_X0      = 90;
    localparam PLAY_X1      = 230;
    localparam PLAY_Y0      = 80;
    localparam PLAY_Y1      = 120;

    localparam EXIT_X0      = 90;
    localparam EXIT_X1      = 230;
    localparam EXIT_Y0      = 140;
    localparam EXIT_Y1      = 180;

    // Derived text-box positions inside buttons (centered 4 chars)
    localparam PLAY_TX0     = (PLAY_X0 + PLAY_X1)/2 - 2*DIGIT_W; // center - 2 chars
    localparam PLAY_TY0     = PLAY_Y0 + ((PLAY_Y1-PLAY_Y0) - DIGIT_H)/2;

    localparam EXIT_TX0     = (EXIT_X0 + EXIT_X1)/2 - 2*DIGIT_W;
    localparam EXIT_TY0     = EXIT_Y0 + ((EXIT_Y1-EXIT_Y0) - DIGIT_H)/2;

    // Colors
    localparam [15:0] COL_BG       = 16'h001F; // legacy blue (used selectively)
    localparam [15:0] COL_SCORE    = 16'hFFFF; // white text
    localparam [15:0] COL_PANEL    = 16'h0841; // unused now (panel removed)
    localparam [15:0] COL_BTN      = 16'hFFFF; // white buttons
    localparam [15:0] COL_FLASH    = 16'hFFFF; // white flash for paddle/bricks

    // --------------------------------------------------------------------
    // 4x7 digit font (28 bits: row-major, top->bottom, left->right)
    // --------------------------------------------------------------------
    function [27:0] digit_font4x7;
        input [3:0] d;
        begin
            case (d)
                4'd0: digit_font4x7 = 28'b1111_1001_1001_1001_1001_1001_1111;
                4'd1: digit_font4x7 = 28'b0010_0110_0010_0010_0010_0010_0111;
                4'd2: digit_font4x7 = 28'b1110_0001_0001_1110_1000_1000_1111;
                4'd3: digit_font4x7 = 28'b1110_0001_0001_1110_0001_0001_1110;
                4'd4: digit_font4x7 = 28'b1001_1001_1001_1111_0001_0001_0001;
                4'd5: digit_font4x7 = 28'b1111_1000_1000_1110_0001_0001_1110;
                4'd6: digit_font4x7 = 28'b1111_1000_1000_1111_1001_1001_1111;
                4'd7: digit_font4x7 = 28'b1111_0001_0001_0001_0001_0001_0001;
                4'd8: digit_font4x7 = 28'b1111_1001_1001_1111_1001_1001_1111;
                4'd9: digit_font4x7 = 28'b1111_1001_1001_1111_0001_0001_1111;
                default: digit_font4x7 = 28'b0000_0000_0000_0000_0000_0000_0000;
            endcase
        end
    endfunction

    // --------------------------------------------------------------------
    // 4x7 letter font for "Score:" (S,C,O,R,E,:) – indices 0..5
    // --------------------------------------------------------------------
    function [27:0] letter_font4x7;
        input [2:0] idx; // 0:S 1:C 2:O 3:R 4:E 5::
        begin
            case (idx)
                3'd0: letter_font4x7 = 28'b1111_1000_1000_1111_0001_0001_1111; // S
                3'd1: letter_font4x7 = 28'b1111_1000_1000_1000_1000_1000_1111; // C
                3'd2: letter_font4x7 = 28'b1111_1001_1001_1001_1001_1001_1111; // O
                3'd3: letter_font4x7 = 28'b1110_1001_1001_1110_1010_1001_1001; // R
                3'd4: letter_font4x7 = 28'b1111_1000_1000_1111_1000_1000_1111; // E
                3'd5: letter_font4x7 = 28'b0000_0010_0010_0000_0010_0010_0000; // :
                default: letter_font4x7 = 28'b0000_0000_0000_0000_0000_0000_0000;
            endcase
        end
    endfunction

    // --------------------------------------------------------------------
    // 4x7 glyphs for UI labels ("PLAY", "QUIT")
    // --------------------------------------------------------------------
    function [27:0] glyph4x7;
        input [3:0] code;
        begin
            case (code)
                4'd0: glyph4x7 = 28'b1110_1001_1001_1110_1000_1000_1000; // P
                4'd1: glyph4x7 = 28'b1000_1000_1000_1000_1000_1000_1111; // L
                4'd2: glyph4x7 = 28'b0110_1001_1001_1111_1001_1001_1001; // A
                4'd3: glyph4x7 = 28'b1001_1001_1001_0110_0010_0010_0010; // Y

                4'd4: glyph4x7 = 28'b1111_1001_1001_1001_1011_1010_0111; // Q
                4'd5: glyph4x7 = 28'b1001_1001_1001_1001_1001_1001_1111; // U
                4'd6: glyph4x7 = 28'b1111_0010_0010_0010_0010_0010_1111; // I
                4'd7: glyph4x7 = 28'b1111_0010_0010_0010_0010_0010_0010; // T

                default: glyph4x7 = 28'b0000_0000_0000_0000_0000_0000_0000;
            endcase
        end
    endfunction

    // --------------------------------------------------------------------
    // Physical X/Y pixel counters driven by framebufferClk
    // --------------------------------------------------------------------
    reg [8:0] x;       // 0..239 (physical)
    reg [8:0] y;       // 0..319 (physical)
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

    // Rotate to game coordinates
    wire [8:0] game_x = y;                 // 0..319 (horizontal)
    wire [8:0] game_y = LCD_W - 1 - x;     // 0..239 (vertical)

    // --------------------------------------------------------------------
    // Gradient background (computed per-pixel)
    // --------------------------------------------------------------------
    function [15:0] gradient_color;
        input [8:0] gy;
        reg [4:0] b;
        reg [5:0] g;
    begin
        // Simple dark-blue -> teal-ish vertical gradient
        g = 6'd8  + (gy[7:2] >> 1);   // modest green increase
        b = 5'd10 + (gy[7:3] >> 1);   // modest blue increase
        gradient_color = {5'd0, g, b};
    end
    endfunction

    // --------------------------------------------------------------------
    // Paddle hit flash
    // --------------------------------------------------------------------
    reg [3:0] paddle_flash_cnt;
    reg       paddle_overlap_d;

    wire [8:0] ball_center_x = ball_x_pix + BALL_SIZE/2;
    wire [8:0] ball_bottom_y = ball_y_pix + BALL_SIZE;

    wire [8:0] paddle_left  = paddle_x_center - (PADDLE_W/2);
    wire [8:0] paddle_right = paddle_x_center + (PADDLE_W/2);

    wire paddle_overlap_now =
        (ball_center_x >= paddle_left) &&
        (ball_center_x <  paddle_right) &&
        (ball_bottom_y  >= PADDLE_Y) &&
        (ball_y_pix     <  (PADDLE_Y + PADDLE_H));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            paddle_flash_cnt <= 4'd0;
            paddle_overlap_d <= 1'b0;
        end else begin
            paddle_overlap_d <= paddle_overlap_now;

            // Start flash on rising edge of overlap
            if (paddle_overlap_now && !paddle_overlap_d) begin
                paddle_flash_cnt <= 4'd8;   // ~8 frames
            end else if (paddle_flash_cnt != 4'd0) begin
                paddle_flash_cnt <= paddle_flash_cnt - 4'd1;
            end
        end
    end

    // --------------------------------------------------------------------
    // Brick destroy flash: track which bricks just disappeared
    // --------------------------------------------------------------------
    reg [47:0] bricks_prev;
    reg [47:0] bricks_flash_mask;
    reg [3:0]  bricks_flash_cnt;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bricks_prev       <= 48'h0;
            bricks_flash_mask <= 48'h0;
            bricks_flash_cnt  <= 4'd0;
        end else begin
            // new_destroyed = prev & ~current
            if (bricks_prev != bricks_alive) begin
                bricks_flash_mask <= bricks_prev & ~bricks_alive;
                if ((bricks_prev & ~bricks_alive) != 48'h0)
                    bricks_flash_cnt <= 4'd6;  // short flash
            end else if (bricks_flash_cnt != 4'd0) begin
                bricks_flash_cnt <= bricks_flash_cnt - 4'd1;
            end

            bricks_prev <= bricks_alive;
        end
    end

    // --------------------------------------------------------------------
    // Shared HUD / UI variables
    // --------------------------------------------------------------------
    integer sc;
    integer d0, d1, d2;
    reg [27:0] font0, font1, font2;
    integer local_x, local_y;
    integer digit_sel, bit_idx;
    integer digit_x;   // local X within a single digit (ignoring spacing)

    reg [27:0] label_font;
    integer label_char;
    integer lx, ly;
    integer label_bit_idx;

    integer tx, ty;
    integer char_idx;
    integer glyph_bit_idx;
    reg [27:0] glyph;

    // font-space coordinates (0..3,0..6)
    integer font_x, font_y;

    // --------------------------------------------------------------------
    // Sprite ROMs
    // --------------------------------------------------------------------
    localparam BRICK_PIXELS  = SPR_BRICK_W  * SPR_BRICK_H;  // 32*9 = 288
    localparam PADDLE_PIXELS = SPR_PADDLE_W * SPR_PADDLE_H; // 32*9 = 288
    localparam BALL_PIXELS   = SPR_BALL_W   * SPR_BALL_H;   // 8*8  = 64

    (* romstyle = "M9K", ramstyle = "M9K", ram_init_file = "brick_green_reduced.hex" *)
    reg [15:0] brick_mem  [0:BRICK_PIXELS-1];

    (* romstyle = "M9K", ramstyle = "M9K", ram_init_file = "paddle_yellow_reduced.hex" *)
    reg [15:0] paddle_mem [0:PADDLE_PIXELS-1];

    (* romstyle = "M9K", ramstyle = "M9K", ram_init_file = "ball_yellow_reduced.hex" *)
    reg [15:0] ball_mem   [0:BALL_PIXELS-1];

    initial begin
        $readmemh("brick_green_reduced.hex",   brick_mem);
        $readmemh("paddle_yellow_reduced.hex", paddle_mem);
        $readmemh("ball_yellow_reduced.hex",   ball_mem);
    end

    // --------------------------------------------------------------------
    // Main combinational renderer
    // --------------------------------------------------------------------
    integer r, c, idx;

    reg in_brick;
    reg in_paddle;
    reg in_ball;
    reg in_score_digit;
    reg in_score_label;
    reg in_go_panel;
    reg in_play_btn;
    reg in_exit_btn;
    reg in_play_text;
    reg in_exit_text;

    integer brick_u, brick_v;
    integer brick_addr_int;
    reg [15:0] brick_color;

    integer paddle_u, paddle_v;
    integer pad_addr_int;
    reg [15:0] paddle_color;

    integer ball_u, ball_v;
    integer ball_addr_int;
    reg [15:0] ball_color;

    always @* begin
        // defaults for flags
        in_brick        = 1'b0;
        in_paddle       = 1'b0;
        in_ball         = 1'b0;
        in_score_digit  = 1'b0;
        in_score_label  = 1'b0;
        in_go_panel     = 1'b0;
        in_play_btn     = 1'b0;
        in_exit_btn     = 1'b0;
        in_play_text    = 1'b0;
        in_exit_text    = 1'b0;

        brick_color     = 16'h0000;
        paddle_color    = 16'h0000;
        ball_color      = 16'h0000;

        brick_u        = 0;
        brick_v        = 0;
        brick_addr_int = 0;

        paddle_u       = 0;
        paddle_v       = 0;
        pad_addr_int   = 0;

        ball_u         = 0;
        ball_v         = 0;
        ball_addr_int  = 0;

        font_x         = 0;
        font_y         = 0;

        // Start from gradient background
        //pixel_color = gradient_color(game_y);
		pixel_color = 16'h001F;

        // ------------------------------ Score digits (8x14 on screen) ----
        sc = score;
        d0 = sc % 10; sc = sc / 10;
        d1 = sc % 10; sc = sc / 10;
        d2 = sc % 10;

        font0 = digit_font4x7(d2[3:0]);
        font1 = digit_font4x7(d1[3:0]);
        font2 = digit_font4x7(d0[3:0]);

        if ( (game_y >= SCORE_Y0) && (game_y < SCORE_Y0 + DIGIT_H) &&
             (game_x >= SCORE_X0) && (game_x < SCORE_X0 + SCORE_TOTAL_W) ) begin

            local_x = game_x - SCORE_X0;
            local_y = game_y - SCORE_Y0;

            // Decide which digit (0,1,2) or gap region
            digit_sel = -1;
            digit_x   = 0;

            if (local_x < DIGIT_W) begin
                // leftmost digit
                digit_sel = 0;
                digit_x   = local_x;
            end else if (local_x < DIGIT_W + DIGIT_SPACING) begin
                // gap between digit 0 and 1
                digit_sel = -1;
            end else if (local_x < DIGIT_W + DIGIT_SPACING + DIGIT_W) begin
                // middle digit
                digit_sel = 1;
                digit_x   = local_x - (DIGIT_W + DIGIT_SPACING);
            end else if (local_x < 2*DIGIT_W + 2*DIGIT_SPACING) begin
                // gap between digit 1 and 2
                digit_sel = -1;
            end else begin
                // rightmost digit
                digit_sel = 2;
                digit_x   = local_x - (2*DIGIT_W + 2*DIGIT_SPACING);
            end

            if (digit_sel >= 0) begin
                // scale 2x: map screen coords -> font coords
                font_x = digit_x >> 1;   // /2
                font_y = local_y >> 1;

                if (font_x < FONT_W && font_y < FONT_H) begin
                    bit_idx = font_y*FONT_W + font_x;
                    case (digit_sel)
                        0: in_score_digit = font0[27-bit_idx];
                        1: in_score_digit = font1[27-bit_idx];
                        2: in_score_digit = font2[27-bit_idx];
                        default: in_score_digit = 1'b0;
                    endcase
                end
            end
        end

        // ------------------------------ "Score:" label (8x14 per char) ---
        if ( (game_y >= LABEL_Y0) && (game_y < LABEL_Y0 + DIGIT_H) &&
             (game_x >= LABEL_X0) && (game_x < LABEL_X0 + LABEL_LEN*DIGIT_W) ) begin

            lx = game_x - LABEL_X0;
            ly = game_y - LABEL_Y0;

            label_char = lx / DIGIT_W; // which character
            lx         = lx % DIGIT_W;

            // scale 2x
            font_x = lx >> 1;
            font_y = ly >> 1;

            if (font_x < FONT_W && font_y < FONT_H) begin
                label_font    = letter_font4x7(label_char[2:0]);
                label_bit_idx = font_y*FONT_W + font_x;
                in_score_label = label_font[27-label_bit_idx];
            end
        end

        // ------------------------------ Game Over UI ----------------------
        if (game_over) begin
            // (panel region unused visually)
            if ( (game_x >= GO_PANEL_X0) && (game_x < GO_PANEL_X0 + GO_PANEL_W) &&
                 (game_y >= GO_PANEL_Y0) && (game_y < GO_PANEL_Y0 + GO_PANEL_H) )
                in_go_panel = 1'b1;

            if ( (game_x >= PLAY_X0) && (game_x < PLAY_X1) &&
                 (game_y >= PLAY_Y0) && (game_y < PLAY_Y1) )
                in_play_btn = 1'b1;

            if ( (game_x >= EXIT_X0) && (game_x < EXIT_X1) &&
                 (game_y >= EXIT_Y0) && (game_y < EXIT_Y1) )
                in_exit_btn = 1'b1;

            // "PLAY" text
            if ( (game_x >= PLAY_TX0) && (game_x < PLAY_TX0 + 4*DIGIT_W) &&
                 (game_y >= PLAY_TY0) && (game_y < PLAY_TY0 + DIGIT_H) ) begin
                tx = game_x - PLAY_TX0;
                ty = game_y - PLAY_TY0;

                char_idx = tx / DIGIT_W;
                tx       = tx % DIGIT_W;

                case (char_idx)
                    0: glyph = glyph4x7(4'd0); // P
                    1: glyph = glyph4x7(4'd1); // L
                    2: glyph = glyph4x7(4'd2); // A
                    3: glyph = glyph4x7(4'd3); // Y
                    default: glyph = 28'b0;
                endcase

                // 2x scaling
                font_x = tx >> 1;
                font_y = ty >> 1;

                if (font_x < FONT_W && font_y < FONT_H) begin
                    glyph_bit_idx = font_y*FONT_W + font_x;
                    if (glyph[27-glyph_bit_idx])
                        in_play_text = 1'b1;
                end
            end

            // "QUIT" text
            if ( (game_x >= EXIT_TX0) && (game_x < EXIT_TX0 + 4*DIGIT_W) &&
                 (game_y >= EXIT_TY0) && (game_y < EXIT_TY0 + DIGIT_H) ) begin
                tx = game_x - EXIT_TX0;
                ty = game_y - EXIT_TY0;

                char_idx = tx / DIGIT_W;
                tx       = tx % DIGIT_W;

                case (char_idx)
                    0: glyph = glyph4x7(4'd4); // Q
                    1: glyph = glyph4x7(4'd5); // U
                    2: glyph = glyph4x7(4'd6); // I
                    3: glyph = glyph4x7(4'd7); // T
                    default: glyph = 28'b0;
                endcase

                // 2x scaling
                font_x = tx >> 1;
                font_y = ty >> 1;

                if (font_x < FONT_W && font_y < FONT_H) begin
                    glyph_bit_idx = font_y*FONT_W + font_x;
                    if (glyph[27-glyph_bit_idx])
                        in_exit_text = 1'b1;
                end
            end
        end

        // ------------------------------ Gameplay with sprites ------------
        if (!game_over) begin
            // Bricks (with destroy flash)
            for (r = 0; r < BRICK_ROWS; r = r + 1) begin
                for (c = 0; c < BRICK_COLS; c = c + 1) begin
                    idx = r*BRICK_COLS + c;

                    if ( (game_x >= BRICK_X0 + c*(BRICK_W + BRICK_X_SP)) &&
                         (game_x <  BRICK_X0 + c*(BRICK_W + BRICK_X_SP) + BRICK_W) &&
                         (game_y >= BRICK_Y0 + r*(BRICK_H + BRICK_Y_SP)) &&
                         (game_y <  BRICK_Y0 + r*(BRICK_H + BRICK_Y_SP) + BRICK_H) ) begin

                        in_brick = 1'b1;

                        if (bricks_alive[idx]) begin
                            // Normal brick sprite
                            brick_u = game_x - (BRICK_X0 + c*(BRICK_W + BRICK_X_SP));
                            brick_v = game_y - (BRICK_Y0 + r*(BRICK_H + BRICK_Y_SP));

                            brick_addr_int = brick_v*SPR_BRICK_W + brick_u;
                            brick_color    = brick_mem[brick_addr_int];
                        end
                        else if ((bricks_flash_cnt != 4'd0) &&
                                 (bricks_flash_mask[idx])) begin
                            // Brick just destroyed: show flash ghost
                            brick_color = COL_FLASH;
                        end
                        else begin
                            // No brick & no ghost
                            brick_color = 16'h0000;
                        end
                    end
                end
            end

            // Paddle
            if ( (game_y >= PADDLE_Y) && (game_y < PADDLE_Y + PADDLE_H) &&
                 (game_x >= paddle_left) &&
                 (game_x <  paddle_right) ) begin
                in_paddle = 1'b1;

                paddle_u = game_x - paddle_left;
                paddle_v = game_y - PADDLE_Y;

                pad_addr_int = paddle_v*SPR_PADDLE_W + paddle_u;
                paddle_color = paddle_mem[pad_addr_int];
            end

            // Ball
            if ( (game_x >= ball_x_pix) &&
                 (game_x <  ball_x_pix + BALL_SIZE) &&
                 (game_y >= ball_y_pix) &&
                 (game_y <  ball_y_pix + BALL_SIZE) ) begin
                in_ball = 1'b1;

                ball_u = game_x - ball_x_pix;
                ball_v = game_y - ball_y_pix;

                ball_addr_int = ball_v*SPR_BALL_W + ball_u;
                ball_color    = ball_mem[ball_addr_int];
            end
        end

        // ------------------------------ Final color ----------------------
        // Background already set to gradient_color(game_y).

        // HUD text (score + label) on top of background
        if (in_score_label || in_score_digit)
            pixel_color = COL_SCORE;

        if (!game_over) begin
            // Treat 0x0000 as transparent in sprites
            if (in_brick   && (brick_color  != 16'h0000)) pixel_color = brick_color;

            if (in_paddle  && (paddle_color != 16'h0000)) begin
                if (paddle_flash_cnt != 4'd0)
                    pixel_color = COL_FLASH;  // flash paddle on hit
                else
                    pixel_color = paddle_color;
            end

            if (in_ball    && (ball_color   != 16'h0000)) pixel_color = ball_color;
        end else begin
            // Game Over: white buttons with cut-out text showing gradient
            if (in_play_btn || in_exit_btn)
                pixel_color = COL_BTN;   // white buttons

            if (in_play_text || in_exit_text)
                pixel_color = gradient_color(game_y);  // text "cut out" to background
        end
    end

endmodule
