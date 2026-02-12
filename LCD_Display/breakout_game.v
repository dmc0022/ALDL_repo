// breakout_game.v
// -----------------------------------------------------------------------------
// Breakout game logic (physics + brick HP + score) driven by a STABLE time tick.
//
// Why this refactor matters:
//   Previously, “smoothness” could accidentally depend on rendering timing
//   (which can jitter if SPI stalls or pixel cadence changes).
//   This version updates game state on a fixed-rate tick derived from clk,
//   so the ball/paddle motion stays consistent regardless of display SPI speed.
//
// Brick mechanic:
//   - Rows 0..1: 3 hits
//   - Rows 2..3: 2 hits
//   - Rows 4..5: 1 hit
//   - Score +5 when a brick is destroyed
//
// Notes:
//   - This module does NOT depend on framebufferClk or renderer scan counters.
//   - game_run freezes updates (tick still runs but no state changes).
//   - ball_lost latches until new_game/reset.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module breakout_game #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer GAME_W      = 320,
    parameter integer GAME_H      = 240
)(
    input  wire       clk,
    input  wire       reset_n,

    // Game control
    input  wire       game_run,   // 1 = game running, 0 = frozen
    input  wire       new_game,   // 1-cycle pulse to reset game state

    // Paddle target (from touch), GAME coordinates 0..GAME_W-1
    input  wire [8:0] paddle_target_x,

    // Outputs in GAME coordinates (0..GAME_W-1, 0..GAME_H-1)
    output reg  [8:0] paddle_x,      // paddle center X
    output reg  [8:0] ball_x_pix,    // ball top-left X
    output reg  [8:0] ball_y_pix,    // ball top-left Y

    // Brick state and score
    output reg  [47:0] bricks_alive, // 6 * 8 = 48 bricks
    output reg  [9:0]  score,        // 0..1023

    // Game over condition
    output reg         ball_lost     // 1 when ball passes paddle (latched until new_game/reset)
);

    // -------------------------------------------------------------------------
    // Tunable game tick rate
    // -------------------------------------------------------------------------
    localparam integer TICK_HZ  = 60; // change to 120 if you want faster updates
    localparam integer TICK_DIV = (CLK_FREQ_HZ / TICK_HZ);
    localparam integer TICK_W   = $clog2(TICK_DIV);

    reg [TICK_W-1:0] tick_cnt;
    reg              game_tick;   // 1-cycle pulse

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_cnt  <= {TICK_W{1'b0}};
            game_tick <= 1'b0;
        end else begin
            if (tick_cnt == TICK_DIV-1) begin
                tick_cnt  <= {TICK_W{1'b0}};
                game_tick <= 1'b1;
            end else begin
                tick_cnt  <= tick_cnt + {{(TICK_W-1){1'b0}},1'b1};
                game_tick <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Game geometry (match your renderer assumptions)
    // -------------------------------------------------------------------------
    localparam integer HUD_H       = 24;

    localparam integer BRICK_ROWS  = 6;
    localparam integer BRICK_COLS  = 8;

    localparam integer BRICK_W     = 32;
    localparam integer BRICK_H     = 9;
    localparam integer BRICK_X_SP  = 3;
    localparam integer BRICK_Y_SP  = 4;
    localparam integer BRICK_X0    = 5;
    localparam integer BRICK_Y0    = HUD_H + 8;

    localparam integer PADDLE_W    = 32;
    localparam integer PADDLE_H    = 9;
    localparam integer PADDLE_Y    = GAME_H - 30;

    localparam integer BALL_SIZE   = 8;

    // -------------------------------------------------------------------------
    // State: ball velocity and brick HP
    // -------------------------------------------------------------------------
    reg  signed [3:0] ball_vx;
    reg  signed [3:0] ball_vy;

    reg  [1:0] brick_hp [0:47]; // 2 bits is enough for 0..3 hits

    integer r, c, idx;

    // -------------------------------------------------------------------------
    // Helper: init ball + bricks (but not score)
    // -------------------------------------------------------------------------
    task init_ball_and_bricks;
    begin
        ball_x_pix   = GAME_W/2 - BALL_SIZE/2;
        ball_y_pix   = PADDLE_Y - 16;
        ball_vx      = 4'sd3;        // slight diagonal
        ball_vy      = -4'sd2;       // up
        ball_lost    = 1'b0;

        for (r = 0; r < BRICK_ROWS; r = r + 1) begin
            for (c = 0; c < BRICK_COLS; c = c + 1) begin
                idx = r*BRICK_COLS + c;

                if (r < 2)
                    brick_hp[idx] = 2'd3;
                else if (r < 4)
                    brick_hp[idx] = 2'd2;
                else
                    brick_hp[idx] = 2'd1;

                bricks_alive[idx] = 1'b1;
            end
        end
    end
    endtask

    // -------------------------------------------------------------------------
    // Main update (ONLY on game_tick)
    // -------------------------------------------------------------------------
    integer desired_paddle;

    integer bricks_y_end;
    integer bricks_x_end;

    integer nx, ny;              // proposed next ball position (signed int)
    integer bcx_old, bcy_old;    // old ball center
    integer bcx, bcy;            // new ball center

    integer paddle_left;
    integer paddle_right;
    integer hit_pos;

    integer brick_col, brick_row;
    integer brick_x_start, brick_y_start;
    integer brick_idx;

    // "next" versions of velocity so we can update cleanly
    reg signed [3:0] vx_next;
    reg signed [3:0] vy_next;

    // flags
    reg hit_any_brick;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            paddle_x <= GAME_W/2;
            score    <= 10'd0;
            init_ball_and_bricks();
        end else if (new_game) begin
            score <= 10'd0;
            init_ball_and_bricks();
        end else if (game_tick && game_run && !ball_lost) begin
            // -----------------------------------------------------------------
            // 1) Paddle follows target (clamped)
            // -----------------------------------------------------------------
            desired_paddle = paddle_target_x;

            if (desired_paddle < (PADDLE_W/2))
                desired_paddle = (PADDLE_W/2);
            else if (desired_paddle > (GAME_W-1 - (PADDLE_W/2)))
                desired_paddle = (GAME_W-1 - (PADDLE_W/2));

            paddle_x <= desired_paddle[8:0];

            // -----------------------------------------------------------------
            // 2) Compute next ball position (start with current velocity)
            // -----------------------------------------------------------------
            vx_next = ball_vx;
            vy_next = ball_vy;

            nx = $signed(ball_x_pix) + $signed(ball_vx);
            ny = $signed(ball_y_pix) + $signed(ball_vy);

            bcx_old = ball_x_pix + BALL_SIZE/2;
            bcy_old = ball_y_pix + BALL_SIZE/2;
            bcx     = nx + BALL_SIZE/2;
            bcy     = ny + BALL_SIZE/2;

            // Precompute brick bounds for quick rejection
            bricks_y_end = BRICK_Y0 + BRICK_ROWS*(BRICK_H + BRICK_Y_SP);
            bricks_x_end = BRICK_X0 + BRICK_COLS*(BRICK_W + BRICK_X_SP);

            // -----------------------------------------------------------------
            // 3) Wall collisions (left/right)
            // -----------------------------------------------------------------
            if (nx <= 0) begin
                nx      = 0;
                vx_next = -vx_next;
                nx      = $signed(ball_x_pix) + $signed(vx_next);
                bcx     = nx + BALL_SIZE/2;
            end else if (nx >= (GAME_W - BALL_SIZE)) begin
                nx      = (GAME_W - BALL_SIZE);
                vx_next = -vx_next;
                nx      = $signed(ball_x_pix) + $signed(vx_next);
                bcx     = nx + BALL_SIZE/2;
            end

            // -----------------------------------------------------------------
            // 4) Top HUD boundary
            // -----------------------------------------------------------------
            if (ny <= HUD_H) begin
                ny      = HUD_H;
                vy_next = -vy_next;
                ny      = $signed(ball_y_pix) + $signed(vy_next);
                bcy     = ny + BALL_SIZE/2;
            end

            // -----------------------------------------------------------------
            // 5) Paddle collision (only when moving downward)
            // -----------------------------------------------------------------
            paddle_left  = desired_paddle - (PADDLE_W/2);
            paddle_right = desired_paddle + (PADDLE_W/2);

            if (vy_next > 0) begin
                if ( (ball_y_pix + BALL_SIZE <= PADDLE_Y) &&
                     (ny + BALL_SIZE >= PADDLE_Y) ) begin

                    if (bcx >= paddle_left && bcx <= paddle_right) begin
                        ny      = PADDLE_Y - BALL_SIZE;
                        vy_next = -4'sd1;

                        hit_pos = bcx - paddle_left; // 0..PADDLE_W

                        if      (hit_pos < (PADDLE_W/5))   vx_next = -4'sd1;
                        else if (hit_pos < (2*PADDLE_W/5)) vx_next = -4'sd1;
                        else if (hit_pos < (3*PADDLE_W/5)) vx_next =  4'sd0;
                        else if (hit_pos < (4*PADDLE_W/5)) vx_next =  4'sd1;
                        else                               vx_next =  4'sd1;

                        ny  = $signed(ball_y_pix) + $signed(vy_next);
                        bcy = ny + BALL_SIZE/2;
                    end
                end
            end

            // -----------------------------------------------------------------
            // 6) Brick collision (grid-based)
            // -----------------------------------------------------------------
            hit_any_brick = 1'b0;

            if ( (bcx >= BRICK_X0) && (bcx < bricks_x_end) &&
                 (bcy >= BRICK_Y0) && (bcy < bricks_y_end) ) begin

                brick_col = (bcx - BRICK_X0) / (BRICK_W + BRICK_X_SP);
                brick_row = (bcy - BRICK_Y0) / (BRICK_H + BRICK_Y_SP);

                if (brick_row >= 0 && brick_row < BRICK_ROWS &&
                    brick_col >= 0 && brick_col < BRICK_COLS) begin

                    brick_x_start = BRICK_X0 + brick_col*(BRICK_W + BRICK_X_SP);
                    brick_y_start = BRICK_Y0 + brick_row*(BRICK_H + BRICK_Y_SP);

                    if ( (bcx >= brick_x_start) &&
                         (bcx <  brick_x_start + BRICK_W) &&
                         (bcy >= brick_y_start) &&
                         (bcy <  brick_y_start + BRICK_H) ) begin

                        brick_idx = brick_row*BRICK_COLS + brick_col;

                        if (bricks_alive[brick_idx]) begin
                            hit_any_brick = 1'b1;

                            // Bounce decision using old vs new center
                            if ((vx_next > 0) &&
                                (bcx_old <= brick_x_start) &&
                                (bcx     >= brick_x_start)) begin

                                vx_next = -vx_next;
                                nx      = brick_x_start - BALL_SIZE;
                                bcx     = nx + BALL_SIZE/2;
                            end
                            else if ((vx_next < 0) &&
                                     (bcx_old >= brick_x_start + BRICK_W) &&
                                     (bcx     <= brick_x_start + BRICK_W)) begin

                                vx_next = -vx_next;
                                nx      = brick_x_start + BRICK_W;
                                bcx     = nx + BALL_SIZE/2;
                            end
                            else if ((vy_next > 0) &&
                                     (bcy_old <= brick_y_start) &&
                                     (bcy     >= brick_y_start)) begin

                                vy_next = -vy_next;
                                ny      = brick_y_start - BALL_SIZE;
                                bcy     = ny + BALL_SIZE/2;
                            end
                            else begin
                                vy_next = -vy_next;
                                ny      = brick_y_start + BRICK_H;
                                bcy     = ny + BALL_SIZE/2;
                            end

                            // HP / destruction (fixes “check after decrement” bug)
                            if (brick_hp[brick_idx] != 2'd0) begin
                                if (brick_hp[brick_idx] == 2'd1) begin
                                    brick_hp[brick_idx] <= 2'd0;
                                    bricks_alive[brick_idx] <= 1'b0;
                                    score <= score + 10'd5;
                                end else begin
                                    brick_hp[brick_idx] <= brick_hp[brick_idx] - 2'd1;
                                end
                            end
                        end
                    end
                end
            end

            // -----------------------------------------------------------------
            // 7) Bottom miss (lose ball)
            // -----------------------------------------------------------------
            if (ny >= (GAME_H - BALL_SIZE)) begin
                ball_lost  <= 1'b1;
                ball_y_pix <= (GAME_H - BALL_SIZE);
                ball_x_pix <= nx[8:0];
            end else begin
                ball_x_pix <= nx[8:0];
                ball_y_pix <= ny[8:0];
            end

            // Commit velocities at the end of the tick
            ball_vx <= vx_next;
            ball_vy <= vy_next;
        end
    end

endmodule
