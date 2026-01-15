// breakout_game.v
// Breakout game logic with external game state control.
//
// New mechanic:
//   * Bricks have hit points per row:
//       rows 0-1 (top):    3 hits
//       rows 2-3 (middle): 2 hits
//       rows 4-5 (bottom): 1 hit
//   * A brick is removed (bricks_alive bit cleared) when its HP reaches 0.
//   * Score increments only when a brick is destroyed (here: +5 per brick).
//
// Other behavior:
//   * Geometry matches renderer (bricks 32x9; paddle sprite 32 wide,
//     physics 40 wide).
//   * Ball moves 1 pixel per tick (vx,vy in {-1,0,+1}).
//   * Tile-based brick collision using ball center.
//   * Paddle hit angle changes based on where the ball strikes.

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

    // Must match renderer vertically
    localparam HUD_H      = 24;

    // Paddle geometry:
    //  - Renderer draws 32px-wide sprite.
    //  - Physics uses 40px width to make hits a bit easier.
    localparam PADDLE_W   = 40;
    localparam PADDLE_H   = 9;
    localparam PADDLE_Y   = GAME_H - 30;

    // Ball geometry
    localparam BALL_SIZE  = 8;

    // Brick layout (match breakout_renderer for position/size)
    localparam BRICK_ROWS   = 6;
    localparam BRICK_COLS   = 8;
    localparam BRICK_W      = 32;
    localparam BRICK_H      = 9;
    localparam BRICK_X_SP   = 3;
    localparam BRICK_Y_SP   = 4;
    localparam BRICK_X0     = 5;
    localparam BRICK_Y0     = HUD_H + 8;

    // Game tick
    localparam integer TICK_HZ   = 120;
    localparam integer TICK_DIV  = CLK_FREQ_HZ / TICK_HZ;
    localparam integer TICK_W    = $clog2(TICK_DIV);

    reg [TICK_W-1:0] tick_cnt;
    reg              game_tick;

    // Ball velocity in pixels per tick (signed, range -2..+2 but we use -1..+1)
    reg signed [3:0] ball_vx;
    reg signed [3:0] ball_vy;

    // Per-brick hit points (2 bits: up to 3 hits)
    reg [1:0] brick_hp [0:BRICK_ROWS*BRICK_COLS-1];

    // Scratch integers used inside the always block
    integer nx, ny;
    integer paddle_left, paddle_right;
    integer hit_pos;
    integer bcx, bcy;          // new ball center x/y
    integer bcx_old, bcy_old;  // old ball center x/y
    integer brick_row, brick_col;
    integer brick_idx;
    integer brick_x_start, brick_y_start;
    integer bricks_y_end;
    integer bricks_x_end;
    integer desired_paddle;

    integer r, c, idx;         // for init loops

    // ----------------------------------------------------------------
    // Create a slower game_tick
    // ----------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tick_cnt  <= 0;
            game_tick <= 1'b0;
        end else begin
            if (tick_cnt == TICK_DIV-1) begin
                tick_cnt  <= 0;
                game_tick <= 1'b1;
            end else begin
                tick_cnt  <= tick_cnt + 1'b1;
                game_tick <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Helper: init ball & bricks (BUT NOT score)
    // ----------------------------------------------------------------
    task init_ball_and_bricks;
    begin
        ball_x_pix   = GAME_W/2 - BALL_SIZE/2;
        ball_y_pix   = PADDLE_Y - 16;
        ball_vx      = 4'sd1;        // slight diagonal
        ball_vy      = -4'sd1;       // up
        ball_lost    = 1'b0;

        // Initialize brick HP and alive bits by row
        for (r = 0; r < BRICK_ROWS; r = r + 1) begin
            for (c = 0; c < BRICK_COLS; c = c + 1) begin
                idx = r*BRICK_COLS + c;

                // Top rows (0,1): 3 hits
                // Middle rows (2,3): 2 hits
                // Bottom rows (4,5): 1 hit
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

    // ----------------------------------------------------------------
    // Game state update
    // ----------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // full reset
            paddle_x = GAME_W/2;
            score    = 10'd0;
            init_ball_and_bricks();
        end else if (new_game) begin
            // new game: reset score & ball/bricks, keep paddle position
            score = 10'd0;
            init_ball_and_bricks();
        end else if (game_tick && game_run && !ball_lost) begin

            // ---------------- Paddle from target (touch) ----------------
            desired_paddle = paddle_target_x;

            // Clamp so paddle stays fully on screen
            if (desired_paddle < PADDLE_W/2)
                desired_paddle = PADDLE_W/2;
            else if (desired_paddle > GAME_W-1 - PADDLE_W/2)
                desired_paddle = GAME_W-1 - PADDLE_W/2;

            paddle_x = desired_paddle[8:0];

            // Precompute some boundary extents for bricks
            bricks_y_end = BRICK_Y0 + BRICK_ROWS*(BRICK_H + BRICK_Y_SP);
            bricks_x_end = BRICK_X0 + BRICK_COLS*(BRICK_W + BRICK_X_SP);

            // Compute proposed next ball position (1 pixel per tick)
            nx = $signed(ball_x_pix) + $signed(ball_vx);
            ny = $signed(ball_y_pix) + $signed(ball_vy);

            // Old center (before move) and new center (after move)
            bcx_old = ball_x_pix + BALL_SIZE/2;
            bcy_old = ball_y_pix + BALL_SIZE/2;
            bcx     = nx + BALL_SIZE/2;
            bcy     = ny + BALL_SIZE/2;

            // ---------------- Walls (left/right) ------------------------
            if (nx <= 0) begin
                nx      = 0;
                ball_vx = -ball_vx;
                nx      = $signed(ball_x_pix) + $signed(ball_vx);
                bcx     = nx + BALL_SIZE/2;
            end else if (nx >= GAME_W - BALL_SIZE) begin
                nx      = GAME_W - BALL_SIZE;
                ball_vx = -ball_vx;
                nx      = $signed(ball_x_pix) + $signed(ball_vx);
                bcx     = nx + BALL_SIZE/2;
            end

            // ---------------- Top HUD boundary --------------------------
            if (ny <= HUD_H) begin
                ny      = HUD_H;
                ball_vy = -ball_vy;
                ny      = $signed(ball_y_pix) + $signed(ball_vy);
                bcy     = ny + BALL_SIZE/2;
            end

            // ---------------- Paddle collision --------------------------
            paddle_left  = paddle_x - (PADDLE_W/2);
            paddle_right = paddle_x + (PADDLE_W/2);

            // Only check when ball moving downward
            if (ball_vy > 0) begin
                // Did we cross the paddle Y band?
                if ( (ball_y_pix + BALL_SIZE <= PADDLE_Y) &&
                     (ny + BALL_SIZE >= PADDLE_Y) ) begin

                    // Is ball horizontally over the paddle?
                    if (bcx >= paddle_left && bcx <= paddle_right) begin
                        // Bounce off paddle: always up
                        ny      = PADDLE_Y - BALL_SIZE;
                        ball_vy = -4'sd1;

                        // Change horizontal angle based on hit position
                        hit_pos = bcx - paddle_left;  // 0..PADDLE_W-1

                        if      (hit_pos < (PADDLE_W/5))          ball_vx = -4'sd1; // far left
                        else if (hit_pos < (2*PADDLE_W/5))        ball_vx = -4'sd1; // mid-left
                        else if (hit_pos < (3*PADDLE_W/5))        ball_vx =  4'sd0; // center
                        else if (hit_pos < (4*PADDLE_W/5))        ball_vx =  4'sd1; // mid-right
                        else                                      ball_vx =  4'sd1; // far right

                        ny  = $signed(ball_y_pix) + $signed(ball_vy);
                        bcy = ny + BALL_SIZE/2;
                    end
                end
            end

            // ---------------- Brick collision (grid-based) --------------
            if ( (bcx >= BRICK_X0) && (bcx < bricks_x_end) &&
                 (bcy >= BRICK_Y0) && (bcy < bricks_y_end) ) begin

                brick_col = (bcx - BRICK_X0) / (BRICK_W + BRICK_X_SP);
                brick_row = (bcy - BRICK_Y0) / (BRICK_H + BRICK_Y_SP);

                if (brick_row >= 0 && brick_row < BRICK_ROWS &&
                    brick_col >= 0 && brick_col < BRICK_COLS) begin

                    brick_x_start = BRICK_X0 +
                                    brick_col*(BRICK_W + BRICK_X_SP);
                    brick_y_start = BRICK_Y0 +
                                    brick_row*(BRICK_H + BRICK_Y_SP);

                    // inside the actual brick rectangle, not the gap?
                    if ( (bcx >= brick_x_start) &&
                         (bcx <  brick_x_start + BRICK_W) &&
                         (bcy >= brick_y_start) &&
                         (bcy <  brick_y_start + BRICK_H) ) begin

                        brick_idx = brick_row*BRICK_COLS + brick_col;

                        if (bricks_alive[brick_idx]) begin
                            // ---------- 1) BOUNCE OFF THIS BRICK ----------
                            // Decide entry side using old vs new centers.

                            // came from left?
                            if ((ball_vx > 0) &&
                                (bcx_old <= brick_x_start) &&
                                (bcx     >= brick_x_start)) begin

                                ball_vx = -ball_vx;
                                nx      = brick_x_start - BALL_SIZE;
                                bcx     = nx + BALL_SIZE/2;
                            end
                            // came from right?
                            else if ((ball_vx < 0) &&
                                     (bcx_old >= brick_x_start + BRICK_W) &&
                                     (bcx     <= brick_x_start + BRICK_W)) begin

                                ball_vx = -ball_vx;
                                nx      = brick_x_start + BRICK_W;
                                bcx     = nx + BALL_SIZE/2;
                            end
                            // came from above?
                            else if ((ball_vy > 0) &&
                                     (bcy_old <= brick_y_start) &&
                                     (bcy     >= brick_y_start)) begin

                                ball_vy = -ball_vy;
                                ny      = brick_y_start - BALL_SIZE;
                                bcy     = ny + BALL_SIZE/2;
                            end
                            // otherwise treat as from below
                            else begin
                                ball_vy = -ball_vy;
                                ny      = brick_y_start + BRICK_H;
                                bcy     = ny + BALL_SIZE/2;
                            end

                            // ---------- 2) HP / DESTRUCTION LOGIC ----------
                            // (brick may disappear now, but bounce already chosen)
                            if (brick_hp[brick_idx] > 0) begin
                                brick_hp[brick_idx] = brick_hp[brick_idx] - 2'd1;

                                if (brick_hp[brick_idx] == 0) begin
                                    bricks_alive[brick_idx] = 1'b0;
                                    score                   = score + 10'd5;   // 5 pts per brick
                                end
                            end
                        end
                    end
                end
            end

            // ---------------- Bottom miss (lose ball) --------------------
            if (ny >= GAME_H - BALL_SIZE) begin
                ball_lost  = 1'b1;
                ball_y_pix = GAME_H - BALL_SIZE;
                ball_x_pix = nx[8:0];
            end else begin
                ball_x_pix = nx[8:0];
                ball_y_pix = ny[8:0];
            end
        end
    end

endmodule
