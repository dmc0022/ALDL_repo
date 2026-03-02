// hub75_phase2_gradient.v
// Phase 2: Full-screen rainbow (top->bottom hue bands) + bit-plane PWM (3bpc)
//          + GLOBAL brightness using OE gating (SW[4:2])
//
// Brightness approach:
//   Keep plane time constant, and gate OE within SHOW.
//   This gives a clear dimming effect without slowing the whole refresh.

`default_nettype none

module hub75_phase2_gradient (
    input  wire       clk,
    input  wire       reset_n,
    input  wire [2:0] bright,      // recommend SW[4:2] (0..7)

    output reg        r1, g1, b1,
    output reg        r2, g2, b2,

    output reg  [3:0] row_addr,
    output reg        clk_out,
    output reg        lat,
    output reg        oe
);

    // ------------------------------------------------------------
    // Panel geometry / PWM planes
    // ------------------------------------------------------------
    localparam integer WIDTH          = 32;
    localparam integer ROWS_PER_GROUP = 16;   // 1/16 scan
    localparam integer PLANES         = 3;    // 3-bit per color: planes 0..2

    // Plane timing (50 MHz): plane 0 is BASE, plane1=2*BASE, plane2=4*BASE
    localparam integer BASE_SHOW_TICKS = 800;

    // OE active-low on most HUB75 panels
    localparam OE_ON  = 1'b0;
    localparam OE_OFF = 1'b1;

    // FSM states
    localparam S_SHIFT = 2'd0;
    localparam S_LATCH = 2'd1;
    localparam S_SHOW  = 2'd2;

    reg [1:0]  state;
    reg [5:0]  col_idx;       // 0..31
    reg [3:0]  row_idx;       // 0..15
    reg        shift_phase;   // 0=setup, 1=pulse clk
    reg [15:0] show_cnt;

    reg [1:0]  plane;         // 0..2
    reg [15:0] plane_ticks;   // total ticks for this plane (constant)
    reg [15:0] oe_on_ticks;   // ticks OE is enabled (scaled by bright)

    // ------------------------------------------------------------
    // Current scan coordinates
    // ------------------------------------------------------------
    wire [5:0] y_top = {2'b00, row_idx};              // 0..15
    wire [5:0] y_bot = 6'd16 + {2'b00, row_idx};      // 16..31

    // ------------------------------------------------------------
    // Rainbow/hue gradient by Y (matches your reference image)
    // Returns 3-bit RGB for a given row y (0..31)
    // ------------------------------------------------------------
    function [8:0] hue_row_rgb3;
        input [5:0] y;
        integer seg, pos, len;
        integer ramp_int;
        reg [2:0] ramp3;
        reg [2:0] rr, gg, bb;
        begin
            // Segment layout across 32 rows:
            // 0..5   : red -> yellow
            // 6..11  : yellow -> green
            // 12..17 : green -> cyan
            // 18..23 : cyan -> blue
            // 24..31 : blue -> purple
            if (y < 6) begin
                seg = 0; len = 6; pos = y;
            end else if (y < 12) begin
                seg = 1; len = 6; pos = y - 6;
            end else if (y < 18) begin
                seg = 2; len = 6; pos = y - 12;
            end else if (y < 24) begin
                seg = 3; len = 6; pos = y - 18;
            end else begin
                seg = 4; len = 8; pos = y - 24;
            end

            // ramp 0..7 across the segment
            ramp_int = (pos * 7) / (len - 1);
            ramp3 = ramp_int[2:0];

            case (seg)
                0: begin rr = 3'd7;        gg = ramp3;      bb = 3'd0; end // red->yellow
                1: begin rr = 3'd7-ramp3;  gg = 3'd7;       bb = 3'd0; end // yellow->green
                2: begin rr = 3'd0;        gg = 3'd7;       bb = ramp3; end // green->cyan
                3: begin rr = 3'd0;        gg = 3'd7-ramp3; bb = 3'd7; end // cyan->blue
                default: begin rr = ramp3; gg = 3'd0;       bb = 3'd7; end // blue->purple
            endcase

            hue_row_rgb3 = {rr, gg, bb};
        end
    endfunction

    // Top/bottom RGB 3-bit levels for the current scanned row-pair
    wire [8:0] rgb_top = hue_row_rgb3(y_top);
    wire [8:0] rgb_bot = hue_row_rgb3(y_bot);

    wire [2:0] r_top_lvl = rgb_top[8:6];
    wire [2:0] g_top_lvl = rgb_top[5:3];
    wire [2:0] b_top_lvl = rgb_top[2:0];

    wire [2:0] r_bot_lvl = rgb_bot[8:6];
    wire [2:0] g_bot_lvl = rgb_bot[5:3];
    wire [2:0] b_bot_lvl = rgb_bot[2:0];

    // Current plane bits (bit-plane PWM)
    wire r1_bit = r_top_lvl[plane];
    wire g1_bit = g_top_lvl[plane];
    wire b1_bit = b_top_lvl[plane];

    wire r2_bit = r_bot_lvl[plane];
    wire g2_bit = g_bot_lvl[plane];
    wire b2_bit = b_bot_lvl[plane];

    // ------------------------------------------------------------
    // Sequential FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r1 <= 1'b0; g1 <= 1'b0; b1 <= 1'b0;
            r2 <= 1'b0; g2 <= 1'b0; b2 <= 1'b0;

            row_addr <= 4'd0;
            clk_out  <= 1'b0;
            lat      <= 1'b0;
            oe       <= OE_OFF;

            state       <= S_SHIFT;
            col_idx     <= 6'd0;
            row_idx     <= 4'd0;
            shift_phase <= 1'b0;

            show_cnt    <= 16'd0;
            plane       <= 2'd0;
            plane_ticks <= 16'd100;
            oe_on_ticks <= 16'd1;

        end else begin
            lat      <= 1'b0;     // default
            row_addr <= row_idx;  // continuously drive row address

            case (state)

                // ------------------------------------------------
                // SHIFT: output 32 columns worth of data
                // ------------------------------------------------
                S_SHIFT: begin
                    oe      <= OE_OFF;   // blank while shifting
                    clk_out <= 1'b0;

                    if (shift_phase == 1'b0) begin
                        // setup data
                        r1 <= r1_bit; g1 <= g1_bit; b1 <= b1_bit;
                        r2 <= r2_bit; g2 <= g2_bit; b2 <= b2_bit;
                        shift_phase <= 1'b1;
                    end else begin
                        // pulse CLK
                        clk_out <= 1'b1;
                        shift_phase <= 1'b0;

                        if (col_idx == WIDTH-1) begin
                            col_idx <= 6'd0;
                            state   <= S_LATCH;
                        end else begin
                            col_idx <= col_idx + 1'b1;
                        end
                    end
                end

                // ------------------------------------------------
                // LATCH: commit the shifted row
                // also compute plane timing + brightness gating
                // ------------------------------------------------
                S_LATCH: begin
                    oe      <= OE_OFF;
                    clk_out <= 1'b0;
                    lat     <= 1'b1;

                    show_cnt <= 16'd0;

                    // Total time for this plane (constant):
                    plane_ticks <= (BASE_SHOW_TICKS << plane);

                    // Stronger dimming curve:
                    //   bright=0 -> 1 tick (almost off)
                    //   bright=7 -> full
                    //   else     -> (bright/8)*plane_ticks
                    if (bright == 3'd0) begin
                        oe_on_ticks <= 16'd1;
                    end else if (bright == 3'd7) begin
                        oe_on_ticks <= (BASE_SHOW_TICKS << plane);
                    end else begin
                        oe_on_ticks <= (((BASE_SHOW_TICKS << plane) * {1'b0, bright}) >> 3);
                        if ((((BASE_SHOW_TICKS << plane) * {1'b0, bright}) >> 3) == 0)
                            oe_on_ticks <= 16'd1;
                    end

                    state <= S_SHOW;
                end

                // ------------------------------------------------
                // SHOW: keep plane_ticks constant, gate OE inside it
                // ------------------------------------------------
                S_SHOW: begin
                    clk_out <= 1'b0;

                    // Only enable OE for first oe_on_ticks of this plane window.
                    oe <= (show_cnt < oe_on_ticks) ? OE_ON : OE_OFF;

                    if (show_cnt == (plane_ticks - 1)) begin
                        oe <= OE_OFF;
                        show_cnt <= 16'd0;

                        // Next plane or next row
                        if (plane == (PLANES-1)) begin
                            plane <= 2'd0;

                            if (row_idx == ROWS_PER_GROUP-1)
                                row_idx <= 4'd0;
                            else
                                row_idx <= row_idx + 1'b1;

                        end else begin
                            plane <= plane + 1'b1;
                        end

                        state <= S_SHIFT;
                    end else begin
                        show_cnt <= show_cnt + 1'b1;
                    end
                end

                default: state <= S_SHIFT;
            endcase
        end
    end

endmodule

`default_nettype wire



