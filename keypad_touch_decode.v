// ============================================================
// keypad_touch_decode.v
// ------------------------------------------------------------
// Converts touch coordinates into hex value (Layout A).
// Generates key_pulse on rising edge of touch.
// ============================================================

module keypad_touch_decode #(
    parameter KP_X0  = 28,
    parameter KP_Y0  = 30,
    parameter KEY_W  = 60,
    parameter KEY_H  = 45,
    parameter GAP    = 8
)(
    input  wire        clk,
    input  wire        reset_n,

    input  wire        touch_valid,
    input  wire [9:0]  touch_x,    // 0-319
    input  wire [8:0]  touch_y,    // 0-239

    output reg         key_pulse,
    output reg  [3:0]  key_value
);

    reg touch_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            touch_d <= 1'b0;
        else
            touch_d <= touch_valid;
    end

    wire touch_press = touch_valid & ~touch_d;

    wire [9:0] x_rel = touch_x - KP_X0;
    wire [8:0] y_rel = touch_y - KP_Y0;

    wire [1:0] col = x_rel / (KEY_W + GAP);
    wire [1:0] row = y_rel / (KEY_H + GAP);

    wire in_x = (touch_x >= KP_X0) &&
                (touch_x < (KP_X0 + 4*KEY_W + 3*GAP));

    wire in_y = (touch_y >= KP_Y0) &&
                (touch_y < (KP_Y0 + 4*KEY_H + 3*GAP));

    wire in_keypad = in_x && in_y;

    wire [3:0] idx = {row, col}; // row*4 + col

    function [3:0] map_idx;
        input [3:0] i;
        begin
            case (i)
                4'd0:  map_idx = 4'h1;
                4'd1:  map_idx = 4'h2;
                4'd2:  map_idx = 4'h3;
                4'd3:  map_idx = 4'hA;

                4'd4:  map_idx = 4'h4;
                4'd5:  map_idx = 4'h5;
                4'd6:  map_idx = 4'h6;
                4'd7:  map_idx = 4'hB;

                4'd8:  map_idx = 4'h7;
                4'd9:  map_idx = 4'h8;
                4'd10: map_idx = 4'h9;
                4'd11: map_idx = 4'hC;

                4'd12: map_idx = 4'hE;
                4'd13: map_idx = 4'h0;
                4'd14: map_idx = 4'hF;
                4'd15: map_idx = 4'hD;

                default: map_idx = 4'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            key_value <= 4'h0;
            key_pulse <= 1'b0;
        end
        else begin
            key_pulse <= 1'b0;

            if (touch_press && in_keypad) begin
                key_value <= map_idx(idx);
                key_pulse <= 1'b1;
            end
        end
    end

endmodule
