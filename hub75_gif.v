// hub75_col_gradient.v
// HUB75 32x32 GIF player using synchronous gif_rom (M9K).
// 1/16 scan, 32x32 panel.
//
// Each pixel byte from ROM: bit2=R, bit1=G, bit0=B.

module hub75_gif (
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

    // GIF parameters (must match gif_rom + Python script)
    localparam FRAME_W        = 32;
    localparam FRAME_H        = 32;
    localparam NUM_FRAMES     = 60;   // <== change if GIF frame count differs
    localparam FRAME_PIX      = FRAME_W * FRAME_H; // 1024 = 2^10

    // FSM states
    localparam STATE_SHIFT = 2'd0;
    localparam STATE_LATCH = 2'd1;
    localparam STATE_SHOW  = 2'd2;

    // Scan state
    reg [1:0]  state;
    reg [4:0]  col_idx;        // 0..31
    reg [3:0]  row_idx;        // 0..15 (row pair index)
    reg        pixel_phase;    // 0: setup, 1: pulse CLK
    reg [15:0] show_cnt;

    // Frame control
    reg [5:0] frame_idx;       // 0..NUM_FRAMES-1
    reg [7:0] frame_hold_cnt;  // slows animation
	
	
	// This value determines how fast GIF plays, 64 seems like a good pace
    localparam FRAME_HOLD = 8'd64; // increase for slower GIF

    // Registered ROM outputs (1-cycle delayed)
    wire [7:0] rom_top_dout;
    wire [7:0] rom_bot_dout;

    // Current addresses we present to ROM this cycle
    reg  [15:0] addr_top;
    reg  [15:0] addr_bot;

    // Base address for current frame: frame_idx * 1024 = frame_idx << 10
    wire [15:0] base_addr = {frame_idx, 10'b0};

    // Global Y for top/bottom halves
    wire [5:0] y_top = row_idx;          //  0..15
    wire [5:0] y_bot = row_idx + 6'd16;  // 16..31

    // Next-cycle addresses (combinational)
    wire [15:0] next_addr_top =
        base_addr + ( {10'd0, y_top} << 5 ) + col_idx;
    wire [15:0] next_addr_bot =
        base_addr + ( {10'd0, y_bot} << 5 ) + col_idx;

    // Synchronous ROM instances
    gif_rom #(
        .FRAME_W    (FRAME_W),
        .FRAME_H    (FRAME_H),
        .NUM_FRAMES (NUM_FRAMES)
    ) u_rom_top (
        .clk  (clk),
        .addr (addr_top),
        .dout (rom_top_dout)
    );

    gif_rom #(
        .FRAME_W    (FRAME_W),
        .FRAME_H    (FRAME_H),
        .NUM_FRAMES (NUM_FRAMES)
    ) u_rom_bot (
        .clk  (clk),
        .addr (addr_bot),
        .dout (rom_bot_dout)
    );

    // ------------------------------------------------------------
    // MAIN LOGIC
    // ------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset state
            state          <= STATE_SHIFT;
            col_idx        <= 5'd0;
            row_idx        <= 4'd0;
            pixel_phase    <= 1'b0;
            show_cnt       <= 16'd0;
            row_addr       <= 4'd0;
            clk_out        <= 1'b0;
            lat            <= 1'b0;
            oe             <= 1'b1;

            r1 <= 1'b0; g1 <= 1'b0; b1 <= 1'b0;
            r2 <= 1'b0; g2 <= 1'b0; b2 <= 1'b0;

            frame_idx      <= 6'd0;
            frame_hold_cnt <= 8'd0;

            addr_top <= 16'd0;
            addr_bot <= 16'd0;

        end else begin

            // ------------------------------------------------
            // Update frame index once per full panel refresh
            // ------------------------------------------------
            if (state == STATE_SHOW &&
                show_cnt == 16'd3000 &&
                row_idx  == ROWS_PER_GROUP-1) begin

                if (frame_hold_cnt == FRAME_HOLD-1) begin
                    frame_hold_cnt <= 8'd0;
                    if (frame_idx == NUM_FRAMES-1)
                        frame_idx <= 6'd0;
                    else
                        frame_idx <= frame_idx + 6'd1;
                end else begin
                    frame_hold_cnt <= frame_hold_cnt + 8'd1;
                end
            end

            // ------------------------------------------------
            // HUB75 scan FSM
            // ------------------------------------------------
            case (state)

                // =========================================
                // SHIFT: shift one pair of rows
                // =========================================
                STATE_SHIFT: begin
                    oe  <= 1'b1;  // outputs off while shifting
                    lat <= 1'b0;

                    if (!pixel_phase) begin
                        // Phase 0: set ROM addresses for *next* pixel
                        clk_out  <= 1'b0;
                        addr_top <= next_addr_top;
                        addr_bot <= next_addr_bot;

                        // Meanwhile, rom_*_dout already holds the data
                        // for the *previous* pixel, which we now drive.
                        r1 <= rom_top_dout[2];
                        g1 <= rom_top_dout[1];
                        b1 <= rom_top_dout[0];

                        r2 <= rom_bot_dout[2];
                        g2 <= rom_bot_dout[1];
                        b2 <= rom_bot_dout[0];

                        pixel_phase <= 1'b1;

                    end else begin
                        // Phase 1: pulse CLK high to shift this pixel
                        clk_out     <= 1'b1;
                        pixel_phase <= 1'b0;

                        if (col_idx == WIDTH-1) begin
                            col_idx <= 5'd0;
                            state   <= STATE_LATCH;
                        end else begin
                            col_idx <= col_idx + 5'd1;
                        end
                    end
                end

                // =========================================
                // LATCH: latch this row pair
                // =========================================
                STATE_LATCH: begin
                    clk_out  <= 1'b0;
                    oe       <= 1'b1;
                    lat      <= 1'b1;
                    row_addr <= row_idx;
                    show_cnt <= 16'd0;

                    // Prime the ROM addresses for the *first* pixel
                    // of the next row pair (col_idx is 0 here).
                    addr_top <= base_addr + ( {10'd0, y_top} << 5 );
                    addr_bot <= base_addr + ( {10'd0, y_bot} << 5 );

                    state    <= STATE_SHOW;
                end

                // =========================================
                // SHOW: enable row pair for some time
                // =========================================
                STATE_SHOW: begin
                    lat     <= 1'b0;
                    clk_out <= 1'b0;
                    oe      <= 1'b0;

                    show_cnt <= show_cnt + 16'd1;
                    if (show_cnt == 16'd3000) begin
                        oe <= 1'b1;

                        if (row_idx == ROWS_PER_GROUP-1)
                            row_idx <= 4'd0;
                        else
                            row_idx <= row_idx + 4'd1;

                        show_cnt <= 16'd0;
                        state    <= STATE_SHIFT;
                    end
                end

                default: state <= STATE_SHIFT;

            endcase
        end
    end

endmodule
