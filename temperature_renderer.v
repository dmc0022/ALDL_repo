`timescale 1ns/1ps
`default_nettype none

module temperature_renderer #(
    parameter integer GAME_W = 320,
    parameter integer GAME_H = 240
)(
    input  wire               clk,
    input  wire               reset_n,
    input  wire               framebufferClk,
    input  wire               temp_valid,
    input  wire               sensor_present,
    input  wire signed [15:0] temp_centi_c,
    output reg  [15:0]        pixel_color
);

    reg [9:0] x;
    reg [8:0] y;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x <= 10'd0;
            y <= 9'd0;
        end else if (framebufferClk) begin
            if (x == GAME_W-1) begin
                x <= 10'd0;
                if (y == GAME_H-1) y <= 9'd0;
                else               y <= y + 9'd1;
            end else begin
                x <= x + 10'd1;
            end
        end
    end

    function automatic in_rect;
        input integer px, py, x0, y0, w, h;
        begin
            in_rect = (px >= x0) && (px < (x0 + w)) &&
                      (py >= y0) && (py < (y0 + h));
        end
    endfunction

    function automatic seg_on;
        input [3:0] val;
        input [2:0] seg;
        begin
            case (val)
                4'd0: seg_on = (seg != 3'd6);
                4'd1: seg_on = (seg == 3'd1) || (seg == 3'd2);
                4'd2: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd6) || (seg == 3'd4) || (seg == 3'd3);
                4'd3: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd6) || (seg == 3'd2) || (seg == 3'd3);
                4'd4: seg_on = (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd1) || (seg == 3'd2);
                4'd5: seg_on = (seg == 3'd0) || (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd2) || (seg == 3'd3);
                4'd6: seg_on = (seg == 3'd0) || (seg == 3'd5) || (seg == 3'd6) || (seg == 3'd4) || (seg == 3'd2) || (seg == 3'd3);
                4'd7: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd2);
                4'd8: seg_on = 1'b1;
                4'd9: seg_on = (seg == 3'd0) || (seg == 3'd1) || (seg == 3'd2) || (seg == 3'd3) || (seg == 3'd5) || (seg == 3'd6);
                default: seg_on = 1'b0;
            endcase
        end
    endfunction

    function automatic digit_pixel;
        input integer px, py, x0, y0;
        input [3:0] val;
        integer lx, ly;
        begin
            lx = px - x0;
            ly = py - y0;
            digit_pixel = 1'b0;
            if ((lx >= 0) && (lx < 30) && (ly >= 0) && (ly < 56)) begin
                if (seg_on(val,3'd0) && (ly >= 0  && ly < 5  && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
                if (seg_on(val,3'd1) && (lx >= 25 && lx < 30 && ly >= 6  && ly < 24)) digit_pixel = 1'b1;
                if (seg_on(val,3'd2) && (lx >= 25 && lx < 30 && ly >= 31 && ly < 49)) digit_pixel = 1'b1;
                if (seg_on(val,3'd3) && (ly >= 51 && ly < 56 && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
                if (seg_on(val,3'd4) && (lx >= 0  && lx < 5  && ly >= 31 && ly < 49)) digit_pixel = 1'b1;
                if (seg_on(val,3'd5) && (lx >= 0  && lx < 5  && ly >= 6  && ly < 24)) digit_pixel = 1'b1;
                if (seg_on(val,3'd6) && (ly >= 25 && ly < 30 && lx >= 6  && lx < 24)) digit_pixel = 1'b1;
            end
        end
    endfunction

    function automatic c_pixel;
        input integer px, py, x0, y0;
        integer lx, ly;
        begin
            lx = px - x0;
            ly = py - y0;
            c_pixel = 1'b0;
            if ((lx >= 0) && (lx < 20) && (ly >= 0) && (ly < 30)) begin
                if ((ly >= 0  && ly < 4  && lx >= 4 && lx < 18) ||
                    (ly >= 26 && ly < 30 && lx >= 4 && lx < 18) ||
                    (lx >= 0  && lx < 4  && ly >= 4 && ly < 26))
                    c_pixel = 1'b1;
            end
        end
    endfunction

    localparam integer PANEL_X = 36;
    localparam integer PANEL_Y = 52;
    localparam integer PANEL_W = 248;
    localparam integer PANEL_H = 136;

    localparam integer DIGIT_Y = 95;
    localparam integer MINUS_X = 54;
    localparam integer TENS_X  = 86;
    localparam integer ONES_X  = 122;
    localparam integer TENTHS_X= 170;
    localparam integer DP_X    = 158;
    localparam integer DEG_X   = 214;
    localparam integer DEG_Y   = 104;
    localparam integer C_X     = 232;
    localparam integer C_Y     = 108;

    localparam [15:0] COL_BG     = 16'h0841;
    localparam [15:0] COL_PANEL  = 16'h0000;
    localparam [15:0] COL_BORDER = 16'hFFFF;
    localparam [15:0] COL_TEXT   = 16'hFFFF;
    localparam [15:0] COL_ACCENT = 16'h07E0;
    localparam [15:0] COL_WARN   = 16'hF800;

    wire invalid = !(sensor_present && temp_valid);
    wire        neg_temp = temp_centi_c[15];
    wire signed [15:0] abs_temp = neg_temp ? -temp_centi_c : temp_centi_c;
    wire [15:0] abs_u    = abs_temp[15:0];
    wire [15:0] whole    = abs_u / 16'd100;
    wire [15:0] frac     = abs_u % 16'd100;
    wire [3:0] tens      = (whole / 10) % 10;
    wire [3:0] ones      = whole % 10;
    wire [3:0] tenths    = frac / 10;
    wire show_minus = neg_temp && !invalid;
    wire show_tens  = (whole >= 10);

    always @* begin
        pixel_color = COL_BG;
        if (in_rect(x, y, PANEL_X, PANEL_Y, PANEL_W, PANEL_H)) pixel_color = COL_BORDER;
        if (in_rect(x, y, PANEL_X+4, PANEL_Y+4, PANEL_W-8, PANEL_H-8)) pixel_color = COL_PANEL;
        if (in_rect(x, y, PANEL_X+12, PANEL_Y+12, PANEL_W-24, 8)) pixel_color = invalid ? COL_WARN : COL_ACCENT;

        if (invalid) begin
            if (in_rect(x, y, 144, 118, 32, 6)) pixel_color = COL_TEXT;
        end else begin
            if (show_minus && in_rect(x, y, MINUS_X, 120, 20, 5)) pixel_color = COL_TEXT;
            if (show_tens && digit_pixel(x, y, TENS_X, DIGIT_Y, tens)) pixel_color = COL_TEXT;
            if (digit_pixel(x, y, ONES_X, DIGIT_Y, ones)) pixel_color = COL_TEXT;
            if (in_rect(x, y, DP_X, 136, 5, 5)) pixel_color = COL_TEXT;
            if (digit_pixel(x, y, TENTHS_X, DIGIT_Y, tenths)) pixel_color = COL_TEXT;
            if (in_rect(x, y, DEG_X, DEG_Y, 10, 10) && !in_rect(x, y, DEG_X+2, DEG_Y+2, 6, 6)) pixel_color = COL_ACCENT;
            if (c_pixel(x, y, C_X, C_Y)) pixel_color = COL_ACCENT;
        end
    end
endmodule

`default_nettype wire
