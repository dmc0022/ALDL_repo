// tft_ili9341_spi_wrapper.v
// -----------------------------------------------------------------------------
// TFT SPI Wrapper (DC + 8-bit byte), Verilog-2001
//
// Purpose:
//   - Preserve your original 9-bit "data" interface used by tft_ili9341.v:
//       data[8]   = DC (0=command, 1=data)
//       data[7:0] = byte to transmit
//       dataAvailable = pulse when a byte is ready to send
//       idle = 1 when ready to accept the next byte
//   - Implement standard SPI Mode 0 timing using the generic spi_master_byte.
//
// Important behavior (compatible with your existing driver):
//   - Accepts a new byte ONLY when idle=1 and dataAvailable=1.
//   - Latches DC + byte, asserts CS, transmits the byte, deasserts CS.
//   - SCK is held LOW when idle.
//   - DC is updated once per byte (latched with the data).
//
// Notes about shared SPI bus (LCD + SD on same SCK/MOSI/MISO):
//   - This wrapper only drives the TFT pins (CS/DC/SCK/MOSI).
//   - For SD card support, you will add an SD controller that also uses
//     spi_master_byte and shares SCK/MOSI/MISO through an arbiter.
//   - For now, LCD_driver_top.v keeps sd_cs HIGH (inactive).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tft_ili9341_spi_wrapper #(
    parameter [15:0] CLK_DIV = 16'd2  // half-period divider (50MHz -> ~12.5MHz SCK)
)(
    input  wire       spiClk,
    input  wire       reset_n,

    input  wire [8:0] data,            // {DC, byte}
    input  wire       dataAvailable,

    output wire       tft_sck,
    output wire       tft_sdi,
    output reg        tft_dc,
    output wire       tft_cs,           // active-low
    output reg        idle
);

    // Latches for current byte
    reg [7:0] latched_byte;

    // SPI master control
    reg        spi_start;
    wire [7:0] spi_rx;
    wire       spi_done;
    wire       spi_busy;

    // Internal SPI pins (ungated)
    wire sck_int;
    wire mosi_int;

    // CS active during transfer
    reg cs_active;

    // Pin assignments
    assign tft_cs  = ~cs_active;
    assign tft_sdi = mosi_int;

    // Optional clock gating: do not toggle SCK unless CS active
    assign tft_sck = sck_int & cs_active;

    spi_master_byte u_spi (
        .clk      (spiClk),
        .reset_n  (reset_n),
        .clk_div  (CLK_DIV),

        .start    (spi_start),
        .tx_byte  (latched_byte),

        .rx_byte  (spi_rx),
        .done     (spi_done),
        .busy     (spi_busy),

        .sck      (sck_int),
        .mosi     (mosi_int),
        .miso     (1'b1)          // TFT readback not used (safe to tie high)
    );

    initial begin
        latched_byte = 8'h00;
        tft_dc       = 1'b0;

        spi_start = 1'b0;
        cs_active = 1'b0;
        idle      = 1'b1;
    end

    always @(posedge spiClk) begin
        if (!reset_n) begin
            latched_byte <= 8'h00;
            tft_dc       <= 1'b0;

            spi_start <= 1'b0;
            cs_active <= 1'b0;
            idle      <= 1'b1;
        end else begin
            spi_start <= 1'b0; // default

            // Accept a new byte when idle
            if (idle && dataAvailable) begin
                latched_byte <= data[7:0];
                tft_dc       <= data[8];

                cs_active <= 1'b1;
                spi_start <= 1'b1;
                idle      <= 1'b0;
            end

            // Done -> release CS and go idle
            if (!idle && spi_done) begin
                cs_active <= 1'b0;
                idle      <= 1'b1;
            end
        end
    end

endmodule
