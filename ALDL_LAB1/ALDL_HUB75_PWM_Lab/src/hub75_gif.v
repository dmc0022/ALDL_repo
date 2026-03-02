// hub75_gif.v
// Parameterized version of your working GIF player.
// Same FSM / timing style, only made configurable.
//
// Pixel byte format in hex: bit2=R, bit1=G, bit0=B

module hub75_gif #(
    parameter integer NUM_FRAMES = 72,
    parameter integer FRAME_HOLD = 64,
    parameter integer SHOW_TICKS = 3000,
    parameter         MEM_FILE   = "GIF1.hex"
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

    // -----------------------------
    // helper: clog2 (Verilog-safe)
    // -----------------------------
    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1)
                value = value >> 1;
            clog2 = i;
        end
    endfunction

    // Panel geometry (UNCHANGED)
    localparam integer WIDTH          = 32;
    localparam integer ROWS_PER_GROUP = 16;

    // Frame geometry (UNCHANGED 32x32)
    localparam integer FRAME_W   = 32;
    localparam integer FRAME_H   = 32;
    localparam integer FRAME_PIX = FRAME_W * FRAME_H;   // 1024
    localparam integer FRAME_SH  = 10;                  // log2(1024)

    // ROM sizing
    localparam integer ROM_DEPTH   = FRAME_PIX * NUM_FRAMES;
    localparam integer ADDR_W      = (ROM_DEPTH  <= 1) ? 1 : clog2(ROM_DEPTH);
    localparam integer FRAME_IDX_W = (NUM_FRAMES <= 1) ? 1 : clog2(NUM_FRAMES);

    // FSM states (UNCHANGED)
    localparam STATE_SHIFT = 2'd0;
    localparam STATE_LATCH = 2'd1;
    localparam STATE_SHOW  = 2'd2;

    // Scan state (UNCHANGED)
    reg [1:0]  state;
    reg [4:0]  col_idx;        // 0..31
    reg [3:0]  row_idx;        // 0..15 (row pair index)
    reg        pixel_phase;    // 0: setup, 1: pulse CLK
    reg [15:0] show_cnt;

    // Frame control (only width is parameterized)
    reg [FRAME_IDX_W-1:0] frame_idx;
    reg [7:0]             frame_hold_cnt;

    // Registered ROM outputs (1-cycle delayed)
    wire [7:0] rom_top_dout;
    wire [7:0] rom_bot_dout;

    // Current addresses we present to ROM this cycle
    reg [ADDR_W-1:0] addr_top;
    reg [ADDR_W-1:0] addr_bot;

    // Base address for current frame: frame_idx * 1024 (same as {frame_idx,10'b0})
    wire [ADDR_W-1:0] base_addr = {{(ADDR_W-FRAME_IDX_W){1'b0}}, frame_idx} << FRAME_SH;

    // Global Y for top/bottom halves (UNCHANGED)
    wire [5:0] y_top = row_idx;          //  0..15
    wire [5:0] y_bot = row_idx + 6'd16;  // 16..31

    // Extend for address math (UNCHANGED mapping)
    wire [ADDR_W-1:0] y_top_ext = {{(ADDR_W-6){1'b0}}, y_top};
    wire [ADDR_W-1:0] y_bot_ext = {{(ADDR_W-6){1'b0}}, y_bot};
    wire [ADDR_W-1:0] x_ext     = {{(ADDR_W-5){1'b0}}, col_idx};

    // Next-cycle addresses (same mapping as original)
    wire [ADDR_W-1:0] next_addr_top = base_addr + (y_top_ext << 5) + x_ext;
    wire [ADDR_W-1:0] next_addr_bot = base_addr + (y_bot_ext << 5) + x_ext;

    // Two synchronous ROM instances (same as your original structure)
    gif_rom #(
        .ROM_DEPTH (ROM_DEPTH),
        .ADDR_W    (ADDR_W),
        .MEM_FILE  (MEM_FILE)
    ) u_rom_top (
        .clk  (clk),
        .addr (addr_top),
        .dout (rom_top_dout)
    );

    gif_rom #(
        .ROM_DEPTH (ROM_DEPTH),
        .ADDR_W    (ADDR_W),
        .MEM_FILE  (MEM_FILE)
    ) u_rom_bot (
        .clk  (clk),
        .addr (addr_bot),
        .dout (rom_bot_dout)
    );

    // ------------------------------------------------------------
    // MAIN LOGIC (UNCHANGED sequencing/structure)
    // ------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
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

            frame_idx      <= {FRAME_IDX_W{1'b0}};
            frame_hold_cnt <= 8'd0;

            addr_top <= {ADDR_W{1'b0}};
            addr_bot <= {ADDR_W{1'b0}};

        end else begin

            // Update frame index once per full panel refresh (same condition, now parameterized)
            if (state == STATE_SHOW &&
                show_cnt == SHOW_TICKS &&
                row_idx  == ROWS_PER_GROUP-1) begin

                if (frame_hold_cnt == FRAME_HOLD-1) begin
                    frame_hold_cnt <= 8'd0;

                    if (frame_idx == NUM_FRAMES-1)
                        frame_idx <= {FRAME_IDX_W{1'b0}};
                    else
                        frame_idx <= frame_idx + 1'b1;

                end else begin
                    frame_hold_cnt <= frame_hold_cnt + 8'd1;
                end
            end

            case (state)

                // SHIFT
                STATE_SHIFT: begin
                    oe  <= 1'b1;
                    lat <= 1'b0;

                    if (!pixel_phase) begin
                        clk_out  <= 1'b0;
                        addr_top <= next_addr_top;
                        addr_bot <= next_addr_bot;

                        r1 <= rom_top_dout[2];
                        g1 <= rom_top_dout[1];
                        b1 <= rom_top_dout[0];

                        r2 <= rom_bot_dout[2];
                        g2 <= rom_bot_dout[1];
                        b2 <= rom_bot_dout[0];

                        pixel_phase <= 1'b1;

                    end else begin
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

                // LATCH
                STATE_LATCH: begin
                    clk_out  <= 1'b0;
                    oe       <= 1'b1;
                    lat      <= 1'b1;
                    row_addr <= row_idx;
                    show_cnt <= 16'd0;

                    addr_top <= base_addr + (y_top_ext << 5);
                    addr_bot <= base_addr + (y_bot_ext << 5);

                    state    <= STATE_SHOW;
                end

                // SHOW
                STATE_SHOW: begin
                    lat     <= 1'b0;
                    clk_out <= 1'b0;
                    oe      <= 1'b0;

                    show_cnt <= show_cnt + 16'd1;
                    if (show_cnt == SHOW_TICKS) begin
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

