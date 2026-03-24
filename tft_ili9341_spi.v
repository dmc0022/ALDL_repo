// --- Byte-wise SPI + DC implementation (Verilog-2001)
// * Will copy data into internal buffer
// * 'idle' will be set to 0 once buffer copy is complete
// * Data is only copied if 'dataAvailable' is set to 1
// * SPI CLK will stop (high state) if no data is being sent

module tft_ili9341_spi(
    input  wire       spiClk,
    input  wire [8:0] data,
    input  wire       dataAvailable,
    output wire       tft_sck,
    output reg        tft_sdi,
    output reg        tft_dc,
    output wire       tft_cs,
    output reg        idle
);

    // Registers
    reg [0:2] counter;          // 3-bit counter (0..7)
    reg [8:0] internalData;
    reg       internalSck;
    reg       cs;

    // Combinational assignments
    wire        dataDc;
    wire [0:7]  dataShift;      // MSB first (index 0)

    assign dataDc    = internalData[8];
    assign dataShift = internalData[7:0]; // MSB maps to index 0 via [0:7] range

    assign tft_sck = internalSck & cs;    // only drive SCK with an active CS
    assign tft_cs  = ~cs;                 // active low

    // Initial conditions
    initial begin
        counter      = 3'b000;
        internalData = 9'b0;
        internalSck  = 1'b1;
        idle         = 1'b1;
        cs           = 1'b0;
        tft_sdi      = 1'b0;
        tft_dc       = 1'b0;
    end

    // Update SPI CLK + output data
    always @(posedge spiClk) begin
        // Store new data in internal register
        if (dataAvailable) begin
            internalData <= data;
            idle         <= 1'b0;
            // NOTE: original SystemVerilog did not explicitly reset counter here.
            // We keep that behavior for compatibility.
        end

        // Change data if we're actively sending
        if (!idle) begin
            // Toggle clock on every active tick
            internalSck <= ~internalSck;

            // Check if SCK will be low on next half cycle
            if (internalSck) begin
                // Update pins on the "falling" half
                tft_dc  <= dataDc;
                tft_sdi <= dataShift[counter];
                cs      <= 1'b1;

                // Advance counter
                counter <= counter + 3'b001;
                // we're just sending the last bit when all bits are 1
                idle    <= &counter;
            end
        end else begin
            // idle mode (also: sent last bit)
            internalSck <= 1'b1;
            if (internalSck)
                cs <= 1'b0; // idle for two bits in a row -> deactivate CS
        end
    end

endmodule
