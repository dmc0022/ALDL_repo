`default_nettype none

module i2c_touch_hub #(
    parameter [6:0] DEV_ADDR0 = 7'h28,
    parameter [6:0] DEV_ADDR1 = 7'h29,
    parameter [6:0] DEV_ADDR2 = 7'h00,
    parameter       ENABLE_DEV0 = 1'b1,
    parameter       ENABLE_DEV1 = 1'b1,
    parameter       ENABLE_DEV2 = 1'b0,
    parameter [6:0] FT6336_ADDR = 7'h38,
    parameter integer TICKS_PER_I2C_CLK_PERIOD = 400,
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer POLL_HZ = 200
)(
    input  wire       clk_50,
    input  wire       reset_n,

    inout  wire       i2c_sda,
    output wire       i2c_scl,

    output reg        CTP_RST,
    input  wire       CTP_INT,

    output reg        touch_valid,
    output reg        touch_down,
    output reg [11:0] touch_x,
    output reg [11:0] touch_y,

    output wire [7:0] cap_touch_status_0,
    output wire [7:0] cap_touch_status_1,
    output wire [7:0] cap_touch_status_2,
    output wire [9:0] LEDR
);

    wire rst = ~reset_n;

    localparam [2:0] DRVR_CMD_NONE       = 3'd0;
    localparam [2:0] DRVR_CMD_WRITE      = 3'd1;
    localparam [2:0] DRVR_CMD_READ       = 3'd2;
    localparam [2:0] DRVR_CMD_START_COND = 3'd3;
    localparam [2:0] DRVR_CMD_STOP_COND  = 3'd4;

    localparam [7:0] REG_MAIN_CTRL      = 8'h00;
    localparam [7:0] REG_SENSOR_STATUS  = 8'h03;
    localparam [7:0] REG_LED_OUTPUT_TYP = 8'h71;
    localparam [7:0] REG_SENSOR_LED_LNK = 8'h72;
    localparam [7:0] REG_LED_POLARITY   = 8'h73;
    localparam [7:0] REG_TD_STATUS      = 8'h02;

    localparam [7:0] VAL_LED_OUTPUT_TYP = 8'h00;
    localparam [7:0] VAL_LED_POLARITY   = 8'h00;
    localparam [7:0] VAL_LED_LINK_ALL   = 8'hFF;
    localparam [7:0] VAL_MAINCLR        = 8'h00;

    reg  [2:0] drv_command = DRVR_CMD_NONE;
    reg  [7:0] drv_tx_byte = 8'h00;
    reg        drv_ack     = 1'b1;

    wire [7:0] drv_read_byte;
    wire       drv_busy;
    wire       drv_data_valid;
    wire       drv_done;

    wire sda_in;
    wire sda_out;
    wire scl_out;

    assign sda_in  = i2c_sda;
    assign i2c_scl = scl_out;
    assign i2c_sda = (sda_out) ? 1'bz : 1'b0;

    gI2C_low_level_tx_rx #(
        .TICKS_PER_I2C_CLK_PERIOD(TICKS_PER_I2C_CLK_PERIOD)
    ) i2c_core (
        .clk       (clk_50),
        .rst       (rst),
        .command   (drv_command),
        .tx_byte   (drv_tx_byte),
        .ACK       (drv_ack),
        .read_byte (drv_read_byte),
        .busy      (drv_busy),
        .data_valid(drv_data_valid),
        .done      (drv_done),
        .i_sda     (sda_in),
        .o_sda     (sda_out),
        .o_scl     (scl_out)
    );

    reg [1:0] dev_idx = 2'd0;
    reg       init_done = 1'b0;

    reg [7:0] touch_status_0 = 8'h00;
    reg [7:0] touch_status_1 = 8'h00;
    reg [7:0] touch_status_2 = 8'h00;

    assign cap_touch_status_0 = touch_status_0;
    assign cap_touch_status_1 = touch_status_1;
    assign cap_touch_status_2 = touch_status_2;

    wire [7:0] touch_or = touch_status_0 | touch_status_1 | touch_status_2;
    assign LEDR[7:0] = touch_or;
    assign LEDR[9:8] = 2'b00;

    function automatic enabled_dev;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: enabled_dev = ENABLE_DEV0;
                2'd1: enabled_dev = ENABLE_DEV1;
                2'd2: enabled_dev = ENABLE_DEV2;
                default: enabled_dev = 1'b0;
            endcase
        end
    endfunction

    function automatic [6:0] dev_addr;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: dev_addr = DEV_ADDR0;
                2'd1: dev_addr = DEV_ADDR1;
                2'd2: dev_addr = DEV_ADDR2;
                default: dev_addr = 7'h00;
            endcase
        end
    endfunction

    function automatic [1:0] next_enabled_dev;
        input [1:0] idx;
        reg [1:0] a;
        begin
            a = (idx == 2'd2) ? 2'd0 : (idx + 2'd1);
            if (enabled_dev(a)) next_enabled_dev = a;
            else begin
                a = (a == 2'd2) ? 2'd0 : (a + 2'd1);
                if (enabled_dev(a)) next_enabled_dev = a;
                else begin
                    a = (a == 2'd2) ? 2'd0 : (a + 2'd1);
                    next_enabled_dev = a;
                end
            end
        end
    endfunction

    wire [7:0] addr_w = {dev_addr(dev_idx), 1'b0};
    wire [7:0] addr_r = {dev_addr(dev_idx), 1'b1};
    wire [7:0] FT_ADDR_W = {FT6336_ADDR, 1'b0};
    wire [7:0] FT_ADDR_R = {FT6336_ADDR, 1'b1};

    localparam integer RST_COUNT_MAX = 100_000;
    localparam integer RST_W = $clog2(RST_COUNT_MAX);
    reg [RST_W-1:0] rst_cnt = {RST_W{1'b0}};
    reg ft_ready = 1'b0;

    localparam integer POLL_INTERVAL_TICKS = CLK_FREQ_HZ / POLL_HZ;
    localparam integer POLL_W = (POLL_INTERVAL_TICKS <= 1) ? 1 : $clog2(POLL_INTERVAL_TICKS);
    reg [POLL_W-1:0] ft_poll_cnt = {POLL_W{1'b0}};
    reg ft_poll_pending = 1'b0;

    reg [7:0] td_status = 8'h00;
    reg [7:0] p1_xh = 8'h00;
    reg [7:0] p1_xl = 8'h00;
    reg [7:0] p1_yh = 8'h00;
    reg [7:0] p1_yl = 8'h00;

    localparam [6:0]
        S_IDLE               = 7'd0,
        S_CFG_START          = 7'd1,
        S_CFG_START_W        = 7'd2,
        S_CFG_ADDR0          = 7'd3,
        S_CFG_ADDR0_W        = 7'd4,
        S_CFG_REG0           = 7'd5,
        S_CFG_REG0_W         = 7'd6,
        S_CFG_DATA0          = 7'd7,
        S_CFG_DATA0_W        = 7'd8,
        S_CFG_STOP0          = 7'd9,
        S_CFG_STOP0_W        = 7'd10,
        S_CFG_START1         = 7'd11,
        S_CFG_START1_W       = 7'd12,
        S_CFG_ADDR1          = 7'd13,
        S_CFG_ADDR1_W        = 7'd14,
        S_CFG_REG1           = 7'd15,
        S_CFG_REG1_W         = 7'd16,
        S_CFG_DATA1          = 7'd17,
        S_CFG_DATA1_W        = 7'd18,
        S_CFG_STOP1          = 7'd19,
        S_CFG_STOP1_W        = 7'd20,
        S_CFG_START2         = 7'd21,
        S_CFG_START2_W       = 7'd22,
        S_CFG_ADDR2          = 7'd23,
        S_CFG_ADDR2_W        = 7'd24,
        S_CFG_REG2           = 7'd25,
        S_CFG_REG2_W         = 7'd26,
        S_CFG_DATA2          = 7'd27,
        S_CFG_DATA2_W        = 7'd28,
        S_CFG_STOP2          = 7'd29,
        S_CFG_STOP2_W        = 7'd30,
        S_RD_START           = 7'd31,
        S_RD_START_W         = 7'd32,
        S_RD_ADDRW           = 7'd33,
        S_RD_ADDRW_W         = 7'd34,
        S_RD_REG             = 7'd35,
        S_RD_REG_W           = 7'd36,
        S_RD_RS              = 7'd37,
        S_RD_RS_W            = 7'd38,
        S_RD_ADDRR           = 7'd39,
        S_RD_ADDRR_W         = 7'd40,
        S_RD_DATA            = 7'd41,
        S_RD_DATA_W          = 7'd42,
        S_RD_STOP            = 7'd43,
        S_RD_STOP_W          = 7'd44,
        S_CLR_START          = 7'd45,
        S_CLR_START_W        = 7'd46,
        S_CLR_ADDR           = 7'd47,
        S_CLR_ADDR_W         = 7'd48,
        S_CLR_REG            = 7'd49,
        S_CLR_REG_W          = 7'd50,
        S_CLR_DATA           = 7'd51,
        S_CLR_DATA_W         = 7'd52,
        S_CLR_STOP           = 7'd53,
        S_CLR_STOP_W         = 7'd54,
        S_FT_START1          = 7'd55,
        S_FT_START1_W        = 7'd56,
        S_FT_ADDRW           = 7'd57,
        S_FT_ADDRW_W         = 7'd58,
        S_FT_REG             = 7'd59,
        S_FT_REG_W           = 7'd60,
        S_FT_START2          = 7'd61,
        S_FT_START2_W        = 7'd62,
        S_FT_ADDRR           = 7'd63,
        S_FT_ADDRR_W         = 7'd64,
        S_FT_READ0           = 7'd65,
        S_FT_READ0_W         = 7'd66,
        S_FT_READ1           = 7'd67,
        S_FT_READ1_W         = 7'd68,
        S_FT_READ2           = 7'd69,
        S_FT_READ2_W         = 7'd70,
        S_FT_READ3           = 7'd71,
        S_FT_READ3_W         = 7'd72,
        S_FT_READ4           = 7'd73,
        S_FT_READ4_W         = 7'd74,
        S_FT_STOP            = 7'd75,
        S_FT_STOP_W          = 7'd76,
        S_FT_PROCESS         = 7'd77;

    reg [6:0] state = S_IDLE;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            state           <= S_IDLE;
            drv_command     <= DRVR_CMD_NONE;
            drv_tx_byte     <= 8'h00;
            drv_ack         <= 1'b1;
            dev_idx         <= ENABLE_DEV0 ? 2'd0 : (ENABLE_DEV1 ? 2'd1 : 2'd2);
            init_done       <= 1'b0;
            touch_status_0  <= 8'h00;
            touch_status_1  <= 8'h00;
            touch_status_2  <= 8'h00;
            td_status       <= 8'h00;
            p1_xh           <= 8'h00;
            p1_xl           <= 8'h00;
            p1_yh           <= 8'h00;
            p1_yl           <= 8'h00;
            touch_valid     <= 1'b0;
            touch_down      <= 1'b0;
            touch_x         <= 12'd0;
            touch_y         <= 12'd0;
            CTP_RST         <= 1'b0;
            rst_cnt         <= {RST_W{1'b0}};
            ft_ready        <= 1'b0;
            ft_poll_cnt     <= {POLL_W{1'b0}};
            ft_poll_pending <= 1'b0;
        end else begin
            drv_command <= DRVR_CMD_NONE;
            touch_valid <= 1'b0;

            if (!ft_ready) begin
                CTP_RST <= 1'b0;
                if (rst_cnt == RST_COUNT_MAX-1) begin
                    rst_cnt  <= {RST_W{1'b0}};
                    CTP_RST  <= 1'b1;
                    ft_ready <= 1'b1;
                end else begin
                    rst_cnt <= rst_cnt + 1'b1;
                end
            end else begin
                CTP_RST <= 1'b1;
                if (ft_poll_cnt == POLL_INTERVAL_TICKS-1) begin
                    ft_poll_cnt     <= {POLL_W{1'b0}};
                    ft_poll_pending <= 1'b1;
                end else begin
                    ft_poll_cnt <= ft_poll_cnt + 1'b1;
                end
            end

            case (state)
                S_IDLE: begin
                    if (!drv_busy) begin
                        if (!init_done && enabled_dev(dev_idx)) begin
                            state <= S_CFG_START;
                        end else if (ft_poll_pending && ft_ready) begin
                            ft_poll_pending <= 1'b0;
                            state <= S_FT_START1;
                        end else if (enabled_dev(dev_idx)) begin
                            state <= S_RD_START;
                        end else begin
                            dev_idx <= next_enabled_dev(dev_idx);
                        end
                    end
                end

                S_CFG_START:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_CFG_START_W; end
                S_CFG_START_W: if (drv_done)  begin drv_tx_byte <= addr_w;               state <= S_CFG_ADDR0;   end
                S_CFG_ADDR0:   if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_ADDR0_W; end
                S_CFG_ADDR0_W: if (drv_done)  begin drv_tx_byte <= REG_LED_OUTPUT_TYP;  state <= S_CFG_REG0;    end
                S_CFG_REG0:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_REG0_W;  end
                S_CFG_REG0_W:  if (drv_done)  begin drv_tx_byte <= VAL_LED_OUTPUT_TYP;  state <= S_CFG_DATA0;   end
                S_CFG_DATA0:   if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_DATA0_W; end
                S_CFG_DATA0_W: if (drv_done)  begin state <= S_CFG_STOP0; end
                S_CFG_STOP0:   if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND;  state <= S_CFG_STOP0_W; end
                S_CFG_STOP0_W: if (drv_done)  begin state <= S_CFG_START1; end

                S_CFG_START1:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_CFG_START1_W; end
                S_CFG_START1_W: if (drv_done)  begin drv_tx_byte <= addr_w;               state <= S_CFG_ADDR1;    end
                S_CFG_ADDR1:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_ADDR1_W;  end
                S_CFG_ADDR1_W:  if (drv_done)  begin drv_tx_byte <= REG_LED_POLARITY;    state <= S_CFG_REG1;     end
                S_CFG_REG1:     if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_REG1_W;   end
                S_CFG_REG1_W:   if (drv_done)  begin drv_tx_byte <= VAL_LED_POLARITY;    state <= S_CFG_DATA1;    end
                S_CFG_DATA1:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_DATA1_W;  end
                S_CFG_DATA1_W:  if (drv_done)  begin state <= S_CFG_STOP1; end
                S_CFG_STOP1:    if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND;  state <= S_CFG_STOP1_W;  end
                S_CFG_STOP1_W:  if (drv_done)  begin state <= S_CFG_START2; end

                S_CFG_START2:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_CFG_START2_W; end
                S_CFG_START2_W: if (drv_done)  begin drv_tx_byte <= addr_w;               state <= S_CFG_ADDR2;    end
                S_CFG_ADDR2:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_ADDR2_W;  end
                S_CFG_ADDR2_W:  if (drv_done)  begin drv_tx_byte <= REG_SENSOR_LED_LNK;  state <= S_CFG_REG2;     end
                S_CFG_REG2:     if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_REG2_W;   end
                S_CFG_REG2_W:   if (drv_done)  begin drv_tx_byte <= VAL_LED_LINK_ALL;    state <= S_CFG_DATA2;    end
                S_CFG_DATA2:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CFG_DATA2_W;  end
                S_CFG_DATA2_W:  if (drv_done)  begin state <= S_CFG_STOP2; end
                S_CFG_STOP2:    if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND;  state <= S_CFG_STOP2_W;  end
                S_CFG_STOP2_W:  if (drv_done)  begin
                    if (next_enabled_dev(dev_idx) == dev_idx) init_done <= 1'b1;
                    else if (next_enabled_dev(dev_idx) == (ENABLE_DEV0 ? 2'd0 : (ENABLE_DEV1 ? 2'd1 : 2'd2))) init_done <= 1'b1;
                    dev_idx <= next_enabled_dev(dev_idx);
                    state   <= S_IDLE;
                end

                S_RD_START:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_RD_START_W; end
                S_RD_START_W: if (drv_done)  begin drv_tx_byte <= addr_w;               state <= S_RD_ADDRW;   end
                S_RD_ADDRW:   if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_RD_ADDRW_W; end
                S_RD_ADDRW_W: if (drv_done)  begin drv_tx_byte <= REG_SENSOR_STATUS;   state <= S_RD_REG;     end
                S_RD_REG:     if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_RD_REG_W;   end
                S_RD_REG_W:   if (drv_done)  begin state <= S_RD_RS; end
                S_RD_RS:      if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_RD_RS_W;    end
                S_RD_RS_W:    if (drv_done)  begin drv_tx_byte <= addr_r;               state <= S_RD_ADDRR;   end
                S_RD_ADDRR:   if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_RD_ADDRR_W; end
                S_RD_ADDRR_W: if (drv_done)  begin drv_ack <= 1'b0; state <= S_RD_DATA; end
                S_RD_DATA:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_RD_DATA_W;  end
                S_RD_DATA_W: begin
                    if (drv_data_valid) begin
                        case (dev_idx)
                            2'd0: touch_status_0 <= drv_read_byte;
                            2'd1: touch_status_1 <= drv_read_byte;
                            2'd2: touch_status_2 <= drv_read_byte;
                            default: ;
                        endcase
                    end
                    if (drv_done) state <= S_RD_STOP;
                end
                S_RD_STOP:   if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND; state <= S_RD_STOP_W; end
                S_RD_STOP_W: if (drv_done)  begin state <= S_CLR_START; end

                S_CLR_START:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_CLR_START_W; end
                S_CLR_START_W: if (drv_done)  begin drv_tx_byte <= addr_w;               state <= S_CLR_ADDR;    end
                S_CLR_ADDR:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CLR_ADDR_W;  end
                S_CLR_ADDR_W:  if (drv_done)  begin drv_tx_byte <= REG_MAIN_CTRL;       state <= S_CLR_REG;     end
                S_CLR_REG:     if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CLR_REG_W;   end
                S_CLR_REG_W:   if (drv_done)  begin drv_tx_byte <= VAL_MAINCLR;         state <= S_CLR_DATA;    end
                S_CLR_DATA:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_CLR_DATA_W;  end
                S_CLR_DATA_W:  if (drv_done)  begin state <= S_CLR_STOP; end
                S_CLR_STOP:    if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND;  state <= S_CLR_STOP_W;  end
                S_CLR_STOP_W:  if (drv_done)  begin dev_idx <= next_enabled_dev(dev_idx); state <= S_IDLE; end

                S_FT_START1:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_FT_START1_W; end
                S_FT_START1_W: if (drv_done)  begin drv_tx_byte <= FT_ADDR_W;            state <= S_FT_ADDRW;    end
                S_FT_ADDRW:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_FT_ADDRW_W;  end
                S_FT_ADDRW_W:  if (drv_done)  begin drv_tx_byte <= REG_TD_STATUS;       state <= S_FT_REG;      end
                S_FT_REG:      if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_FT_REG_W;    end
                S_FT_REG_W:    if (drv_done)  begin state <= S_FT_START2; end
                S_FT_START2:   if (!drv_busy) begin drv_command <= DRVR_CMD_START_COND; state <= S_FT_START2_W; end
                S_FT_START2_W: if (drv_done)  begin drv_tx_byte <= FT_ADDR_R;            state <= S_FT_ADDRR;    end
                S_FT_ADDRR:    if (!drv_busy) begin drv_command <= DRVR_CMD_WRITE;      state <= S_FT_ADDRR_W;  end
                S_FT_ADDRR_W:  if (drv_done)  begin drv_ack <= 1'b1; state <= S_FT_READ0; end
                S_FT_READ0:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_FT_READ0_W;  end
                S_FT_READ0_W:  begin if (drv_data_valid) td_status <= drv_read_byte; if (drv_done) begin drv_ack <= 1'b1; state <= S_FT_READ1; end end
                S_FT_READ1:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_FT_READ1_W;  end
                S_FT_READ1_W:  begin if (drv_data_valid) p1_xh <= drv_read_byte;   if (drv_done) begin drv_ack <= 1'b1; state <= S_FT_READ2; end end
                S_FT_READ2:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_FT_READ2_W;  end
                S_FT_READ2_W:  begin if (drv_data_valid) p1_xl <= drv_read_byte;   if (drv_done) begin drv_ack <= 1'b1; state <= S_FT_READ3; end end
                S_FT_READ3:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_FT_READ3_W;  end
                S_FT_READ3_W:  begin if (drv_data_valid) p1_yh <= drv_read_byte;   if (drv_done) begin drv_ack <= 1'b0; state <= S_FT_READ4; end end
                S_FT_READ4:    if (!drv_busy) begin drv_command <= DRVR_CMD_READ;       state <= S_FT_READ4_W;  end
                S_FT_READ4_W:  begin if (drv_data_valid) p1_yl <= drv_read_byte;   if (drv_done) state <= S_FT_STOP; end
                S_FT_STOP:     if (!drv_busy) begin drv_command <= DRVR_CMD_STOP_COND;  state <= S_FT_STOP_W;   end
                S_FT_STOP_W:   if (drv_done)  begin state <= S_FT_PROCESS; end
                S_FT_PROCESS: begin
                    if (td_status[3:0] != 4'd0) begin
                        touch_down  <= 1'b1;
                        touch_x     <= {p1_xh[3:0], p1_xl};
                        touch_y     <= {p1_yh[3:0], p1_yl};
                        touch_valid <= 1'b1;
                    end else begin
                        touch_down  <= 1'b0;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
