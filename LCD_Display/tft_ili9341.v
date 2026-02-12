// tft_ili9341.v
// -----------------------------------------------------------------------------
// ILI9341 SPI TFT Driver (frame-based streaming, RGB565)
//
// This module:
//  - Resets and initializes an ILI9341 over SPI
//  - For each frame:
//      1) Sets address window to full 320x240 (CASET/PASET)
//      2) Issues RAMWR (0x2C)
//      3) Streams exactly 320*240 pixels (RGB565, high byte then low byte)
//
// Pixel handshake (IMPORTANT):
//  - framebufferClk is a 1-cycle "request next pixel" pulse
//  - We do NOT sample framebufferData in the same cycle we request it.
//    We request first, then on the next SPI slot we transmit the bytes.
//    This prevents being 1 pixel behind (which causes shifted/missing UI).
//
// Panel-specific notes (your hardware):
//  - Your module requires INVON (0x21) for correct colors.
//  - MADCTL controls orientation and RGB/BGR ordering.
// -----------------------------------------------------------------------------
//
// Dependency: tft_ili9341_spi_wrapper.v (uses spi_master_byte.v)
// -----------------------------------------------------------------------------

module tft_ili9341(
    input  wire        clk,
    input  wire        reset_n,

    input  wire        tft_sdo,      // unused
    output wire        tft_sck,
    output wire        tft_sdi,
    output wire        tft_dc,
    output reg         tft_reset,
    output wire        tft_cs,

    input  wire [15:0] framebufferData, // RGB565 pixel
    output wire        framebufferClk    // 1-cycle request pulse per pixel
);

    parameter INPUT_CLK_MHZ = 50;

    // Target scan geometry (what we write every frame)
    localparam integer WIDTH  = 320;
    localparam integer HEIGHT = 240;
    localparam [16:0]  PIXELS_PER_FRAME = WIDTH * HEIGHT; // 76800

    // Your panel needs inversion ON for correct colors.
    localparam [7:0] INV_SETTING = 8'h21; // INVON

/* ============================================================================
 * ILI9341 MADCTL (Memory Access Control) Reference
 * Command: 0x36
 *
 * Controls display orientation, scan direction, and RGB/BGR color order.
 * Bit layout:
 *
 *   Bit:   7    6    5    4    3    2    1    0
 *         MY   MX   MV   ML  BGR  MH    -    -
 *
 *   MY  = Row address order (vertical flip)
 *   MX  = Column address order (horizontal flip)
 *   MV  = Row/column exchange (rotation)
 *   ML  = Vertical refresh order
 *   BGR = Color order (1 = BGR, 0 = RGB)
 *   MH  = Horizontal refresh order
 *
 * --------------------------------------------------------------------------
 * Common MADCTL Values (ILI9341)
 * --------------------------------------------------------------------------
 *
 *  Value | Binary    | Orientation        | Color Order | Notes
 * -------+-----------+--------------------+-------------+--------------------
 *  0x20  | 0010_0000 | Landscape          | RGB         | Recommended default
 *  0x28  | 0010_1000 | Landscape          | BGR         | Red/Blue swapped
 *  0xE0  | 1110_0000 | Landscape (180°)   | RGB         | Rotated + flipped
 *  0xE8  | 1110_1000 | Landscape (180°)   | BGR         | Rotated + BGR
 *
 *  0x00  | 0000_0000 | Portrait           | RGB         | Rarely used
 *  0x48  | 0100_1000 | Portrait           | BGR         | Many breakout defaults
 *
 * --------------------------------------------------------------------------
 * Notes:
 *  - For 320x240 landscape rendering, MV MUST be 1.
 *  - If colors appear swapped (red <-> blue), toggle the BGR bit.
 *  - Address window (CASET/PASET) must match orientation.
 *
 * Example:
 *   localparam [7:0] MADCTL_VALUE = 8'h20; // Landscape, RGB565
 * ============================================================================
 */

    localparam [7:0] MADCTL_VALUE = 8'h28;

    // -------------------------------------------------------------------------
    // SPI interface
    // -------------------------------------------------------------------------
    reg  [8:0] spiData;      // {dc, byte}
    reg        spiDataSet;
    wire       spiIdle;

    tft_ili9341_spi_wrapper #(
        // SPI clock divider (half-period). With clk=50MHz:
        //   CLK_DIV=25 -> ~1 MHz (safe init)
        //   CLK_DIV=2  -> ~12.5 MHz (fast streaming)
		
		//   CLK_DIV=1  -> ~25Mhz (GIGA FPS MODE)
        .CLK_DIV(16'd1)
    ) spi (
        .spiClk        (clk),
        .reset_n       (reset_n),
        .data          (spiData),
        .dataAvailable (spiDataSet),
        .tft_sck       (tft_sck),
        .tft_sdi       (tft_sdi),
        .tft_dc        (tft_dc),
        .tft_cs        (tft_cs),
        .idle          (spiIdle)
    );

