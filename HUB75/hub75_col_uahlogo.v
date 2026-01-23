module hub75_uahlogo (
    input  wire       clk,
    input  wire       reset_n,

    output reg        r1,
    output reg        g1,
    output reg        b1,
    output reg        r2,
    output reg        g2,
    output reg        b2,

    output reg  [3:0] row_addr,
    output reg        clk_out,
    output reg        lat,
    output reg        oe
);

    // Panel geometry
    localparam WIDTH          = 32;
    localparam ROWS_PER_GROUP = 16;

    // FSM states
    localparam STATE_SHIFT = 2'd0;
    localparam STATE_LATCH = 2'd1;
    localparam STATE_SHOW  = 2'd2;

    // UAH sprite size (upright orientation)
    localparam SPRITE_W = 17;
    localparam SPRITE_H = 7;

    // Bounce limits
    localparam MAX_X = WIDTH - SPRITE_W; // 15
    localparam MAX_Y = WIDTH - SPRITE_H; // 25

    // State registers
    reg [1:0]  state;
    reg [4:0]  col_idx;
    reg [3:0]  row_idx;
    reg        pixel_phase;
    reg [15:0] show_cnt;

    // Bouncing sprite position
    reg [5:0] text_x;
    reg [5:0] text_y;
    reg       move_right;
    reg       move_down;
    reg [21:0] move_cnt;

    // Sprite hit flags
    reg sprite_on_top;
    reg sprite_on_bot;

    // Temp vars (declared here to avoid SystemVerilog)
    reg [5:0] y_top, y_bot;
    reg [4:0] sx_top, sy_top;
    reg [4:0] sx_bot, sy_bot;


    // ------------------------------------------------------------
    // UAH bitmap (upright, 17×7)
    // ------------------------------------------------------------
    function [0:0] uah_pixel;
        input [4:0] sx;
        input [3:0] sy;
        reg [16:0] row_bits;
    begin
        if (sy >= SPRITE_H)
            uah_pixel = 1'b0;
        else begin
            case (sy)
                4'd0: row_bits = 17'b10001_0_01110_0_10001;
                4'd1: row_bits = 17'b10001_0_10001_0_10001;
                4'd2: row_bits = 17'b10001_0_10001_0_10001;
                4'd3: row_bits = 17'b10001_0_11111_0_11111;
                4'd4: row_bits = 17'b10001_0_10001_0_10001;
                4'd5: row_bits = 17'b10001_0_10001_0_10001;
                4'd6: row_bits = 17'b01110_0_10001_0_10001;
                default: row_bits = 17'd0;
            endcase

            if (sx < SPRITE_W)
                uah_pixel = row_bits[SPRITE_W - 1 - sx];
            else
                uah_pixel = 1'b0;
        end
    end
    endfunction


    // ------------------------------------------------------------
    // MAIN LOGIC
    // ------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            
            state   <= STATE_SHIFT;
            col_idx <= 0;
            row_idx <= 0;
            pixel_phase <= 0;
            show_cnt <= 0;

            clk_out <= 0;
            lat     <= 0;
            oe      <= 1;

            r1 <= 0; g1 <= 0; b1 <= 0;
            r2 <= 0; g2 <= 0; b2 <= 0;

            text_x     <= 4;
            text_y     <= 4;
            move_right <= 1;
            move_down  <= 1;
            move_cnt   <= 0;

            sprite_on_top <= 0;
            sprite_on_bot <= 0;

        end else begin

            // ----------------------------------------------------
            // Bounce logic
            // ----------------------------------------------------
            move_cnt <= move_cnt + 1;
            if (move_cnt == 22'd3_000_000) begin
                move_cnt <= 0;

                // Horizontal bounce
                if (move_right) begin
                    if (text_x == MAX_X) move_right <= 0;
                    else text_x <= text_x + 1;
                end else begin
                    if (text_x == 0) move_right <= 1;
                    else text_x <= text_x - 1;
                end

                // Vertical bounce
                if (move_down) begin
                    if (text_y == MAX_Y) move_down <= 0;
                    else text_y <= text_y + 1;
                end else begin
                    if (text_y == 0) move_down <= 1;
                    else text_y <= text_y - 1;
                end
            end


            // ----------------------------------------------------
            // HUB75 scan FSM
            // ----------------------------------------------------
            case (state)

                // =================================================
                // SHIFT PIXELS
                // =================================================
                STATE_SHIFT: begin
                    oe  <= 1;
                    lat <= 0;

                    if (!pixel_phase) begin
                        clk_out <= 0;

                        // CLEAR FLAGS FIRST
                        sprite_on_top = 0;
                        sprite_on_bot = 0;

                        // Global y mapping
                        y_top = row_idx;       
                        y_bot = row_idx + 16;

                        // ---------------- TOP HALF ----------------
                        if (col_idx >= text_x && col_idx < text_x + SPRITE_W &&
                            y_top   >= text_y && y_top   < text_y + SPRITE_H) begin
                            sx_top = col_idx - text_x;
                            sy_top = y_top   - text_y;
                            sprite_on_top = uah_pixel(sx_top, sy_top);
                        end

                        // ---------------- BOTTOM HALF ----------------
                        if (col_idx >= text_x && col_idx < text_x + SPRITE_W &&
                            y_bot   >= text_y && y_bot   < text_y + SPRITE_H) begin
                            sx_bot = col_idx - text_x;
                            sy_bot = y_bot   - text_y;
                            sprite_on_bot = uah_pixel(sx_bot, sy_bot);
                        end

                        {r1,g1,b1} <= sprite_on_top ? 3'b001 : 3'b000;
                        {r2,g2,b2} <= sprite_on_bot ? 3'b001 : 3'b000;

                        pixel_phase <= 1;

                    end else begin
                        clk_out <= 1;
                        pixel_phase <= 0;

                        if (col_idx == WIDTH-1) begin
                            col_idx <= 0;
                            state <= STATE_LATCH;
                        end else
                            col_idx <= col_idx + 1;
                    end
                end


                // =================================================
                // LATCH
                // =================================================
                STATE_LATCH: begin
                    clk_out <= 0;
                    oe      <= 1;
                    lat     <= 1;
                    row_addr <= row_idx;
                    show_cnt <= 0;
                    state    <= STATE_SHOW;
                end


                // =================================================
                // SHOW
                // =================================================
                STATE_SHOW: begin
                    lat     <= 0;
                    clk_out <= 0;
                    oe      <= 0;

                    show_cnt <= show_cnt + 1;
                    if (show_cnt == 16'd3000) begin
                        oe <= 1;

                        if (row_idx == ROWS_PER_GROUP-1)
                            row_idx <= 0;
                        else
                            row_idx <= row_idx + 1;

                        show_cnt <= 0;
                        state    <= STATE_SHIFT;
                    end
                end

            endcase
        end
    end

endmodule


  
