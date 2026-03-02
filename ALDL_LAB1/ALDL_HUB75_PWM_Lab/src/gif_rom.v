// gif_rom.v
// Synchronous ROM for 32x32 frames stored in a Verilog hex file.
// 1-cycle latency read: dout valid on the clock AFTER addr is applied.
// Each line in MEM_FILE: 2 hex digits (00..FF).
//
// Pixel byte: bit2=R, bit1=G, bit0=B

module gif_rom #(
    parameter integer ROM_DEPTH = 73728,      // 1024 * NUM_FRAMES (default for 72 frames)
    parameter integer ADDR_W    = 17,         // must cover ROM_DEPTH-1
    parameter         MEM_FILE  = "GIF1.hex"
)(
    input  wire                 clk,
    input  wire [ADDR_W-1:0]     addr,
    output reg  [7:0]           dout
);

    (* ramstyle = "M9K" *)
    reg [7:0] mem [0:ROM_DEPTH-1];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    always @(posedge clk) begin
        dout <= mem[addr];
    end

endmodule

