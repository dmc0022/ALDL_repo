`timescale 1ns/1ps
`default_nettype none

//==============================================================================
// A.L.D.L. Lab 2 - Phase I Top File
//------------------------------------------------------------------------------
// Module Name:
//   aldl_lab2_phase1_top
//
// Purpose:
//   This is the Phase I top-level file for the TMP117 lab. The goal here is simply 
//   to prove that the FPGA is communicating with the temperature sensor and that 
//   the TMP117 reader module is returning data.
//
// What this top file does:
//   1. Instantiates the provided tmp117_reader module.
//   2. Reads the raw 16-bit sensor word coming back from the TMP117 path.
//   3. Displays the raw word directly on the 7-segment displays as hex.
//   4. Exposes reader/debug state on LEDs so students can see progress.
//
//
// Notes for instructors/students:
//   - The current tmp117_reader used here returns the raw register data from the
//   temperature register. In order to complete phase I, the tmp117_reader file 
//   must be modified. 
//         UPDATE localparam [7:0] REG_TEMPERATURE = 8'h00; TO 0X0F. 
// 
//   - This value 0X0F will read this register address and should output 0x117. 
//==============================================================================

module aldl_lab2_phase1_top (
    input  wire       clk_50,
    input  wire       reset_n,

    // TMP117 I2C bus
    inout  wire       TMP_SCL,
    inout  wire       TMP_SDA,

    // 7-segment displays
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,

    // Debug LEDs
    output wire [9:0] LEDR
);

    //==========================================================================
    // Reader output signals
    //--------------------------------------------------------------------------
    // raw_temp_word:
    //   The 16-bit raw value returned by tmp117_reader. In this lab flow we use
    //   it directly during Phase I as proof that communication is happening.
    //
    // tx_done:
    //   Pulses when a full read transaction completes.
    //
    // busy:
    //   High while the reader is in the middle of a transaction.
    //
    // busy_seen / complete_seen:
    //   Sticky-style debug indicators coming from the reader. These are very
    //   useful in lab because they show whether the lower-level transaction
    //   engine has ever actually started/completed.
    //==========================================================================
    wire [15:0] raw_temp_word;
    wire        busy;
    wire        tx_done;
    wire [2:0]  dbg_state;
    wire        busy_seen;
    wire        complete_seen;
    wire [3:0]  latched_master_state;
    wire [1:0]  latched_master_phase;
    wire [3:0]  latched_master_bit;
    wire [7:0]  latched_master_byte;
    wire        latched_master_last_ack;

    //==========================================================================
    // TMP117 reader instantiation
    //--------------------------------------------------------------------------
    // This is the same sensor-read block used in later phases. For Phase I we
    // simply expose its outputs directly rather than converting the result.
    //
    // Parameters:
    //   I2C_FREQ_HZ   = 50 kHz  -> intentionally conservative for bring-up
    //   TMP117_ADDR   = 0x48    -> default SparkFun TMP117 / Qwiic address
    //   STARTUP_TICKS = delay after reset before first transaction
    //   POLL_DIVIDER  = sets the interval between repeated reads
    //==========================================================================
    tmp117_reader #(
        .CLK_FREQ_HZ  (50_000_000),
        .I2C_FREQ_HZ  (50_000),
        .TMP117_ADDR  (7'h48),
        .STARTUP_TICKS(24'd5_000_000),
        .POLL_DIVIDER (24'd10_000_000)
    ) u_tmp117 (
        .clk_50                  (clk_50),
        .reset_n                 (reset_n),
        .tmp_scl                 (TMP_SCL),
        .tmp_sda                 (TMP_SDA),
        .raw_id                  (raw_temp_word),
        .busy                    (busy),
        .tx_done                 (tx_done),
        .dbg_state               (dbg_state),
        .busy_seen               (busy_seen),
        .complete_seen           (complete_seen),
        .latched_master_state    (latched_master_state),
        .latched_master_phase    (latched_master_phase),
        .latched_master_bit      (latched_master_bit),
        .latched_master_byte     (latched_master_byte),
        .latched_master_last_ack (latched_master_last_ack)
    );

    //==========================================================================
    // Display-valid latch
    //--------------------------------------------------------------------------
    // We capture whether a completed transaction has EVER occurred since reset.
    //   - Before the first successful transaction, the HEX displays stay blank.
    //   - After the first completed transaction, the HEX displays stay enabled.
    //
    // That makes it easy to distinguish:
    //   "The sensor has not responded yet"
    // from
    //   "The sensor responded and I now have data."
    //==========================================================================
    reg display_valid;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            display_valid <= 1'b0;
        else if (tx_done)
            display_valid <= 1'b1;
    end

    //==========================================================================
    // Phase I 7-segment strategy
    //--------------------------------------------------------------------------
    // In this phase we show the RAW 16-bit sensor word directly in hex:
    //
    //   HEX3 HEX2 HEX1 HEX0 = raw_temp_word[15:0]
    //
    //==========================================================================
    localparam [6:0] SEG_BLANK = 7'b1111111;

    assign HEX5 = SEG_BLANK;
    assign HEX4 = SEG_BLANK;
    assign HEX3 = display_valid ? hex7(raw_temp_word[15:12]) : SEG_BLANK;
    assign HEX2 = display_valid ? hex7(raw_temp_word[11:8])  : SEG_BLANK;
    assign HEX1 = display_valid ? hex7(raw_temp_word[7:4])   : SEG_BLANK;
    assign HEX0 = display_valid ? hex7(raw_temp_word[3:0])   : SEG_BLANK;

    //==========================================================================
    // LED debug mapping
    //--------------------------------------------------------------------------
    //
    // Suggested interpretation:
    //   LEDR[0] = busy_seen         -> transaction has started at least once
    //   LEDR[1] = complete_seen     -> transaction has completed at least once
    //   LEDR[2] = display_valid     -> HEX display is now showing live data
    //   LEDR[6:3] = master state    -> captured low-level state machine state
    //   LEDR[8:7] = master phase    -> sub-phase from lower-level I2C master
    //   LEDR[9] = wrapper dbg bit   -> quick activity/status indicator
    //==========================================================================
    assign LEDR[0]   = busy_seen;
    assign LEDR[1]   = complete_seen;
    assign LEDR[2]   = display_valid;
    assign LEDR[6:3] = latched_master_state;
    assign LEDR[8:7] = latched_master_phase;
    assign LEDR[9]   = dbg_state[0];

    //==========================================================================
    // Local 4-bit hex to 7-segment decoder
    //--------------------------------------------------------------------------
    //
    // The DE10-Lite 7-segment displays are active-low.
    //==========================================================================
    function [6:0] hex7(input [3:0] v);
        begin
            case (v)
                4'h0: hex7 = 7'b1000000;
                4'h1: hex7 = 7'b1111001;
                4'h2: hex7 = 7'b0100100;
                4'h3: hex7 = 7'b0110000;
                4'h4: hex7 = 7'b0011001;
                4'h5: hex7 = 7'b0010010;
                4'h6: hex7 = 7'b0000010;
                4'h7: hex7 = 7'b1111000;
                4'h8: hex7 = 7'b0000000;
                4'h9: hex7 = 7'b0010000;
                4'hA: hex7 = 7'b0001000;
                4'hB: hex7 = 7'b0000011;
                4'hC: hex7 = 7'b1000110;
                4'hD: hex7 = 7'b0100001;
                4'hE: hex7 = 7'b0000110;
                default: hex7 = 7'b0001110; // F
            endcase
        end
    endfunction

endmodule

`default_nettype wire
