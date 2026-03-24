// image_rom.v
// Simple ROM to store one full-screen image as 16-bit pixels.

module image_rom #(
    parameter ADDR_WIDTH = 17,        // enough for up to 2^17 = 131072 pixels
    parameter IMG_SIZE   = 76800      // 240*320 = 76800 pixels
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [15:0]           data
);

    // 16-bit pixels
    reg [15:0] mem [0:IMG_SIZE-1];



    initial begin
        // Simulation-only example:
         $readmemh("uah_logo_horizontal.hex", mem);
    end

    always @(posedge clk) begin
        if (addr < IMG_SIZE)
            data <= mem[addr];
        else
            data <= 16'h0000;
    end

endmodule
