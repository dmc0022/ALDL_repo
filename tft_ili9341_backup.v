// tft_ili9341.v
// Simple frame-buffer based driver for the ILI9341 TFT module (Verilog-2001)

module tft_ili9341(
    input  wire        clk,
    input  wire        reset_n,       // NEW: active-low global reset
    input  wire        tft_sdo,       // not used in this simple driver
    output wire        tft_sck,
    output wire        tft_sdi,
    output wire        tft_dc,
    output reg         tft_reset,
    output wire        tft_cs,
    input  wire [15:0] framebufferData,
    output wire        framebufferClk
);

    // Adjust to your input clock freq in MHz
    parameter INPUT_CLK_MHZ = 50;

    // SPI interface signals
    reg  [8:0] spiData;
    reg        spiDataSet;
    wire       spiIdle;

    // Framebuffer byte selector (high vs low byte of RGB565)
    reg  frameBufferLowNibble;
    assign framebufferClk = ~frameBufferLowNibble;

    // Init sequence storage
    // Each entry: {dc, byte}  dc=0 → command, dc=1 → data
    localparam INIT_SEQ_LEN = 54;
    reg [5:0] initSeqCounter;
    reg [8:0] INIT_SEQ [0:INIT_SEQ_LEN-1];

    // State machine encoding
    localparam STATE_START         = 3'd0;
    localparam STATE_HOLD_RESET    = 3'd1;
    localparam STATE_WAIT_POWERUP  = 3'd2;
    localparam STATE_SEND_INIT_SEQ = 3'd3;
    localparam STATE_LOOP          = 3'd4;

    reg [2:0]  state;
    reg [23:0] remainingDelayTicks;

    // ----------------------------------------------------------------
    // Instantiate SPI engine
    // ----------------------------------------------------------------
    tft_ili9341_spi spi (
        .spiClk        (clk),
        .data          (spiData),
        .dataAvailable (spiDataSet),
        .tft_sck       (tft_sck),
        .tft_sdi       (tft_sdi),
        .tft_dc        (tft_dc),
        .tft_cs        (tft_cs),
        .idle          (spiIdle)
    );

    // ----------------------------------------------------------------
    // INIT_SEQ contents (only the table is in the initial block)
    // ----------------------------------------------------------------
    integer i;
    initial begin
        // Clear INIT_SEQ (not strictly necessary)
        for (i = 0; i < INIT_SEQ_LEN; i = i + 1) begin
            INIT_SEQ[i] = 9'h000;
        end

        // -------------------------------
        // ILI9341 INIT SEQUENCE
        // Each entry = {DC, BYTE}
        // -------------------------------

        // 0: Display OFF
        INIT_SEQ[0]  = {1'b0, 8'h28};   // CMD: DISPOFF

        // Power control B (CFh)
        INIT_SEQ[1]  = {1'b0, 8'hCF};
        INIT_SEQ[2]  = {1'b1, 8'h00};
        INIT_SEQ[3]  = {1'b1, 8'h83};
        INIT_SEQ[4]  = {1'b1, 8'h30};

        // Power on sequence control (EDh)
        INIT_SEQ[5]  = {1'b0, 8'hED};
        INIT_SEQ[6]  = {1'b1, 8'h64};
        INIT_SEQ[7]  = {1'b1, 8'h03};
        INIT_SEQ[8]  = {1'b1, 8'h12};
        INIT_SEQ[9]  = {1'b1, 8'h81};

        // Driver timing control A (E8h)
        INIT_SEQ[10] = {1'b0, 8'hE8};
        INIT_SEQ[11] = {1'b1, 8'h85};
        INIT_SEQ[12] = {1'b1, 8'h01};
        INIT_SEQ[13] = {1'b1, 8'h79};

        // Power control A (CBh)
        INIT_SEQ[14] = {1'b0, 8'hCB};
        INIT_SEQ[15] = {1'b1, 8'h39};
        INIT_SEQ[16] = {1'b1, 8'h2C};
        INIT_SEQ[17] = {1'b1, 8'h00};
        INIT_SEQ[18] = {1'b1, 8'h34};
        INIT_SEQ[19] = {1'b1, 8'h02};

        // Pump ratio control (F7h)
        INIT_SEQ[20] = {1'b0, 8'hF7};
        INIT_SEQ[21] = {1'b1, 8'h20};

        // Driver timing control B (EAh)
        INIT_SEQ[22] = {1'b0, 8'hEA};
        INIT_SEQ[23] = {1'b1, 8'h00};
        INIT_SEQ[24] = {1'b1, 8'h00};

        // Power control 1 (C0h)
        INIT_SEQ[25] = {1'b0, 8'hC0};
        INIT_SEQ[26] = {1'b1, 8'h26};

        // Power control 2 (C1h)
        INIT_SEQ[27] = {1'b0, 8'hC1};
        INIT_SEQ[28] = {1'b1, 8'h11};

        // VCOM control 1 (C5h)
        INIT_SEQ[29] = {1'b0, 8'hC5};
        INIT_SEQ[30] = {1'b1, 8'h35};
        INIT_SEQ[31] = {1'b1, 8'h3E};

        // VCOM control 2 (C7h)
        INIT_SEQ[32] = {1'b0, 8'hC7};
        INIT_SEQ[33] = {1'b1, 8'hBE};

        // COLMOD: Pixel Format Set (3Ah)
        INIT_SEQ[34] = {1'b0, 8'h3A};
        INIT_SEQ[35] = {1'b1, 8'h55};   // 16-bit

        // MADCTL: Memory Access Control (36h)
        INIT_SEQ[36] = {1'b0, 8'h36};
        INIT_SEQ[37] = {1'b1, 8'h48};   // MX=1, BGR=1 (landscape + BGR)

        // Frame Rate Control (B1h)
        INIT_SEQ[38] = {1'b0, 8'hB1};
        INIT_SEQ[39] = {1'b1, 8'h00};
        INIT_SEQ[40] = {1'b1, 8'h1B};

        // Gamma function select (26h)
        INIT_SEQ[41] = {1'b0, 8'h26};
        INIT_SEQ[42] = {1'b1, 8'h01};

        // Write Display Brightness (51h)
        INIT_SEQ[43] = {1'b0, 8'h51};
        INIT_SEQ[44] = {1'b1, 8'hFF};

        // Display function control (B7h)
        INIT_SEQ[45] = {1'b0, 8'hB7};
        INIT_SEQ[46] = {1'b1, 8'h07};

        // Display function control (B6h)
        INIT_SEQ[47] = {1'b0, 8'hB6};
        INIT_SEQ[48] = {1'b1, 8'h0A};
        INIT_SEQ[49] = {1'b1, 8'h82};
        INIT_SEQ[50] = {1'b1, 8'h27};
        INIT_SEQ[51] = {1'b1, 8'h00};

        // Display ON (29h)
        INIT_SEQ[52] = {1'b0, 8'h29};

        // Memory Write (2Ch)
        INIT_SEQ[53] = {1'b0, 8'h2C};
    end

    // ----------------------------------------------------------------
    // State machine with delay + idle support (used for initialization)
    // ----------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Reset all control registers to power-up state
            tft_reset            <= 1'b1;       // inactive (will be pulled low next in STATE_START)
            spiData              <= 9'b0;
            spiDataSet           <= 1'b0;
            frameBufferLowNibble <= 1'b1;
            initSeqCounter       <= 6'd0;
            remainingDelayTicks  <= 24'd0;
            state                <= STATE_START;
        end else begin
            // clear data flag first
            spiDataSet <= 1'b0;

            // always decrement delay ticks
            if (remainingDelayTicks > 0) begin
                remainingDelayTicks <= remainingDelayTicks - 24'd1;
            end
            else if (spiIdle && !spiDataSet) begin
                // only advance state machine when SPI is idle and
                // we didn't just send a new byte
                case (state)
                    // 1) Assert reset low briefly
                    STATE_START: begin
                        tft_reset           <= 1'b0;
                        remainingDelayTicks <= INPUT_CLK_MHZ * 10;     // ~10us
                        state               <= STATE_HOLD_RESET;
                    end

                    // 2) Release reset and wait for panel to power up
                    STATE_HOLD_RESET: begin
                        tft_reset           <= 1'b1;
                        remainingDelayTicks <= INPUT_CLK_MHZ * 120000; // ~120ms
                        state               <= STATE_WAIT_POWERUP;
                        frameBufferLowNibble<= 1'b0;                   // request first pixel
                    end

                    // 3) Sleep Out (11h), then wait a bit before init sequence
                    STATE_WAIT_POWERUP: begin
                        spiData             <= {1'b0, 8'h11};          // CMD: SLEEPOUT
                        spiDataSet          <= 1'b1;
                        remainingDelayTicks <= INPUT_CLK_MHZ * 5000;   // ~5ms
                        state               <= STATE_SEND_INIT_SEQ;
                        frameBufferLowNibble<= 1'b1;
                    end

                    // 4) Send the init sequence above
                    STATE_SEND_INIT_SEQ: begin
                        if (initSeqCounter < INIT_SEQ_LEN) begin
                            spiData        <= INIT_SEQ[initSeqCounter];
                            spiDataSet     <= 1'b1;
                            initSeqCounter <= initSeqCounter + 6'd1;
                        end else begin
                            // Init done; small extra delay then go into FB loop
                            state               <= STATE_LOOP;
                            remainingDelayTicks <= INPUT_CLK_MHZ * 10000; // ~10ms
                        end
                    end

                    // 5) Framebuffer loop – continuously send pixel data
                    default: begin
                        // Send high byte then low byte of RGB565/BGR565 pixel
                        if (!frameBufferLowNibble)
                            spiData <= {1'b1, framebufferData[15:8]};
                        else
                            spiData <= {1'b1, framebufferData[7:0]};

                        spiDataSet           <= 1'b1;
                        frameBufferLowNibble <= ~frameBufferLowNibble;
                    end
                endcase
            end
        end
    end

endmodule
