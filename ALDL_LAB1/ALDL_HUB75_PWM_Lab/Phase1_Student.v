// hub75_phase1_pixel.v (STUDENT VERSION / SKELETON)
// Phase 1: Single pixel moves across the panel, cycling R->G->B.
// Students fill in the TODO sections.
//
// ============================
// PHASE 1 TODO CHECKLIST
// ============================
// 1) Implement scan FSM: SHIFT -> LATCH -> SHOW
//    - SHIFT: output RGB bits for current column, pulse CLK 32 times
//    - LATCH: pulse LAT once after 32 columns
//    - SHOW: assert OE for a programmable interval (brightness)
// 2) Implement row/column counters:
//    - col_idx: 0..31
//    - row_idx: 0..15 (row_addr outputs)
// 3) Implement moving pixel coordinates (pix_x, pix_y):
//    - single pixel across 32x32
//    - move once every MOVE_FRAMES refreshes (or similar)
//    - wrap around at edges
// 4) Implement RGB cycle: R -> G -> B -> R ...
// 5) Implement brightness (PWM) using SW[4:2] (0..7):
//    - map brightness level to show_limit
//    - during SHOW: OE_ON while show_cnt < show_limit, else OE_OFF


module hub75_phase1_pixel #(
    parameter integer WIDTH          = 32,
    parameter integer ROWS_PER_GROUP = 16,    // 1/16 scan => 16 row addresses (top+bottom)
    parameter integer SHOW_TICKS     = 12000, // OE-on time per row
    parameter integer MOVE_FRAMES    = 20,    // move pixel every N full refreshes
    parameter         OE_ACTIVE_LOW  = 1      // most HUB75 panels: OE=0 enables output
)(
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

    // -------------------------
    // OE polarity helpers
    // -------------------------
    localparam OE_ON  = (OE_ACTIVE_LOW) ? 1'b0 : 1'b1;
    localparam OE_OFF = (OE_ACTIVE_LOW) ? 1'b1 : 1'b0;

    // -------------------------
    // Scan FSM: SHIFT -> LATCH -> SHOW
    // -------------------------
    localparam S_SHIFT = 2'd0;
    localparam S_LATCH = 2'd1;
    localparam S_SHOW  = 2'd2;

    reg [1:0] state;

    reg [5:0] col_idx;       // 0..31
    reg [3:0] row_idx;       // 0..15
    reg       shift_phase;   // toggles to create a CLK pulse per column
    reg [15:0] show_cnt;     // counts SHOW interval ticks

    // -------------------------
    // Moving pixel state (full 32x32)
    // -------------------------
    reg [5:0] pix_x;         // 0..31
    reg [5:0] pix_y;         // 0..31
    reg [1:0] color_sel;     // 0=R,1=G,2=B
    reg [15:0] move_frame_cnt;

    // -------------------------
    // Match logic for current scan row-pair
    // -------------------------
    // NOTE: Row addressing is 0..15. Top half is y=0..15, bottom half is y=16..31.
    // For y=16..31, pix_y[3:0] naturally maps to 0..15.

    wire top_half = (pix_y < 6'd16);
    wire bot_half = (pix_y >= 6'd16);
    wire [3:0] pix_y_row = pix_y[3:0];

    // TODO(PHASE1-MATCH): Complete these match expressions
    //   top_match should be 1 ONLY when:
    //     - pixel is in the top half
    //     - the currently scanned row (row_idx) equals the pixel's row within the half (pix_y_row)
    //     - the currently shifted column (col_idx) equals pix_x
    //
    //   bot_match should be 1 ONLY when:
    //     - pixel is in the bottom half
    //     - row_idx equals pix_y_row
    //     - col_idx equals pix_x
    wire top_match = 1'b0; // TODO: replace with boolean expression
    wire bot_match = 1'b0; // TODO: replace with boolean expression

    // -------------------------
    // Color bits (1-bit channels for Phase 1 bring-up)
    // -------------------------
    // TODO(PHASE1-COLOR): Define c_r/c_g/c_b based on color_sel:
    //   color_sel=0 -> Red on
    //   color_sel=1 -> Green on
    //   color_sel=2 -> Blue on
    wire c_r = 1'b0; // TODO
    wire c_g = 1'b0; // TODO
    wire c_b = 1'b0; // TODO

    // -------------------------
    // Sequential logic
    // -------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // outputs
            r1 <= 0; g1 <= 0; b1 <= 0;
            r2 <= 0; g2 <= 0; b2 <= 0;
            row_addr <= 0;
            clk_out <= 0;
            lat <= 0;
            oe  <= OE_OFF;

            // fsm
            state <= S_SHIFT;
            col_idx <= 0;
            row_idx <= 0;
            shift_phase <= 0;
            show_cnt <= 0;

            // pixel motion
            pix_x <= 0;
            pix_y <= 0;
            color_sel <= 0;
            move_frame_cnt <= 0;

        end else begin
            // default “safe” values (overridden per-state)
            lat <= 1'b0;

            // Keep row_addr updated to current scan row
            row_addr <= row_idx;

            case (state)

                // ---------------------------------
                // SHIFT: present RGB data + pulse CLK for each column
                // ---------------------------------
                S_SHIFT: begin
                    oe <= OE_OFF;     // TODO(PHASE1-SHIFT): Keep OE blank during SHIFT
                    clk_out <= 1'b0;  // default low

                    // Only drive pixel data on the setup half-cycle
                    if (shift_phase == 1'b0) begin
                        // TODO(PHASE1-SHIFT-DATA): Drive RGB outputs for current col/row.
                        // HINT: if top_match is true, drive (c_r,c_g,c_b) on (r1,g1,b1).
                        //       if bot_match is true, drive (c_r,c_g,c_b) on (r2,g2,b2).
                        //       otherwise drive zeros.
                        r1 <= 1'b0; g1 <= 1'b0; b1 <= 1'b0;  // TODO
                        r2 <= 1'b0; g2 <= 1'b0; b2 <= 1'b0;  // TODO

                        // Next cycle will be the rising edge pulse
                        shift_phase <= 1'b1; // TODO(PHASE1-CLK): keep or implement shift_phase toggle
                    end else begin
                        // TODO(PHASE1-CLK): Generate a clock pulse for HUB75 shift register
                        // HINT: set clk_out high for this cycle, then low next cycle.
                        clk_out <= 1'b1; // TODO

                        // Finish this column; advance column counter
                        shift_phase <= 1'b0;

                        // TODO(PHASE1-COL): Increment col_idx, and when col_idx hits WIDTH-1:
                        //   - reset col_idx to 0
                        //   - go to S_LATCH
                        if (col_idx == WIDTH-1) begin
                            col_idx <= 0;       // TODO (ok to keep)
                            state   <= S_LATCH; // TODO (ok to keep)
                        end else begin
                            col_idx <= col_idx + 1'b1; // TODO (ok to keep)
                        end
                    end
                end

                // ---------------------------------
                // LATCH: commit shifted row data
                // ---------------------------------
                S_LATCH: begin
                    // TODO(PHASE1-LATCH): Pulse LAT for 1 cycle, keep OE off, then go to SHOW.
                    oe      <= OE_OFF; // TODO
                    clk_out <= 1'b0;
                    lat     <= 1'b1;   // TODO: latch pulse
                    show_cnt <= 0;     // TODO: reset show counter
                    state   <= S_SHOW; // TODO: go to show
                end

                // ---------------------------------
                // SHOW: enable LEDs for SHOW_TICKS
                // ---------------------------------
                S_SHOW: begin
                    clk_out <= 1'b0;

                    // TODO(PHASE1-SHOW): Enable display output during SHOW
                    // If you later add PWM duty, OE will turn on/off inside SHOW.
                    oe <= OE_ON; // TODO

                    // TODO(PHASE1-SHOWCNT): Count show_cnt up to SHOW_TICKS-1
                    if (show_cnt == SHOW_TICKS-1) begin
                        oe <= OE_OFF;      // blank before next row shift
                        show_cnt <= 0;

                        // TODO(PHASE1-ROW): Advance row_idx 0..ROWS_PER_GROUP-1
                        // When the row wraps (row_idx hits ROWS_PER_GROUP-1), that marks one full refresh.
                        if (row_idx == ROWS_PER_GROUP-1) begin
                            row_idx <= 0;

                            // TODO(PHASE1-MOVEFRAME): update move_frame_cnt each full refresh
                            // When move_frame_cnt reaches MOVE_FRAMES-1:
                            //   - reset move_frame_cnt
                            //   - advance pixel position
                            //   - cycle color_sel
                            if (move_frame_cnt == MOVE_FRAMES-1) begin
                                move_frame_cnt <= 0;

                                // TODO(PHASE1-MOVE): Move pixel (pix_x, pix_y)
                                // Suggestion (row-major):
                                //   pix_x increments each move
                                //   when pix_x hits WIDTH-1 -> pix_x=0 and pix_y increments
                                //   when pix_y hits 31 -> pix_y=0
                                // pix_x <= ...
                                // pix_y <= ...

                                // TODO(PHASE1-COLORCYCLE): Cycle color_sel R->G->B->R
                                // color_sel <= ...
                            end else begin
                                move_frame_cnt <= move_frame_cnt + 1'b1; // TODO
                            end

                        end else begin
                            row_idx <= row_idx + 1'b1; // TODO
                        end

                        // Back to shifting next row
                        state <= S_SHIFT;
                    end else begin
                        show_cnt <= show_cnt + 1'b1; // TODO
                    end
                end

                default: begin
                    state <= S_SHIFT;
                end
            endcase
        end
    end

endmodule
