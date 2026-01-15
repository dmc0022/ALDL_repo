// de2_115_hub75_top.v  (used on DE10-Lite too)
// SW0 selects which image:
//   SW0 = 0 -> UAH bouncing logo
//   SW0 = 1 -> GIF animation

module de2_115_hub75_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,    // not used now, kept for pinout compatibility
    input  wire [9:0]  SW,     // SW0 = selector

    output wire        PANEL_R1,
    output wire        PANEL_G1,
    output wire        PANEL_B1,
    output wire        PANEL_R2,
    output wire        PANEL_G2,
    output wire        PANEL_B2,
    output wire        PANEL_A,
    output wire        PANEL_B,
    output wire        PANEL_C,
    output wire        PANEL_D,
    output wire        PANEL_CLK,
    output wire        PANEL_LAT,
    output wire        PANEL_OE
);

    wire reset_n = 1'b1;

    // Slide switch is active-high: 0 = UAH, 1 = GIF
    wire sel_gif = SW[0];

    //----------------------------------------
    // UAH LOGO MODULE
    //----------------------------------------
    wire u_r1, u_g1, u_b1;
    wire u_r2, u_g2, u_b2;
    wire [3:0] u_row_addr;
    wire u_clk, u_lat, u_oe;

    hub75_uahlogo u_logo (
        .clk      (CLOCK_50),
        .reset_n  (reset_n),

        .r1       (u_r1),
        .g1       (u_g1),
        .b1       (u_b1),
        .r2       (u_r2),
        .g2       (u_g2),
        .b2       (u_b2),

        .row_addr (u_row_addr),
        .clk_out  (u_clk),
        .lat      (u_lat),
        .oe       (u_oe)
    );

    //----------------------------------------
    // GIF MODULE
    //----------------------------------------
    wire g_r1, g_g1, g_b1;
    wire g_r2, g_g2, g_b2;
    wire [3:0] g_row_addr;
    wire g_clk, g_lat, g_oe;

    hub75_gif u_gif (
        .clk      (CLOCK_50),
        .reset_n  (reset_n),

        .r1       (g_r1),
        .g1       (g_g1),
        .b1       (g_b1),
        .r2       (g_r2),
        .g2       (g_g2),
        .b2       (g_b2),

        .row_addr (g_row_addr),
        .clk_out  (g_clk),
        .lat      (g_lat),
        .oe       (g_oe)
    );

    //----------------------------------------
    // OUTPUT MUX: SW0 selects source
    //----------------------------------------
    assign PANEL_R1 = sel_gif ? g_r1 : u_r1;
    assign PANEL_G1 = sel_gif ? g_g1 : u_g1;
    assign PANEL_B1 = sel_gif ? g_b1 : u_b1;

    assign PANEL_R2 = sel_gif ? g_r2 : u_r2;
    assign PANEL_G2 = sel_gif ? g_g2 : u_g2;
    assign PANEL_B2 = sel_gif ? g_b2 : u_b2;

    assign PANEL_CLK = sel_gif ? g_clk : u_clk;
    assign PANEL_LAT = sel_gif ? g_lat : u_lat;
    assign PANEL_OE  = sel_gif ? g_oe  : u_oe;

    // ABCD row address
    wire [3:0] row_sel = sel_gif ? g_row_addr : u_row_addr;
    assign {PANEL_D, PANEL_C, PANEL_B, PANEL_A} = row_sel;

endmodule
