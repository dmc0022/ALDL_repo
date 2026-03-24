// font4x7.v
// Tiny 4x7 bitmap font, optimized to use far fewer combinational resources.
// Same interface as original: purely combinational, no clock, no latency.

`timescale 1ns/1ps

module font4x7 (
    input  wire [7:0] char,   // ASCII code
    input  wire [2:0] x,      // 0..3
    input  wire [2:0] y,      // 0..6
    output reg        bit
);
    // We encode each glyph as a 4x7 = 28-bit bitmap:
    // row-major, top->bottom, left->right
    // [27:24] = row 0 (x=0..3), [23:20] = row 1, ... [3:0] = row 6
    //
    // This is identical data to what you had before, just packed.

    // Glyph index
    reg [5:0] glyph_idx;
    reg [27:0] glyph;
    integer bit_index;
    reg [2:0] fx, fy;

    // ---------------- ASCII -> glyph index ----------------
    always @* begin
        case (char)
            8'h20: glyph_idx = 6'd0;  // space

            // Digits '0'..'9'
            "0": glyph_idx = 6'd1;
            "1": glyph_idx = 6'd2;
            "2": glyph_idx = 6'd3;
            "3": glyph_idx = 6'd4;
            "4": glyph_idx = 6'd5;
            "5": glyph_idx = 6'd6;
            "6": glyph_idx = 6'd7;
            "7": glyph_idx = 6'd8;
            "8": glyph_idx = 6'd9;
            "9": glyph_idx = 6'd10;

            // 'S','C','O','R','E',':'
            "S": glyph_idx = 6'd11;
            "C": glyph_idx = 6'd12;
            "O": glyph_idx = 6'd13;
            "R": glyph_idx = 6'd14;
            "E": glyph_idx = 6'd15;
            ":": glyph_idx = 6'd16;

            // "PLAY"
            "P": glyph_idx = 6'd17;
            "L": glyph_idx = 6'd18;
            "A": glyph_idx = 6'd19;
            "Y": glyph_idx = 6'd20;

            // "QUIT"
            "Q": glyph_idx = 6'd21;
            "U": glyph_idx = 6'd22;
            "I": glyph_idx = 6'd23;
            "T": glyph_idx = 6'd24;

            // "GIF"
            "G": glyph_idx = 6'd25;
            "F": glyph_idx = 6'd26;

            // "BREAKOUT" letters B,K
            "B": glyph_idx = 6'd27;
            "K": glyph_idx = 6'd28;

            // "HOME" letters H,M
            "H": glyph_idx = 6'd29;
            "M": glyph_idx = 6'd30;
			
			"D": glyph_idx = 6'd31;


            default: glyph_idx = 6'd0; // space
        endcase
    end

    // ---------------- glyph index -> 28-bit bitmap ----------------
    always @* begin
        case (glyph_idx)
            // space
            6'd0:  glyph = 28'b0000_0000_0000_0000_0000_0000_0000;

            // Digits '0'..'9'
            6'd1:  glyph = 28'b1111_1001_1001_1001_1001_1001_1111; // 0
            6'd2:  glyph = 28'b0010_0110_0010_0010_0010_0010_0111; // 1
            6'd3:  glyph = 28'b1110_0001_0001_1110_1000_1000_1111; // 2
            6'd4:  glyph = 28'b1110_0001_0001_1110_0001_0001_1110; // 3
            6'd5:  glyph = 28'b1001_1001_1001_1111_0001_0001_0001; // 4
            6'd6:  glyph = 28'b1111_1000_1000_1110_0001_0001_1110; // 5
            6'd7:  glyph = 28'b1111_1000_1000_1111_1001_1001_1111; // 6
            6'd8:  glyph = 28'b1111_0001_0001_0001_0001_0001_0001; // 7
            6'd9:  glyph = 28'b1111_1001_1001_1111_1001_1001_1111; // 8
            6'd10: glyph = 28'b1111_1001_1001_1111_0001_0001_1111; // 9

            // S C O R E :
            6'd11: glyph = 28'b1111_1000_1000_1111_0001_0001_1111; // S
            6'd12: glyph = 28'b1111_1000_1000_1000_1000_1000_1111; // C
            6'd13: glyph = 28'b1111_1001_1001_1001_1001_1001_1111; // O
            6'd14: glyph = 28'b1110_1001_1001_1110_1010_1001_1001; // R
            6'd15: glyph = 28'b1111_1000_1000_1111_1000_1000_1111; // E
            6'd16: glyph = 28'b0000_0010_0010_0000_0010_0010_0000; // :

            // PLAY
            6'd17: glyph = 28'b1110_1001_1001_1110_1000_1000_1000; // P
            6'd18: glyph = 28'b1000_1000_1000_1000_1000_1000_1111; // L
            6'd19: glyph = 28'b0110_1001_1001_1111_1001_1001_1001; // A
            6'd20: glyph = 28'b1001_1001_1001_0110_0010_0010_0010; // Y

            // QUIT
            6'd21: glyph = 28'b1111_1001_1001_1001_1011_1010_0111; // Q
            6'd22: glyph = 28'b1001_1001_1001_1001_1001_1001_1111; // U
            6'd23: glyph = 28'b1111_0010_0010_0010_0010_0010_1111; // I
            6'd24: glyph = 28'b1111_0010_0010_0010_0010_0010_0010; // T

            // GIF
            6'd25: glyph = 28'b0110_1001_1000_1011_1001_1001_0110; // G
            6'd26: glyph = 28'b1111_1000_1000_1110_1000_1000_1000; // F

            // B, K
            6'd27: glyph = 28'b1110_1001_1001_1110_1001_1001_1110; // B
            6'd28: glyph = 28'b1001_1010_1100_1100_1010_1001_1001; // K

            // H, M
            6'd29: glyph = 28'b1001_1001_1001_1111_1001_1001_1001; // H
            6'd30: glyph = 28'b1001_1111_1111_1001_1001_1001_1001; // M
			
			// D
            6'd31: glyph = 28'b1110_1001_1001_1001_1001_1001_1110; // D


            default: glyph = 28'b0000_0000_0000_0000_0000_0000_0000;
        endcase
    end

    // ---------------- pick the bit for (x,y) ----------------
    always @* begin
        fx = x;
        fy = y;

        if (fx < 4 && fy < 7) begin
            bit_index = fy * 4 + fx;       // 0..27
            bit       = glyph[27 - bit_index];
        end else begin
            bit = 1'b0;
        end
    end

endmodule