// Pixel request pulse
    reg fb_req;
    assign framebufferClk = fb_req;

    // -------------------------------------------------------------------------
    // Init sequence (common ILI9341 init + your required settings)
    // -------------------------------------------------------------------------
    localparam INIT_SEQ_LEN = 56;
    reg [5:0] initSeqCounter;
    reg [8:0] INIT_SEQ [0:INIT_SEQ_LEN-1];

    integer i;
    initial begin
        for (i = 0; i < INIT_SEQ_LEN; i = i + 1)
            INIT_SEQ[i] = 9'h000;

        INIT_SEQ[0]  = {1'b0, 8'h28};   // DISPOFF
        INIT_SEQ[1]  = {1'b0, 8'h11};   // SLEEPOUT (we also delay in state machine)

        // (Some sequences put delays between blocks; our state machine delays cover this.)
        INIT_SEQ[2]  = {1'b0, 8'hCF};
        INIT_SEQ[3]  = {1'b1, 8'h00};
        INIT_SEQ[4]  = {1'b1, 8'h83};
        INIT_SEQ[5]  = {1'b1, 8'h30};

        INIT_SEQ[6]  = {1'b0, 8'hED};
        INIT_SEQ[7]  = {1'b1, 8'h64};
        INIT_SEQ[8]  = {1'b1, 8'h03};
        INIT_SEQ[9]  = {1'b1, 8'h12};
        INIT_SEQ[10] = {1'b1, 8'h81};

        INIT_SEQ[11] = {1'b0, 8'hE8};
        INIT_SEQ[12] = {1'b1, 8'h85};
        INIT_SEQ[13] = {1'b1, 8'h01};
        INIT_SEQ[14] = {1'b1, 8'h79};

        INIT_SEQ[15] = {1'b0, 8'hCB};
        INIT_SEQ[16] = {1'b1, 8'h39};
        INIT_SEQ[17] = {1'b1, 8'h2C};
        INIT_SEQ[18] = {1'b1, 8'h00};
        INIT_SEQ[19] = {1'b1, 8'h34};
        INIT_SEQ[20] = {1'b1, 8'h02};

        INIT_SEQ[21] = {1'b0, 8'hF7};
        INIT_SEQ[22] = {1'b1, 8'h20};

        INIT_SEQ[23] = {1'b0, 8'hEA};
        INIT_SEQ[24] = {1'b1, 8'h00};
        INIT_SEQ[25] = {1'b1, 8'h00};

        INIT_SEQ[26] = {1'b0, 8'hC0};
        INIT_SEQ[27] = {1'b1, 8'h26};

        INIT_SEQ[28] = {1'b0, 8'hC1};
        INIT_SEQ[29] = {1'b1, 8'h11};

        INIT_SEQ[30] = {1'b0, 8'hC5};
        INIT_SEQ[31] = {1'b1, 8'h35};
        INIT_SEQ[32] = {1'b1, 8'h3E};

        INIT_SEQ[33] = {1'b0, 8'hC7};
        INIT_SEQ[34] = {1'b1, 8'hBE};

        INIT_SEQ[35] = {1'b0, 8'h3A};   // COLMOD
        INIT_SEQ[36] = {1'b1, 8'h55};   // 16-bit RGB565

        INIT_SEQ[37] = {1'b0, 8'h36};   // MADCTL
        INIT_SEQ[38] = {1'b1, MADCTL_VALUE};

        INIT_SEQ[39] = {1'b0, 8'hB1};
        INIT_SEQ[40] = {1'b1, 8'h00};
        INIT_SEQ[41] = {1'b1, 8'h1B};

        INIT_SEQ[42] = {1'b0, 8'h26};
        INIT_SEQ[43] = {1'b1, 8'h01};

        INIT_SEQ[44] = {1'b0, 8'h51};
        INIT_SEQ[45] = {1'b1, 8'hFF};

        INIT_SEQ[46] = {1'b0, 8'hB7};
        INIT_SEQ[47] = {1'b1, 8'h07};

        INIT_SEQ[48] = {1'b0, 8'hB6};
        INIT_SEQ[49] = {1'b1, 8'h0A};
        INIT_SEQ[50] = {1'b1, 8'h82};
        INIT_SEQ[51] = {1'b1, 8'h27};
        INIT_SEQ[52] = {1'b1, 8'h00};

        // INV_SETTING default value makes color inverted
        INIT_SEQ[53] = {1'b0, INV_SETTING}; // INVON (0x21)

        INIT_SEQ[54] = {1'b0, 8'h29};   // DISPON
        INIT_SEQ[55] = {1'b0, 8'h00};   // filler
    end

    // -------------------------------------------------------------------------
    // Per-frame setup: always set full 320x240 window, then RAMWR
    // -------------------------------------------------------------------------
    localparam FRAME_SEQ_LEN = 11;
    reg [3:0] frameSeqCounter;
    reg [8:0] FRAME_SEQ [0:FRAME_SEQ_LEN-1];

    initial begin
        // CASET (0x2A): X = 0..319
        FRAME_SEQ[0]  = {1'b0, 8'h2A};
        FRAME_SEQ[1]  = {1'b1, 8'h00};
        FRAME_SEQ[2]  = {1'b1, 8'h00};
        FRAME_SEQ[3]  = {1'b1, 8'h01};
        FRAME_SEQ[4]  = {1'b1, 8'h3F};

        // PASET (0x2B): Y = 0..239
        FRAME_SEQ[5]  = {1'b0, 8'h2B};
        FRAME_SEQ[6]  = {1'b1, 8'h00};
        FRAME_SEQ[7]  = {1'b1, 8'h00};
        FRAME_SEQ[8]  = {1'b1, 8'h00};
        FRAME_SEQ[9]  = {1'b1, 8'hEF};

        // RAMWR (0x2C)
        FRAME_SEQ[10] = {1'b0, 8'h2C};
    end

    // -------------------------------------------------------------------------
    // State machine (byte-level pacing driven by spiIdle)
    // -------------------------------------------------------------------------
    localparam [3:0]
        STATE_START         = 4'd0,
        STATE_HOLD_RESET    = 4'd1,
        STATE_WAIT_POWERUP  = 4'd2,
        STATE_SEND_INIT_SEQ = 4'd3,
        STATE_FRAME_SETUP   = 4'd4,
        STATE_REQ_PIXEL     = 4'd5,
        STATE_WAIT_PIXEL    = 4'd6,
        STATE_SEND_HI       = 4'd7,
        STATE_SEND_LO       = 4'd8;

    reg [3:0]  state;
    reg [23:0] remainingDelayTicks;
    reg [16:0] pixelCount;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tft_reset           <= 1'b1;
            spiData             <= 9'd0;
            spiDataSet          <= 1'b0;
            fb_req              <= 1'b0;

            initSeqCounter      <= 6'd0;
            frameSeqCounter     <= 4'd0;
            remainingDelayTicks <= 24'd0;
            state               <= STATE_START;

            pixelCount          <= 17'd0;

        end else begin
            spiDataSet <= 1'b0;
            fb_req     <= 1'b0;

            if (remainingDelayTicks > 0) begin
                remainingDelayTicks <= remainingDelayTicks - 24'd1;

            end else if (spiIdle && !spiDataSet) begin
                case (state)

                    STATE_START: begin
                        // Assert reset low briefly
                        tft_reset           <= 1'b0;
                        remainingDelayTicks <= INPUT_CLK_MHZ * 10;      // ~10us
                        state               <= STATE_HOLD_RESET;
                    end

                    STATE_HOLD_RESET: begin
                        // Release reset and wait for panel power-up
                        tft_reset           <= 1'b1;
                        remainingDelayTicks <= INPUT_CLK_MHZ * 120000;  // ~120ms
                        state               <= STATE_WAIT_POWERUP;
                    end

                    STATE_WAIT_POWERUP: begin
                        // Additional wait (conservative)
                        remainingDelayTicks <= INPUT_CLK_MHZ * 5000;    // ~5ms
                        state               <= STATE_SEND_INIT_SEQ;
                    end

                    STATE_SEND_INIT_SEQ: begin
                        if (initSeqCounter < INIT_SEQ_LEN) begin
                            spiData        <= INIT_SEQ[initSeqCounter];
                            spiDataSet     <= 1'b1;
                            initSeqCounter <= initSeqCounter + 6'd1;
                        end else begin
                            frameSeqCounter <= 4'd0;
                            pixelCount      <= 17'd0;
                            state           <= STATE_FRAME_SETUP;
                        end
                    end

                    STATE_FRAME_SETUP: begin
                        if (frameSeqCounter < FRAME_SEQ_LEN) begin
                            spiData         <= FRAME_SEQ[frameSeqCounter];
                            spiDataSet      <= 1'b1;
                            frameSeqCounter <= frameSeqCounter + 4'd1;
                        end else begin
                            pixelCount <= 17'd0;
                            state      <= STATE_REQ_PIXEL;
                        end
                    end

                    // STEP A: request next pixel from renderer/top
                    STATE_REQ_PIXEL: begin
                        fb_req <= 1'b1; // 1-cycle request pulse
                        state  <= STATE_WAIT_PIXEL;
                    end

                    

                    // STEP A.5: wait one full clk so renderers can see framebufferClk
                    // and update framebufferData before we sample it.
                    STATE_WAIT_PIXEL: begin
                        state <= STATE_SEND_HI;
                    end

					// STEP B: send high byte of RGB565
                    STATE_SEND_HI: begin
                        spiData    <= {1'b1, framebufferData[15:8]};
                        spiDataSet <= 1'b1;
                        state      <= STATE_SEND_LO;
                    end

                    // STEP C: send low byte, count pixel
                    STATE_SEND_LO: begin
                        spiData    <= {1'b1, framebufferData[7:0]};
                        spiDataSet <= 1'b1;

                        if (pixelCount == (PIXELS_PER_FRAME - 1)) begin
                            frameSeqCounter <= 4'd0;
                            state           <= STATE_FRAME_SETUP;
                        end else begin
                            pixelCount <= pixelCount + 17'd1;
                            state      <= STATE_REQ_PIXEL;
                        end
                    end

                    default: state <= STATE_START;
                endcase
            end
        end
    end

endmodule