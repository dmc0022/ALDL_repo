`timescale 1ns/1ps
`default_nettype none

module LCD_driver_core_shared_touch (
    input  wire        clk_50,
    input  wire        reset_n,

    // LCD pins
    output wire        lcd_cs,
    output wire        lcd_rst,
    output wire        lcd_rs,
    output wire        lcd_sck,
    output wire        lcd_mosi,

    // Backlight / SD / debug
    output wire        bl_pwm,
    output wire        sd_cs,
    output wire        debug_led,

    // Extra LEDs for debug
    output wire [3:0]  led_touch_y,
    output wire [3:0]  led_paddle_x,

    // 7-seg display
    output wire [6:0]  HEX0,

    // Shared-touch inputs from i2c_touch_hub
    input  wire        touch_valid,
    input  wire        touch_down,
    input  wire [11:0] touch_x,
    input  wire [11:0] touch_y,

    // TMP117 temperature inputs
    input  wire               temp_valid_in,
    input  wire               temp_sensor_present,
    input  wire signed [15:0] temp_centi_c_in
);

    localparam integer GAME_W = 320;
    localparam integer GAME_H = 240;

    localparam integer ICON_W        = 48;
    localparam integer ICON_H        = 48;
    localparam integer ICON_MARGIN_X = 16;
    localparam integer ICON_MARGIN_Y = 16;

    localparam integer ICON_X0 = GAME_W - ICON_W - ICON_MARGIN_X;
    localparam integer ICON_Y0 = ICON_MARGIN_Y;

    localparam integer GIF_ICON_W  = ICON_W;
    localparam integer GIF_ICON_H  = ICON_H;
    localparam integer GIF_ICON_X0 = ICON_MARGIN_X;
    localparam integer GIF_ICON_Y0 = ICON_MARGIN_Y;

    localparam integer TEMP_ICON_W  = ICON_W;
    localparam integer TEMP_ICON_H  = ICON_H;
    localparam integer TEMP_ICON_X0 = 136;
    localparam integer TEMP_ICON_Y0 = 112;

    localparam integer KP_ICON_W  = ICON_W;
    localparam integer KP_ICON_H  = ICON_H;
    localparam integer KP_ICON_X0 = 136;
    localparam integer KP_ICON_Y0 = ICON_MARGIN_Y;

    localparam [8:0] PLAY_X0  = 9'd90;
    localparam [8:0] PLAY_X1  = 9'd230;
    localparam [8:0] PLAY_Y0  = 9'd80;
    localparam [8:0] PLAY_Y1  = 9'd120;

    localparam [8:0] EXIT_X0  = 9'd90;
    localparam [8:0] EXIT_X1  = 9'd230;
    localparam [8:0] EXIT_Y0  = 9'd140;
    localparam [8:0] EXIT_Y1  = 9'd180;

    localparam [8:0] GIF_HOME_X0 = 9'd120;
    localparam [8:0] GIF_HOME_X1 = 9'd200;
    localparam [8:0] GIF_HOME_Y0 = 9'd10;
    localparam [8:0] GIF_HOME_Y1 = 9'd40;

    localparam [8:0] KP_HOME_X0 = 9'd120;
    localparam [8:0] KP_HOME_X1 = 9'd200;
    localparam [8:0] KP_HOME_Y0 = 9'd10;
    localparam [8:0] KP_HOME_Y1 = 9'd40;

    localparam [8:0] TEMP_HOME_X0 = 9'd120;
    localparam [8:0] TEMP_HOME_X1 = 9'd200;
    localparam [8:0] TEMP_HOME_Y0 = 9'd10;
    localparam [8:0] TEMP_HOME_Y1 = 9'd40;

    localparam [2:0]
        APP_HOME     = 3'd0,
        APP_BREAKOUT = 3'd1,
        APP_GIF      = 3'd2,
        APP_KEYPAD   = 3'd3,
        APP_TEMP     = 3'd4;

    reg [2:0] app_state;

    localparam [1:0]
        B_IDLE      = 2'd0,
        B_PLAY      = 2'd1,
        B_GAME_OVER = 2'd2;

    reg [1:0] b_state;

    assign bl_pwm = 1'b1;
    assign sd_cs  = 1'b1;

    reg  [15:0] fb_data_reg;
    wire [15:0] fb_data = fb_data_reg;
    wire        framebufferClk;

    tft_ili9341 #(
        .INPUT_CLK_MHZ(50)
    ) tft_inst (
        .clk            (clk_50),
        .reset_n        (reset_n),
        .tft_sdo        (1'b0),
        .tft_sck        (lcd_sck),
        .tft_sdi        (lcd_mosi),
        .tft_dc         (lcd_rs),
        .tft_reset      (lcd_rst),
        .tft_cs         (lcd_cs),
        .framebufferData(fb_data),
        .framebufferClk (framebufferClk)
    );

    assign led_touch_y = touch_y[11:8];

    // Rotated touch mapping:
    // Map FT6336 touch directly into game space without extra X scaling.
    // The previous 240->320 scaling shifted the icon hitboxes left of the drawn icons.
    wire [9:0] game_touch_x =
        (touch_y > 12'd319) ? 10'd319 : touch_y[9:0];

    wire [7:0] touch_x_clamped =
        (touch_x[7:0] > 8'd239) ? 8'd239 : touch_x[7:0];

    wire [8:0] game_touch_y = 9'd239 - {1'b0, touch_x_clamped};

    reg touch_down_d;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            touch_down_d <= 1'b0;
        else
            touch_down_d <= touch_down;
    end

    wire touch_rise = touch_down && !touch_down_d;

    localparam integer ICON_HIT_MARGIN = 12;

    localparam integer CHAR_H      = 7;
    localparam integer LABEL_GAP_Y = 8;
    localparam integer EXTRA_Y     = 12;

    // Make all home-screen icon hitboxes include the icon and its label,
    // and give them a little extra padding so taps are forgiving.
    wire in_breakout_icon =
        (game_touch_x >= ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  ICON_X0 + ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  (ICON_Y0 + ICON_H + LABEL_GAP_Y + CHAR_H + EXTRA_Y + ICON_HIT_MARGIN));

    wire in_gif_icon =
        (game_touch_x >= GIF_ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  GIF_ICON_X0 + GIF_ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= GIF_ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  (GIF_ICON_Y0 + GIF_ICON_H + LABEL_GAP_Y + CHAR_H + EXTRA_Y + ICON_HIT_MARGIN));

    wire in_temp_icon =
        (game_touch_x >= TEMP_ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  TEMP_ICON_X0 + TEMP_ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= TEMP_ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  (TEMP_ICON_Y0 + TEMP_ICON_H + LABEL_GAP_Y + CHAR_H + EXTRA_Y + ICON_HIT_MARGIN));

    wire in_keypad_icon =
        (game_touch_x >= KP_ICON_X0 - ICON_HIT_MARGIN) &&
        (game_touch_x <  KP_ICON_X0 + KP_ICON_W + ICON_HIT_MARGIN) &&
        (game_touch_y >= KP_ICON_Y0 - ICON_HIT_MARGIN) &&
        (game_touch_y <  (KP_ICON_Y0 + KP_ICON_H + LABEL_GAP_Y + CHAR_H + EXTRA_Y + ICON_HIT_MARGIN));

    wire in_gif_home_btn =
        (game_touch_x >= GIF_HOME_X0) &&
        (game_touch_x <  GIF_HOME_X1) &&
        (game_touch_y >= GIF_HOME_Y0) &&
        (game_touch_y <  GIF_HOME_Y1);

    wire in_keypad_home_btn =
        (game_touch_x >= KP_HOME_X0) &&
        (game_touch_x <  KP_HOME_X1) &&
        (game_touch_y >= KP_HOME_Y0) &&
        (game_touch_y <  KP_HOME_Y1);

    wire in_temp_home_btn =
        (game_touch_x >= TEMP_HOME_X0) &&
        (game_touch_x <  TEMP_HOME_X1) &&
        (game_touch_y >= TEMP_HOME_Y0) &&
        (game_touch_y <  TEMP_HOME_Y1);

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

    wire tap_breakout_icon = touch_rise && touch_valid && in_breakout_icon;
    wire tap_gif_icon      = touch_rise && touch_valid && in_gif_icon;
    wire tap_temp_icon     = touch_rise && touch_valid && in_temp_icon;
    wire tap_keypad_icon   = touch_rise && touch_valid && in_keypad_icon;

    wire tap_gif_home      = touch_rise && touch_valid && in_gif_home_btn;
    wire tap_temp_home     = touch_rise && touch_valid && in_temp_home_btn;
    wire tap_keypad_home   = touch_rise && touch_valid && in_keypad_home_btn;

    wire tap_play_again    = touch_rise && touch_valid && in_play_btn;
    wire tap_quit          = touch_rise && touch_valid && in_quit_btn;

    reg  [8:0] paddle_target_x;
    wire [3:0] paddle_x_nibble;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            paddle_target_x <= 9'd160;
        end else begin
            if ((app_state == APP_BREAKOUT) &&
                (b_state   == B_PLAY) &&
                touch_valid && touch_down) begin
                paddle_target_x <= game_touch_x[8:0];
            end
        end
    end

    assign paddle_x_nibble = paddle_target_x[8:5];
    assign led_paddle_x    = paddle_x_nibble;

    reg  game_run;
    reg  new_game;
    wire ball_lost;
    wire breakout_game_over = (b_state == B_GAME_OVER);

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            app_state <= APP_HOME;
            b_state   <= B_IDLE;
            game_run  <= 1'b0;
            new_game  <= 1'b0;
        end else begin
            new_game <= 1'b0;

            case (app_state)
                APP_HOME: begin
                    game_run <= 1'b0;
                    b_state  <= B_IDLE;

                    if (tap_breakout_icon) begin
                        app_state <= APP_BREAKOUT;
                        b_state   <= B_PLAY;
                        game_run  <= 1'b1;
                        new_game  <= 1'b1;
                    end else if (tap_gif_icon) begin
                        app_state <= APP_GIF;
                    end else if (tap_temp_icon) begin
                        app_state <= APP_TEMP;
                    end else if (tap_keypad_icon) begin
                        app_state <= APP_KEYPAD;
                    end
                end

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

                APP_GIF: begin
                    game_run <= 1'b0;
                    if (tap_gif_home)
                        app_state <= APP_HOME;
                end

                APP_KEYPAD: begin
                    game_run <= 1'b0;
                    if (tap_keypad_home)
                        app_state <= APP_HOME;
                end

                APP_TEMP: begin
                    game_run <= 1'b0;
                    if (tap_temp_home)
                        app_state <= APP_HOME;
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

    reg  [3:0] selected_hex;

    wire       keypad_key_pulse;
    wire [3:0] keypad_key_value;

    wire keypad_touch_event =
        (app_state == APP_KEYPAD) ? (touch_rise && touch_valid) : 1'b0;

    keypad_touch_decode keypad_decode_inst (
        .clk        (clk_50),
        .reset_n    (reset_n),
        .touch_valid(keypad_touch_event),
        .touch_x    (game_touch_x[9:0]),
        .touch_y    (game_touch_y[8:0]),
        .key_pulse  (keypad_key_pulse),
        .key_value  (keypad_key_value)
    );

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            selected_hex <= 4'h0;
        else if ((app_state == APP_KEYPAD) && keypad_key_pulse)
            selected_hex <= keypad_key_value;
    end

    wire [6:0] hex0_keypad_raw;

    hex7seg hex0_inst (
        .val(selected_hex),
        .seg(hex0_keypad_raw)
    );

    // Blank HEX0 unless actively in keypad app
    // DE10-Lite segments are active-low, so 7'b1111111 = off
    assign HEX0 = (app_state == APP_KEYPAD) ? hex0_keypad_raw : 7'b1111111;

    wire [15:0] home_pixel;
    wire [15:0] scene_pixel;
    wire [15:0] gif_pixel;
    wire [15:0] keypad_pixel;
    wire [15:0] temp_pixel;

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

    keypad_renderer #(
        .GAME_W (GAME_W),
        .GAME_H (GAME_H),
        .SWAP_XY(0),
        .FLIP_X (0),
        .FLIP_Y (0)
    ) keypad_inst (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .selected_hex  (selected_hex),
        .pixel_color   (keypad_pixel)
    );

    temperature_renderer #(
        .GAME_W(GAME_W),
        .GAME_H(GAME_H)
    ) temp_inst (
        .clk           (clk_50),
        .reset_n       (reset_n),
        .framebufferClk(framebufferClk),
        .temp_valid    (temp_valid_in),
        .sensor_present(temp_sensor_present),
        .temp_centi_c  (temp_centi_c_in),
        .pixel_color   (temp_pixel)
    );

    always @* begin
        case (app_state)
            APP_HOME:     fb_data_reg = home_pixel;
            APP_BREAKOUT: fb_data_reg = scene_pixel;
            APP_GIF:      fb_data_reg = gif_pixel;
            APP_KEYPAD:   fb_data_reg = keypad_pixel;
            APP_TEMP:     fb_data_reg = temp_pixel;
            default:      fb_data_reg = 16'h0000;
        endcase
    end

    reg [23:0] blink_cnt;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            blink_cnt <= 24'd0;
        else
            blink_cnt <= blink_cnt + 24'd1;
    end

    assign debug_led = blink_cnt[23];

endmodule

`default_nettype wire
