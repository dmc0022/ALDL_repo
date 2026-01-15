// LCD_driver_top.v
// DE10-Lite + ILI9341 + FT6336 touch +
//   - Global app FSM: HOME / BREAKOUT / GIF
//   - Home screen with Breakout icon and GIF icon ("CPE 431")
//   - Breakout game with Game Over UI
//   - GIF app skeleton with Home button + GIF placeholder box

`timescale 1ns/1ps

module LCD_driver_top (
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

    // Breakout home icon geometry (must match home_renderer)
    localparam integer ICON_W        = 48;
    localparam integer ICON_H        = 48;
    localparam integer ICON_MARGIN_X = 16;
    localparam integer ICON_MARGIN_Y = 16;
    localparam integer ICON_X0       = GAME_W - ICON_W - ICON_MARGIN_X; // 256
    localparam integer ICON_Y0       = ICON_MARGIN_Y;                   // 16

    // GIF home icon geometry (left side on HOME SCREEN)
    localparam integer GIF_ICON_W   = ICON_W;
    localparam integer GIF_ICON_H   = ICON_H;
    localparam integer GIF_ICON_X0  = ICON_MARGIN_X;   // 16
    localparam integer GIF_ICON_Y0  = ICON_MARGIN_Y;   // 16

    // Game Over buttons (must match breakout_renderer)
    localparam [8:0] PLAY_X0  = 9'd90;
    localparam [8:0] PLAY_X1  = 9'd230;
    localparam [8:0] PLAY_Y0  = 9'd80;
    localparam [8:0] PLAY_Y1  = 9'd120;

    localparam [8:0] EXIT_X0  = 9'd90;
    localparam [8:0] EXIT_X1  = 9'd230;
    localparam [8:0] EXIT_Y0  = 9'd140;
    localparam [8:0] EXIT_Y1  = 9'd180;

    // GIF app Home button (TOP-CENTER, must match gif_renderer)
    // Button size ~80x30, centered horizontally
    localparam [8:0] GIF_HOME_X0 = 9'd120;  // (320 - 80)/2
    localparam [8:0] GIF_HOME_X1 = 9'd200;  // 80 px wide
    localparam [8:0] GIF_HOME_Y0 = 9'd10;
    localparam [8:0] GIF_HOME_Y1 = 9'd40;

    // --------------------------------------------------------------------
    // App-level FSM: HOME / BREAKOUT / GIF
    // --------------------------------------------------------------------
    localparam [1:0]
        APP_HOME     = 2'd0,
        APP_BREAKOUT = 2'd1,
        APP_GIF      = 2'd2;

    reg [1:0] app_state;

    // Breakout sub-FSM (inside APP_BREAKOUT)
    localparam [1:0]
        B_IDLE      = 2'd0,
        B_PLAY      = 2'd1,
        B_GAME_OVER = 2'd2;

    reg [1:0] b_state;

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
    // Edge detect on touch_down so screens react only to taps
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
    // HOMESCREEN + GIF + GAME OVER hitboxes (in GAME coordinates)
    // --------------------------------------------------------------------
    localparam integer ICON_HIT_MARGIN = 4;

    // home-screen icons
    wire in_breakout_icon = 
        (game_touch_x >= ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  ICON_X0 + ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  ICON_Y0 + ICON_H + ICON_HIT_MARGIN);

    wire in_gif_icon =
        (game_touch_x >= GIF_ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  GIF_ICON_X0 + GIF_ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= GIF_ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  GIF_ICON_Y0 + GIF_ICON_H + ICON_HIT_MARGIN);

    // GIF app "Home" button (TOP-CENTER)
    wire in_gif_home_btn =
        (game_touch_x >= GIF_HOME_X0) &&
        (game_touch_x <  GIF_HOME_X1) &&
        (game_touch_y >= GIF_HOME_Y0) &&
        (game_touch_y <  GIF_HOME_Y1);

    // Game Over PLAY / QUIT buttons
    wire in_play_btn =
        (game_touch_x >= PLAY_X0) &&
        (game_touch_x <  PLAY_X1) &&
        (game_touch_y >= PLAY_Y0) &&
        (game_touch_y <  PLAY_Y1);

    wire in_quit_btn =
        (game_touch_x >= EXIT_X0) &&
        (game_touch_x <  EXIT_X1) &&
        (game_touch_y >= EXIT_Y0) &&
        (game_touch_y <  EXIT_Y1);

    // edge-based taps
    wire tap_breakout_icon = touch_rise && touch_valid && in_breakout_icon;
    wire tap_gif_icon      = touch_rise && touch_valid && in_gif_icon;
    wire tap_gif_home      = touch_rise && touch_valid && in_gif_home_btn;
    wire tap_play_again    = touch_rise && touch_valid && in_play_btn;
    wire tap_quit          = touch_rise && touch_valid && in_quit_btn;

    // --------------------------------------------------------------------
    // Paddle control from touch (only when Breakout is playing)
    // --------------------------------------------------------------------
    reg  [8:0] paddle_target_x;
    wire [3:0] paddle_x_nibble;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            paddle_target_x <= 9'd160; // center
        end else begin
            if ((app_state == APP_BREAKOUT) &&
                (b_state   == B_PLAY) &&
                touch_valid && touch_down) begin
                if (game_touch_x > (GAME_W-1))
                    paddle_target_x <= GAME_W-1;
                else
                    paddle_target_x <= game_touch_x;
            end
        end
    end

    assign paddle_x_nibble = paddle_target_x[8:5];
    assign led_paddle_x    = paddle_x_nibble;

    // --------------------------------------------------------------------
    // Breakout game control signals
    // --------------------------------------------------------------------
    reg       game_run;
    reg       new_game;
    wire      ball_lost;
    wire      breakout_game_over = (b_state == B_GAME_OVER);

    // --------------------------------------------------------------------
    // App + Breakout sub-FSM
    // --------------------------------------------------------------------
    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            app_state   <= APP_HOME;
            b_state     <= B_IDLE;
            game_run    <= 1'b0;
            new_game    <= 1'b0;
        end else begin
            // default: no new_game pulse
            new_game <= 1'b0;

            case (app_state)
                // ---------------------------------------------------------
                // GLOBAL HOME SCREEN (two icons)
                // ---------------------------------------------------------
                APP_HOME: begin
                    game_run <= 1'b0;
                    b_state  <= B_IDLE;

                    if (tap_breakout_icon) begin
                        app_state <= APP_BREAKOUT;
                        b_state   <= B_PLAY;
                        game_run  <= 1'b1;
                        new_game  <= 1'b1;  // reset Breakout
                    end else if (tap_gif_icon) begin
                        app_state <= APP_GIF;
                    end
                end

                // ---------------------------------------------------------
                // BREAKOUT APP
                // ---------------------------------------------------------
                APP_BREAKOUT: begin
                    case (b_state)
                        B_IDLE: begin
                            game_run <= 1'b0;
                        end

                        B_PLAY: begin
                            game_run <= 1'b1;
                            if (ball_lost) begin
                                b_state  <= B_GAME_OVER;
                                game_run <= 1'b0;
                            end
                        end

                        B_GAME_OVER: begin
                            game_run <= 1'b0;

                            // Use edge-based taps so holding a touch
                            // when the ball is lost does NOT auto-select.
                            if (tap_play_again) begin
                                b_state  <= B_PLAY;
                                game_run <= 1'b1;
                                new_game <= 1'b1;
                            end else if (tap_quit) begin
                                app_state <= APP_HOME;
                                b_state   <= B_IDLE;
                                game_run  <= 1'b0;
                            end
                        end

                        default: begin
                            b_state  <= B_IDLE;
                            game_run <= 1'b0;
                        end
                    endcase
                end

                // ---------------------------------------------------------
                // GIF APP
                // ---------------------------------------------------------
                APP_GIF: begin
                    game_run <= 1'b0; // pause Breakout

                    if (tap_gif_home) begin
                        app_state <= APP_HOME;
                        b_state   <= B_IDLE;
                    end
                end

                default: begin
                    app_state <= APP_HOME;
                    b_state   <= B_IDLE;
                    game_run  <= 1'b0;
                    new_game  <= 1'b0;
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
    // Renderers
    // --------------------------------------------------------------------
    wire [15:0] home_pixel;
    wire [15:0] scene_pixel;
    wire [15:0] gif_pixel;

    home_renderer #(
        .GAME_W(GAME_W),
        .GAME_H(GAME_H)
    ) home_inst (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .pixel_color   (home_pixel)
    );

    breakout_renderer scene_inst (
        .clk             (clk_50),
        .reset_n         (reset_n),
        .framebufferClk  (framebufferClk),

        .paddle_x_center (paddle_x_game),
        .ball_x_pix      (ball_x_game),
        .ball_y_pix      (ball_y_game),

        .bricks_alive    (bricks_alive_game),
        .score           (score_game),

        .game_over       (breakout_game_over),

        .pixel_color     (scene_pixel)
    );

    gif_renderer #(
        .GAME_W(GAME_W),
        .GAME_H(GAME_H)
    ) gif_inst (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .pixel_color   (gif_pixel)
    );

    // --------------------------------------------------------------------
    // Framebuffer data mux:
    //  - APP_HOME     => home screen (icons)
    //  - APP_BREAKOUT => breakout scene pixels
    //  - APP_GIF      => GIF app skeleton
    // --------------------------------------------------------------------
    always @* begin
        case (app_state)
            APP_HOME:     fb_data_reg = home_pixel;
            APP_BREAKOUT: fb_data_reg = scene_pixel;
            APP_GIF:      fb_data_reg = gif_pixel;
            default:      fb_data_reg = 16'h0000;
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
