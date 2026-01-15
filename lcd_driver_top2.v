// LCD_driver_top.v
// DE10-Lite + ILI9341 + FT6336 touch + Breakout game +
// home screen with Breakout app icon + Game Over UI.

`timescale 1ns/1ps

module LCD_driver_top2 (
    input  wire clk_50,      // 50 MHz DE10-Lite clock
    input  wire reset_n,     // active-low reset (KEY0)

    // LCD pins
    output wire lcd_cs,      // TFT CS  (active low)
    output wire lcd_rst,     // TFT RESET
    output wire lcd_rs,      // TFT D/C (RS)
    output wire lcd_sck,     // TFT SCK
    output wire lcd_mosi,    // TFT MOSI / SDI

    // Backlight / SD / debug
    output wire bl_pwm,      // Backlight PWM/enable
    output wire sd_cs,       // SD card CS (keep disabled)
    output wire debug_led,   // tie to LEDR0 for a heartbeat

    // Extra LEDs for debug
    output wire [3:0] led_touch_y,   // map to LEDR[3:0]
    output wire [3:0] led_paddle_x,  // map to LEDR[7:4]

    // Touch panel pins (FT6336G)
    output wire CTP_SCL,
    inout  wire CTP_SDA,
    output wire CTP_RST,
    input  wire CTP_INT      // from panel
);

    // --------------------------------------------------------------------
    // Game & UI geometry constants
    // --------------------------------------------------------------------
    localparam integer GAME_W = 320;
    localparam integer GAME_H = 240;

    // Home icon geometry (must match home_renderer)
    localparam integer ICON_W        = 48;
    localparam integer ICON_H        = 48;
    localparam integer ICON_MARGIN_X = 16;
    localparam integer ICON_MARGIN_Y = 16;
    localparam integer ICON_X0       = GAME_W - ICON_W - ICON_MARGIN_X; // 256
    localparam integer ICON_Y0       = ICON_MARGIN_Y;                   // 16

    // Game Over buttons (must match breakout_renderer)
    localparam [8:0] PLAY_X0  = 9'd90;
    localparam [8:0] PLAY_X1  = 9'd230;
    localparam [8:0] PLAY_Y0  = 9'd80;
    localparam [8:0] PLAY_Y1  = 9'd120;

    localparam [8:0] EXIT_X0  = 9'd90;
    localparam [8:0] EXIT_X1  = 9'd230;
    localparam [8:0] EXIT_Y0  = 9'd140;
    localparam [8:0] EXIT_Y1  = 9'd180;

    // --------------------------------------------------------------------
    // Backlight + SD card chip select
    // --------------------------------------------------------------------
    assign bl_pwm = 1'b1;   // backlight ON
    assign sd_cs  = 1'b1;   // SD chip-select inactive (HIGH)

    // --------------------------------------------------------------------
    // TFT driver instantiation
    // --------------------------------------------------------------------
    reg  [15:0] fb_data_reg;
    wire [15:0] fb_data      = fb_data_reg;
    wire        framebufferClk;

    tft_ili9341 #(
        .INPUT_CLK_MHZ(50)          // DE10-Lite uses 50 MHz clock
    ) tft_inst (
        .clk            (clk_50),
        .reset_n        (reset_n),  // reset driver + LCD from KEY0
        .tft_sdo        (1'b0),     // not reading from LCD
        .tft_sck        (lcd_sck),
        .tft_sdi        (lcd_mosi),
        .tft_dc         (lcd_rs),
        .tft_reset      (lcd_rst),
        .tft_cs         (lcd_cs),
        .framebufferData(fb_data),
        .framebufferClk (framebufferClk)
    );

    // --------------------------------------------------------------------
    // Touch controller (FT6336G polling version)
    // --------------------------------------------------------------------
    wire        touch_valid;
    wire        touch_down;
    wire [11:0] touch_x;
    wire [11:0] touch_y;

    ft6336_touch #(
        .CLK_FREQ_HZ(50_000_000),
        .I2C_FREQ_HZ(100_000),
        .POLL_HZ    (200)            // ~200 samples/sec
    ) touch_inst (
        .clk        (clk_50),
        .reset_n    (reset_n),
        .CTP_SCL    (CTP_SCL),
        .CTP_SDA    (CTP_SDA),
        .CTP_RST    (CTP_RST),
        .CTP_INT    (CTP_INT),       // unused for polling
        .touch_valid(touch_valid),
        .touch_down (touch_down),
        .touch_x    (touch_x),
        .touch_y    (touch_y)
    );

    // Debug: show top bits of touch_y (coarse game X) on LEDs
    assign led_touch_y = touch_y[11:8];

    // --------------------------------------------------------------------
    // Map touch coordinates -> GAME coordinates (rotation-aware)
    // --------------------------------------------------------------------
    // Horizontal game X comes from panel Y (touch_y), clamped
    wire [8:0] game_touch_x_raw = touch_y[8:0];
    wire [8:0] game_touch_x =
        (game_touch_x_raw > (GAME_W-1)) ? (GAME_W-1) : game_touch_x_raw;

    // Vertical game Y from touch_x, inverted (since screen is rotated)
    wire [7:0] touch_x_clamped =
        (touch_x[7:0] > 8'd239) ? 8'd239 : touch_x[7:0];
    wire [8:0] game_touch_y = 9'd239 - {1'b0, touch_x_clamped};

    // --------------------------------------------------------------------
    // Edge detect on touch_down so home screen only reacts to a new tap
    // --------------------------------------------------------------------
    reg touch_down_d;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            touch_down_d <= 1'b0;
        else
            touch_down_d <= touch_down;
    end

    wire touch_rise = touch_down && !touch_down_d;

    // --------------------------------------------------------------------
    // Home screen renderer (Breakout icon)
    // --------------------------------------------------------------------
    wire [15:0] home_pixel;

    home_renderer #(
        .GAME_W(GAME_W),
        .GAME_H(GAME_H)
    ) home_inst (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .pixel_color   (home_pixel)
    );

    // --------------------------------------------------------------------
    // Game state machine
    // --------------------------------------------------------------------
    localparam [1:0]
        S_IDLE      = 2'd0,   // home screen + icon
        S_PLAY      = 2'd1,
        S_GAME_OVER = 2'd2;

    reg [1:0] game_state;

    // Control signals to breakout_game
    reg       game_run;
    reg       new_game;
    wire      ball_lost;
    wire      game_over = (game_state == S_GAME_OVER);

    // Paddle control from touch
    reg  [8:0] paddle_target_x;
    wire [3:0] paddle_x_nibble;

    // Update paddle_target_x only while playing and we have new touch data
    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            paddle_target_x <= 9'd160; // center
        end else begin
            if ((game_state == S_PLAY) && touch_valid && touch_down) begin
                if (game_touch_x > (GAME_W-1))
                    paddle_target_x <= GAME_W-1;
                else
                    paddle_target_x <= game_touch_x;
            end
        end
    end

    assign paddle_x_nibble = paddle_target_x[8:5];
    assign led_paddle_x    = paddle_x_nibble;
	
	// add extra hitbox for the icons (qol)
	localparam integer ICON_HIT_MARGIN = 4;


    // Game state + new_game + game_run
    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            game_state <= S_IDLE;
            game_run   <= 1'b0;
            new_game   <= 1'b0;
        end else begin
            // default: no new_game pulse
            new_game <= 1'b0;

            case (game_state)
                // ---------------------------------------------------------
                // HOME SCREEN (icon) - S_IDLE
                // ---------------------------------------------------------
                S_IDLE: begin
                    game_run <= 1'b0;

                    // Start game only on NEW touch (rising edge) AND inside icon
                    if (touch_rise && touch_valid) begin
                        if ( (game_touch_x >= ICON_X0 - ICON_HIT_MARGIN) &&
                             (game_touch_x <  ICON_X0 + ICON_W + ICON_HIT_MARGIN) &&
                             (game_touch_y >= ICON_Y0 - ICON_HIT_MARGIN) &&
                             (game_touch_y <  ICON_Y0 + ICON_H + ICON_HIT_MARGIN) ) begin
                            game_state <= S_PLAY;
                            game_run   <= 1'b1;
                            new_game   <= 1'b1;   // reset game state
                        end
                    end
                end

                // ---------------------------------------------------------
                // PLAYING
                // ---------------------------------------------------------
                S_PLAY: begin
                    game_run <= 1'b1;
                    if (ball_lost) begin
                        game_state <= S_GAME_OVER;
                        game_run   <= 1'b0;   // freeze game
                    end
                end

                // ---------------------------------------------------------
                // GAME OVER UI: play again / quit buttons
                // ---------------------------------------------------------
                S_GAME_OVER: begin
                    game_run <= 1'b0;
                    if (touch_valid && touch_down) begin
                        // Play Again button
                        if ( (game_touch_x >= PLAY_X0) &&
                             (game_touch_x <  PLAY_X1) &&
                             (game_touch_y >= PLAY_Y0) &&
                             (game_touch_y <  PLAY_Y1) ) begin
                            game_state <= S_PLAY;
                            game_run   <= 1'b1;
                            new_game   <= 1'b1;
                        end
                        // Quit button -> back to home icon
                        else if ( (game_touch_x >= EXIT_X0) &&
                                  (game_touch_x <  EXIT_X1) &&
                                  (game_touch_y >= EXIT_Y0) &&
                                  (game_touch_y <  EXIT_Y1) ) begin
                            game_state <= S_IDLE;
                            game_run   <= 1'b0;
                        end
                    end
                end

                default: begin
                    game_state <= S_IDLE;
                    game_run   <= 1'b0;
                    new_game   <= 1'b0;
                end
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Breakout game logic
    // --------------------------------------------------------------------
    wire [8:0]  paddle_x_game;
    wire [8:0]  ball_x_game;
    wire [8:0]  ball_y_game;
    wire [47:0] bricks_alive_game;
    wire [9:0]  score_game;

    breakout_game #(
        .CLK_FREQ_HZ(50_000_000),
        .GAME_W     (GAME_W),
        .GAME_H     (GAME_H)
    ) game_inst (
        .clk            (clk_50),
        .reset_n        (reset_n),
        .game_run       (game_run),
        .new_game       (new_game),
        .paddle_target_x(paddle_target_x),
        .paddle_x       (paddle_x_game),
        .ball_x_pix     (ball_x_game),
        .ball_y_pix     (ball_y_game),
        .bricks_alive   (bricks_alive_game),
        .score          (score_game),
        .ball_lost      (ball_lost)
    );

    // --------------------------------------------------------------------
    // Breakout scene renderer
    // --------------------------------------------------------------------
    wire [15:0] scene_pixel;

    breakout_renderer scene_inst (
        .clk             (clk_50),
        .reset_n         (reset_n),
        .framebufferClk  (framebufferClk),

        .paddle_x_center (paddle_x_game),
        .ball_x_pix      (ball_x_game),
        .ball_y_pix      (ball_y_game),

        .bricks_alive    (bricks_alive_game),
        .score           (score_game),

        .game_over       (game_over),

        .pixel_color     (scene_pixel)
    );

    // --------------------------------------------------------------------
    // Framebuffer data mux:
    //  - S_IDLE      => home icon
    //  - S_PLAY/GO   => breakout scene pixels
    // --------------------------------------------------------------------
    always @* begin
        case (game_state)
            S_IDLE:       fb_data_reg = home_pixel;   // home screen with icon
            S_PLAY,
            S_GAME_OVER:  fb_data_reg = scene_pixel;  // game + endgame UI
            default:      fb_data_reg = 16'h0000;     // safety
        endcase
    end

    // --------------------------------------------------------------------
    // Simple heartbeat LED so you know the top is running
    // --------------------------------------------------------------------
    reg [23:0] blink_cnt;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            blink_cnt <= 24'd0;
        else
            blink_cnt <= blink_cnt + 24'd1;
    end

    assign debug_led = blink_cnt[23]; // ~3 Hz blink at 50 MHz

endmodule
