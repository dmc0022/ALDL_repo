`timescale 1ns/1ps
`default_nettype none

//==============================================================================
// A.L.D.L. Lab 2 - Phase II Top File
//------------------------------------------------------------------------------
// Module Name:
//   aldl_lab2_phase2_top
//
// Purpose:
//   This is the Phase II top-level file for the TMP117 lab. This phase moves
//   beyond "raw communication proof" and introduces the key fixed-point math
//   used to convert the sensor's raw output into degrees Celsius.
//
// Recommended learning objective for Phase II:
//   "Can I correctly interpret the TMP117 measurement and display temperature?"
//
// What this top file does:
//   1. Instantiates the provided tmp117_reader module.
//   2. Receives the raw 16-bit TMP117 reading.
//   3. Converts the raw sensor value into centi-degrees Celsius.
//   4. Displays the integer temperature on the 7-segment displays.
//   5. Leaves the LCD out of the design so the conversion logic can be studied
//      and debugged in isolation.
//
// Why Phase II still avoids the LCD:
//   - Students should focus on conversion math first.
//   - The 7-segment display is enough to prove the temperature value is correct.
//   - This keeps compile time short and the project easier to debug.
//==============================================================================

module aldl_lab2_phase2_top (
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
    // Reader outputs
    //--------------------------------------------------------------------------
    // raw_temp_word:
    //   Raw 16-bit temperature register as returned by the reader.
    //
    // We keep the same reader interface from Phase I so students can clearly see
    // that Phase II is built on top of the same communication foundation.
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
    // Valid-data latch
    //--------------------------------------------------------------------------
    // As in Phase I, we wait until the first completed transaction before we
    // enable the visible display.
    //==========================================================================
    reg temp_display_valid;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n)
            temp_display_valid <= 1'b0;
        else if (tx_done)
            temp_display_valid <= 1'b1;
    end

    //==========================================================================
    // Phase II learning focus: conversion math
    //--------------------------------------------------------------------------
    // TMP117 format:
    //   The TMP117 temperature register uses a scale factor of:
    //
    //       1 LSB = 0.0078125 degrees C = 1/128 degrees C
    //
    // To avoid floating-point hardware in FPGA logic, we use fixed-point math.
    //
    // Step 1: convert to centi-degrees Celsius (hundredths of a degree)
    //
    //   temp_centi_c = raw * 100 / 128
    //
    // Simplify:
    //
    //   temp_centi_c = raw * 25 / 32
    //
    // Example:
    //   If the sensor is approximately 26.00 C, then temp_centi_c ~ 2600.
    //
    // This is an excellent teaching point because students see how FPGA designs
    // often replace floating-point with exact integer arithmetic.
    //==========================================================================
    wire signed [15:0] raw_temp_signed = raw_temp_word;
    wire signed [31:0] temp_centi_c_long = raw_temp_signed * 32'sd25;
    wire signed [15:0] temp_centi_c = temp_centi_c_long / 32'sd32;

    //==========================================================================
    // Split the converted value into sign and integer digits
    //--------------------------------------------------------------------------
    // In this phase we display only the WHOLE number of degrees Celsius on the
    // 7-segment display to keep the checkoff simple.
    //
    // Example:
    //   temp_centi_c = 2534 -> display 25 C
    //
    // temp_negative:
    //   High if the converted temperature is negative.
    //
    // temp_abs_centi:
    //   Absolute value in centi-degrees, used to extract decimal digits.
    //
    // temp_whole_c:
    //   Integer temperature in degrees C (fractional part removed).
    //==========================================================================
    wire        temp_negative = temp_centi_c[15];
    wire [15:0] temp_abs_centi = temp_negative ? -temp_centi_c : temp_centi_c;
    wire [15:0] temp_whole_c   = temp_abs_centi / 16'd100;

    wire [3:0] temp_ones     = temp_whole_c % 10;
    wire [3:0] temp_tens     = (temp_whole_c / 10) % 10;
    wire [3:0] temp_hundreds = (temp_whole_c / 100) % 10;

    wire show_hundreds = (temp_whole_c >= 100);
    wire show_tens     = (temp_whole_c >= 10);

    //==========================================================================
    // 7-segment display format
    //--------------------------------------------------------------------------
    // Format used:
    //
    //   [HEX5 HEX4 HEX3 HEX2 HEX1 HEX0]
    //   [blank blank sign/100s 10s 1s C]
    //
    // Examples:
    //   26 C  -> HEX2=2, HEX1=6, HEX0=C
    //   -5 C  -> HEX3='-', HEX1=5, HEX0=C
    //==========================================================================
    localparam [6:0] SEG_BLANK = 7'b1111111;
    localparam [6:0] SEG_MINUS = 7'b0111111;
    localparam [6:0] SEG_C     = 7'b1000110;

    assign HEX5 = SEG_BLANK;
    assign HEX4 = SEG_BLANK;
    assign HEX3 = temp_negative ? SEG_MINUS : (show_hundreds ? hex7(temp_hundreds) : SEG_BLANK);
    assign HEX2 = show_hundreds ? hex7(temp_tens) : (show_tens ? hex7(temp_tens) : SEG_BLANK);
    assign HEX1 = temp_display_valid ? hex7(temp_ones) : SEG_BLANK;
    assign HEX0 = temp_display_valid ? SEG_C : SEG_BLANK;

    //==========================================================================
    // Debug LEDs
    //--------------------------------------------------------------------------
    // We keep the same debug LED strategy as Phase I so students can continue to
    // monitor the communication path while they work on conversion.
    //==========================================================================
    assign LEDR[0]   = busy_seen;
    assign LEDR[1]   = complete_seen;
    assign LEDR[2]   = temp_display_valid;
    assign LEDR[6:3] = latched_master_state;
    assign LEDR[8:7] = latched_master_phase;
    assign LEDR[9]   = dbg_state[0];

    //==========================================================================
    // Local 4-bit hex to 7-segment decoder
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
