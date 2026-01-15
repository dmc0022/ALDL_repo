// top.v — Use Terasic spi_ee_config (3-wire SPI) and show ±X.Y g on 7-seg.
// Verilog-2001. Requires spi_ee_config.v and VGA_Audio_PLL IP from the DE10-Lite demo.

module top (
    // clocks / switches
    input  wire        MAX10_CLK1_50,
    input  wire        MAX10_CLK2_50,
    input  wire [9:0]  SW,                 // not used, but keep for expansion
    input  wire [1:0]  KEY,                // KEY[0] = reset_n like the demo

    // accelerometer pins (on-board)
    output wire        GSENSOR_CS_n,
    output wire        GSENSOR_SCLK,
    inout  wire        GSENSOR_SDI,        // SDIO (bidirectional)
    inout  wire        GSENSOR_SDO,        // not used in 3-wire mode

    // seven segment (active-low)
    output reg  [7:0]  HEX5, HEX4, HEX3, HEX2, HEX1, HEX0,

    // (optional/unused) LEDs etc. — keep ports to satisfy your QSF if needed
    output wire [9:0]  LEDR
);

    // ---------------- reset like factory demo ----------------
    wire DLY_RST;
    wire reset_n = KEY[0];

    Reset_Delay u_rst (.iCLK(MAX10_CLK1_50), .oRESET(DLY_RST));

    // ---------------- SPI clocks from the factory PLL ----------------
    // Bring in the same PLL IP the demo uses; gives ~2 MHz spi_clk and a phase-shifted copy
    wire spi_clk, spi_clk_out;

    VGA_Audio_PLL u_pll (
        .areset(~DLY_RST),
        .inclk0(MAX10_CLK2_50),
        .c0(/* unused VGA */),
        .c1(spi_clk),       // ~2 MHz
        .c2(spi_clk_out)    // ~2 MHz, phase-shifted
    );

    // ---------------- Terasic SPI to ADXL345 ----------------
    // Important: 3-wire SDIO only uses GSENSOR_SDI; leave SDO hi-Z.
    assign GSENSOR_SDO = 1'bz;

    wire [15:0] data_x;  // factory block outputs one 16-bit sample (X axis in their demo)

    spi_ee_config u_spi (
        .iRSTN     (DLY_RST),
        .iSPI_CLK  (spi_clk),
        .iSPI_CLK_OUT(spi_clk_out),
        .iG_INT2   (1'b0),        // not using INT2 here
        .oDATA_L   (data_x[7:0]),
        .oDATA_H   (data_x[15:8]),
        .SPI_SDIO  (GSENSOR_SDI),
        .oSPI_CSN  (GSENSOR_CS_n),
        .oSPI_CLK  (GSENSOR_SCLK)
    );

    // Optional: mirror some bits to LEDs to show life
    assign LEDR = { data_x[9:0] };

    // ---------------- fixed-point: raw -> ±X.Y g ----------------
    // ADXL345 ±2 g, 256 LSB/g in the demo setup -> tenths ≈ |raw|*10/256
    function [15:0] abs16; input [15:0] v; begin abs16 = v[15] ? (~v+16'd1) : v; end endfunction

    wire signed [15:0] raw  = data_x;               // signed two’s complement
    wire        neg        = raw[15];
    wire [15:0] mag        = abs16(raw);
    wire [9:0]  tenths     = (mag*10 + 16'd128) >> 8;   // round(|raw|*10/256)
    wire [9:0]  tcl        = (tenths > 10'd199) ? 10'd199 : tenths; // clamp to 19.9g display

    wire [3:0] d2 = tcl/100;
    wire [3:0] d1 = (tcl/10)%10;
    wire [3:0] d0 = tcl%10;

    // ---------------- 7-segment (active-low) ----------------
    function [7:0] seg; input [3:0] n; begin
        case(n)
            4'h0: seg=8'b11000000; 4'h1: seg=8'b11111001; 4'h2: seg=8'b10100100; 4'h3: seg=8'b10110000;
            4'h4: seg=8'b10011001; 4'h5: seg=8'b10010010; 4'h6: seg=8'b10000010; 4'h7: seg=8'b11111000;
            4'h8: seg=8'b10000000; 4'h9: seg=8'b10010000; default: seg=8'b11111111;
        endcase
    end endfunction
    localparam [7:0] SEG_BLANK=8'b11111111, SEG_MINUS=8'b10111111, SEG_PLUS=8'b10101111, SEG_g=8'b10010000;

    // heartbeat to blink the decimal point on HEX3 (just to show updates are happening)
    reg [23:0] hbdiv;
    always @(posedge MAX10_CLK1_50) hbdiv <= hbdiv + 24'd1;
    wire hb = hbdiv[20];

    always @* begin
        HEX5 = neg ? SEG_MINUS : SEG_BLANK;       // sign
        HEX4 = (d2==0) ? SEG_BLANK : seg(d2);    // hundreds (blank if 0)
        HEX3 = seg(d1) & 8'b01111111;            // tens with decimal point ON
        HEX2 = seg(d0);                          // ones
        HEX1 = hb ? 8'b01111111 : SEG_BLANK;     // blinking dot (activity)
        HEX0 = SEG_g;                             // 'g'
    end

endmodule
