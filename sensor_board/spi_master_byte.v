// spi_master_byte.v
// -----------------------------------------------------------------------------
// Generic SPI Master (Mode 0) - byte transactions, MSB first, Verilog-2001
//
// SPI mode:
//   - CPOL = 0  (SCK idles LOW)
//   - CPHA = 0  (sample on rising edge, shift/change on falling edge)
//
// Interface:
//   - Pulse 'start' high for 1 clk to begin sending 'tx_byte'.
//   - 'busy' stays high while 8 bits are transferred.
//   - 'done' pulses high for 1 clk when complete.
//   - 'rx_byte' holds the received byte captured on MISO.
//
// Clock divider:
//   clk_div = number of 'clk' cycles per HALF SCK period.
//   SCK frequency ~= clk_freq / (2*clk_div)
//
// Notes:
//   - When not busy, SCK is held LOW.
//   - MOSI is driven stable before the first rising edge.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module spi_master_byte (
    input  wire        clk,
    input  wire        reset_n,

    input  wire [15:0] clk_div,

    input  wire        start,
    input  wire [7:0]  tx_byte,

    output reg  [7:0]  rx_byte,
    output reg         done,
    output reg         busy,

    output reg         sck,
    output reg         mosi,
    input  wire        miso
);

    reg [15:0] div_cnt;
    reg [7:0]  rx_shift;
    reg [2:0]  bit_cnt;

    wire start_go = start & ~busy;

    initial begin
        div_cnt  = 16'd0;
        rx_shift = 8'h00;
        bit_cnt  = 3'd0;

        sck     = 1'b0;
        mosi    = 1'b0;
        rx_byte = 8'h00;

        done = 1'b0;
        busy = 1'b0;
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            div_cnt  <= 16'd0;
            rx_shift <= 8'h00;
            bit_cnt  <= 3'd0;

            sck     <= 1'b0;
            mosi    <= 1'b0;
            rx_byte <= 8'h00;

            done <= 1'b0;
            busy <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                // Idle: hold SCK low and wait for start
                sck <= 1'b0;
                div_cnt <= 16'd0;

                if (start_go) begin
                    busy    <= 1'b1;
                    bit_cnt <= 3'd7;
                    rx_shift <= 8'h00;

                    // Mode 0: MOSI must be valid before first rising edge
                    mosi <= tx_byte[7];
                end
            end else begin
                // Busy: generate SCK edges with divider
                if (div_cnt == (clk_div - 16'd1)) begin
                    div_cnt <= 16'd0;

                    // Toggle SCK
                    sck <= ~sck;

                    if (sck == 1'b0) begin
                        // Rising edge (LOW->HIGH): sample MISO
                        rx_shift[bit_cnt] <= miso;
                    end else begin
                        // Falling edge (HIGH->LOW): shift out next MOSI bit
                        if (bit_cnt != 3'd0) begin
                            bit_cnt <= bit_cnt - 3'd1;
                            mosi <= tx_byte[bit_cnt - 3'd1];
                        end else begin
                            // Completed last bit; finish transfer
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            rx_byte <= rx_shift;
                            sck     <= 1'b0;
                        end
                    end
                end else begin
                    div_cnt <= div_cnt + 16'd1;
                end
            end
        end
    end

endmodule
