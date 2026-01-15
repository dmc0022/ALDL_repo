// gif_rom.v
// Synchronous ROM for 32x32 GIF frames, 3-bit RGB packed into 8 bits
// (bit2=R, bit1=G, bit0=B).
//
// Address mapping (must match Python script):
//   addr = frame_idx * 1024 + y * 32 + x
//
// 1-cycle latency: dout is valid on the clock *after* addr is applied.
// Uses $readmemh with a simple Verilog hex file (one byte per line).

module gif_rom #(
    parameter FRAME_W     = 32,
    parameter FRAME_H     = 32,
    parameter NUM_FRAMES  = 60,                 // <== change if your GIF has different # frames
    parameter FRAME_PIX   = FRAME_W * FRAME_H,  // 1024
    parameter ROM_DEPTH   = FRAME_PIX * NUM_FRAMES
)(
    input  wire           clk,
    input  wire [15:0]    addr,
    output reg  [7:0]     dout
);

    // Force use of M9K blocks, but DO NOT specify ram_init_file here.
    (* ramstyle = "M9K" *)
    reg [7:0] mem [0:ROM_DEPTH-1];

    // Initialize from a Verilog-style hex file:
    //   myGIF_rgb3bpp.hex
    // Each line: two hex digits (00..FF).
    initial begin
        $readmemh("myGIF_rgb3bpp.hex", mem);
    end

    // Synchronous read (1-cycle latency)
    always @(posedge clk) begin
        dout <= mem[addr];
    end

endmodule
