// font4x7.v
// Tiny 4x7 bitmap font, used with 2x scaling for 8x14 text in some renderers,
// and native 4x7 in others.
// Supports digits 0-9 and letters needed for:
// "Score:", "PLAY", "QUIT", "GIF", "CPE 431", "BREAKOUT", "HOME".

`timescale 1ns/1ps

module font4x7 (
    input  wire [7:0] char,   // ASCII code
    input  wire [2:0] x,      // 0..3
    input  wire [2:0] y,      // 0..6
    output reg        bit
);
    reg [3:0] row;

    always @(*) begin
        row = 4'b0000;

        case (char)
            // Space
            8'h20: row = 4'b0000;

            // Digits '0'..'9'
            "0": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1001;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "1": begin
                case (y)
                    0: row = 4'b0010;
                    1: row = 4'b0110;
                    2: row = 4'b0010;
                    3: row = 4'b0010;
                    4: row = 4'b0010;
                    5: row = 4'b0010;
                    6: row = 4'b0111;
                    default: row = 4'b0000;
                endcase
            end
            "2": begin
                case (y)
                    0: row = 4'b1110;
                    1: row = 4'b0001;
                    2: row = 4'b0001;
                    3: row = 4'b1110;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "3": begin
                case (y)
                    0: row = 4'b1110;
                    1: row = 4'b0001;
                    2: row = 4'b0001;
                    3: row = 4'b1110;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b1110;
                    default: row = 4'b0000;
                endcase
            end
            "4": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1111;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b0001;
                    default: row = 4'b0000;
                endcase
            end
            "5": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1110;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b1110;
                    default: row = 4'b0000;
                endcase
            end
            "6": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1111;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "7": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b0001;
                    2: row = 4'b0001;
                    3: row = 4'b0001;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b0001;
                    default: row = 4'b0000;
                endcase
            end
            "8": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1111;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "9": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1111;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end

            // Letters: S C O R E :
            "S": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1111;
                    4: row = 4'b0001;
                    5: row = 4'b0001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "C": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1000;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "O": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1001;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "R": begin
                case (y)
                    0: row = 4'b1110;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1110;
                    4: row = 4'b1010;
                    5: row = 4'b1001;
                    6: row = 4'b1001;
                    default: row = 4'b0000;
                endcase
            end
            "E": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1111;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            ":": begin
                case (y)
                    0: row = 4'b0000;
                    1: row = 4'b0010;
                    2: row = 4'b0010;
                    3: row = 4'b0000;
                    4: row = 4'b0010;
                    5: row = 4'b0010;
                    6: row = 4'b0000;
                    default: row = 4'b0000;
                endcase
            end

            // PLAY
            "P": begin
                case (y)
                    0: row = 4'b1110;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1110;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1000;
                    default: row = 4'b0000;
                endcase
            end
            "L": begin
                case (y)
                    0: row = 4'b1000;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1000;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "A": begin
                case (y)
                    0: row = 4'b0110;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1111;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1001;
                    default: row = 4'b0000;
                endcase
            end
            "Y": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b0110;
                    4: row = 4'b0010;
                    5: row = 4'b0010;
                    6: row = 4'b0010;
                    default: row = 4'b0000;
                endcase
            end

            // QUIT
            "Q": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1001;
                    4: row = 4'b1011;
                    5: row = 4'b1010;
                    6: row = 4'b0111;
                    default: row = 4'b0000;
                endcase
            end
            "U": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1001;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "I": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b0010;
                    2: row = 4'b0010;
                    3: row = 4'b0010;
                    4: row = 4'b0010;
                    5: row = 4'b0010;
                    6: row = 4'b1111;
                    default: row = 4'b0000;
                endcase
            end
            "T": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b0010;
                    2: row = 4'b0010;
                    3: row = 4'b0010;
                    4: row = 4'b0010;
                    5: row = 4'b0010;
                    6: row = 4'b0010;
                    default: row = 4'b0000;
                endcase
            end

            // G I F (for GIF icon)
            "G": begin
                case (y)
                    0: row = 4'b0110;
                    1: row = 4'b1001;
                    2: row = 4'b1000;
                    3: row = 4'b1011;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b0110;
                    default: row = 4'b0000;
                endcase
            end
            "F": begin
                case (y)
                    0: row = 4'b1111;
                    1: row = 4'b1000;
                    2: row = 4'b1000;
                    3: row = 4'b1110;
                    4: row = 4'b1000;
                    5: row = 4'b1000;
                    6: row = 4'b1000;
                    default: row = 4'b0000;
                endcase
            end

            // B, K (for "BREAKOUT")
            "B": begin
                case (y)
                    0: row = 4'b1110;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1110;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1110;
                    default: row = 4'b0000;
                endcase
            end
            "K": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1010;
                    2: row = 4'b1100;
                    3: row = 4'b1100;
                    4: row = 4'b1010;
                    5: row = 4'b1001;
                    6: row = 4'b1001;
                    default: row = 4'b0000;
                endcase
            end

            // H, M (for "HOME")
            "H": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1001;
                    2: row = 4'b1001;
                    3: row = 4'b1111;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1001;
                    default: row = 4'b0000;
                endcase
            end
            "M": begin
                case (y)
                    0: row = 4'b1001;
                    1: row = 4'b1111;
                    2: row = 4'b1111;
                    3: row = 4'b1001;
                    4: row = 4'b1001;
                    5: row = 4'b1001;
                    6: row = 4'b1001;
                    default: row = 4'b0000;
                endcase
            end

            default: row = 4'b0000;
        endcase

        bit = row[3 - x];
    end
endmodule
