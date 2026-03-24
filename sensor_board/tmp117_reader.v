`timescale 1ns/1ps
`default_nettype none

module tmp117_reader #(
    parameter integer TICKS_PER_I2C_CLK_PERIOD = 400,
    parameter integer CLK_FREQ_HZ              = 50_000_000,
    parameter integer POLL_HZ                  = 2,
    parameter integer STARTUP_DELAY_MS         = 200
)(
    input  wire       clk_50,
    input  wire       reset_n,
    inout  wire       i2c_sda,
    output wire       i2c_scl,

    output reg        sensor_present,
    output reg        temp_valid,
    output reg [7:0]  id48_msb,
    output reg [7:0]  id48_lsb,
    output reg [7:0]  id49_msb,
    output reg [7:0]  id49_lsb,
    output reg [7:0]  temp_msb,
    output reg [7:0]  temp_lsb,
    output reg [3:0]  dbg_state,
    output reg [6:0]  dbg_addr,
    output reg        dbg_selected_49
);

    wire rst = ~reset_n;

    localparam [2:0] DRVR_CMD_NONE       = 3'd0;
    localparam [2:0] DRVR_CMD_WRITE      = 3'd1;
    localparam [2:0] DRVR_CMD_READ       = 3'd2;
    localparam [2:0] DRVR_CMD_START_COND = 3'd3;
    localparam [2:0] DRVR_CMD_STOP_COND  = 3'd4;

    localparam [7:0] REG_TEMP_RESULT = 8'h00;
    localparam [7:0] REG_DEVICE_ID   = 8'h0F;
    localparam [15:0] TMP117_CHIP_ID = 16'h0117;
    localparam [6:0] ADDR0           = 7'h48;
    localparam [6:0] ADDR1           = 7'h49;

    localparam integer STARTUP_TICKS = ((CLK_FREQ_HZ / 1000) * STARTUP_DELAY_MS < 1) ? 1 : ((CLK_FREQ_HZ / 1000) * STARTUP_DELAY_MS);
    localparam integer POLL_TICKS    = (POLL_HZ <= 0) ? CLK_FREQ_HZ : (((CLK_FREQ_HZ / POLL_HZ) < 1) ? 1 : (CLK_FREQ_HZ / POLL_HZ));
    localparam integer STARTUP_W = (STARTUP_TICKS <= 1) ? 1 : $clog2(STARTUP_TICKS);
    localparam integer POLL_W    = (POLL_TICKS <= 1) ? 1 : $clog2(POLL_TICKS);

    reg  [2:0] drv_command;
    reg  [7:0] drv_tx_byte;
    reg        drv_ack;
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

    reg [6:0] active_addr;
    reg [7:0] active_reg;
    reg [7:0] rx_msb;
    reg [7:0] rx_lsb;
    reg [STARTUP_W-1:0] startup_cnt;
    reg [POLL_W-1:0]    poll_cnt;
    reg found_48;
    reg found_49;

    wire [7:0] active_addr_w = {active_addr, 1'b0};
    wire [7:0] active_addr_r = {active_addr, 1'b1};

    localparam [3:0]
        S_BOOT_WAIT = 4'd0,
        S_ID48      = 4'd1,
        S_ID48_EVAL = 4'd2,
        S_ID49      = 4'd3,
        S_ID49_EVAL = 4'd4,
        S_SELECT    = 4'd5,
        S_TEMP      = 4'd6,
        S_TEMP_EVAL = 4'd7,
        S_WAIT_POLL = 4'd8;

    // Sequence: START -> ADDR(W) -> REG -> STOP -> START -> ADDR(R) -> READ2 -> STOP
    localparam [4:0]
        X_IDLE       = 5'd0,
        X_START_W0   = 5'd1,
        X_START_W1   = 5'd2,
        X_ADDRW0     = 5'd3,
        X_ADDRW1     = 5'd4,
        X_REG0       = 5'd5,
        X_REG1       = 5'd6,
        X_STOPA0     = 5'd7,
        X_STOPA1     = 5'd8,
        X_START_R0   = 5'd9,
        X_START_R1   = 5'd10,
        X_ADDRR0     = 5'd11,
        X_ADDRR1     = 5'd12,
        X_READ0_0    = 5'd13,
        X_READ0_1    = 5'd14,
        X_READ1_0    = 5'd15,
        X_READ1_1    = 5'd16,
        X_STOPB0     = 5'd17,
        X_STOPB1     = 5'd18;

    reg [3:0] main_state;
    reg [4:0] xstate;

    always @(posedge clk_50 or negedge reset_n) begin
        if (!reset_n) begin
            drv_command      <= DRVR_CMD_NONE;
            drv_tx_byte      <= 8'h00;
            drv_ack          <= 1'b1;
            active_addr      <= ADDR0;
            active_reg       <= REG_DEVICE_ID;
            rx_msb           <= 8'h00;
            rx_lsb           <= 8'h00;
            startup_cnt      <= {STARTUP_W{1'b0}};
            poll_cnt         <= {POLL_W{1'b0}};
            found_48         <= 1'b0;
            found_49         <= 1'b0;
            sensor_present   <= 1'b0;
            temp_valid       <= 1'b0;
            id48_msb         <= 8'h00;
            id48_lsb         <= 8'h00;
            id49_msb         <= 8'h00;
            id49_lsb         <= 8'h00;
            temp_msb         <= 8'h00;
            temp_lsb         <= 8'h00;
            dbg_state        <= S_BOOT_WAIT;
            dbg_addr         <= ADDR0;
            dbg_selected_49  <= 1'b0;
            main_state       <= S_BOOT_WAIT;
            xstate           <= X_IDLE;
        end else begin
            drv_command <= DRVR_CMD_NONE;
            dbg_state   <= main_state;
            dbg_addr    <= active_addr;

            case (xstate)
                X_IDLE: begin
                    case (main_state)
                        S_BOOT_WAIT: begin
                            sensor_present  <= 1'b0;
                            temp_valid      <= 1'b0;
                            dbg_selected_49 <= 1'b0;
                            if (startup_cnt == STARTUP_TICKS-1) begin
                                startup_cnt <= {STARTUP_W{1'b0}};
                                found_48    <= 1'b0;
                                found_49    <= 1'b0;
                                main_state  <= S_ID48;
                            end else begin
                                startup_cnt <= startup_cnt + 1'b1;
                            end
                        end

                        S_ID48: begin
                            active_addr <= ADDR0;
                            active_reg  <= REG_DEVICE_ID;
                            main_state  <= S_ID48_EVAL;
                            xstate      <= X_START_W0;
                        end

                        S_ID48_EVAL: begin
                            id48_msb <= rx_msb;
                            id48_lsb <= rx_lsb;
                            found_48 <= ({rx_msb, rx_lsb} == TMP117_CHIP_ID);
                            main_state <= S_ID49;
                        end

                        S_ID49: begin
                            active_addr <= ADDR1;
                            active_reg  <= REG_DEVICE_ID;
                            main_state  <= S_ID49_EVAL;
                            xstate      <= X_START_W0;
                        end

                        S_ID49_EVAL: begin
                            id49_msb <= rx_msb;
                            id49_lsb <= rx_lsb;
                            found_49 <= ({rx_msb, rx_lsb} == TMP117_CHIP_ID);
                            main_state <= S_SELECT;
                        end

                        S_SELECT: begin
                            temp_valid     <= 1'b0;
                            sensor_present <= 1'b0;
                            temp_msb       <= 8'h00;
                            temp_lsb       <= 8'h00;

                            if (found_48) begin
                                active_addr      <= ADDR0;
                                active_reg       <= REG_TEMP_RESULT;
                                dbg_selected_49  <= 1'b0;
                                sensor_present   <= 1'b1;
                                main_state       <= S_TEMP;
                            end else if (found_49) begin
                                active_addr      <= ADDR1;
                                active_reg       <= REG_TEMP_RESULT;
                                dbg_selected_49  <= 1'b1;
                                sensor_present   <= 1'b1;
                                main_state       <= S_TEMP;
                            end else begin
                                dbg_selected_49  <= 1'b0;
                                poll_cnt         <= {POLL_W{1'b0}};
                                main_state       <= S_WAIT_POLL;
                            end
                        end

                        S_TEMP: begin
                            main_state <= S_TEMP_EVAL;
                            xstate     <= X_START_W0;
                        end

                        S_TEMP_EVAL: begin
                            temp_msb       <= rx_msb;
                            temp_lsb       <= rx_lsb;
                            sensor_present <= 1'b1;
                            temp_valid     <= 1'b1;
                            poll_cnt       <= {POLL_W{1'b0}};
                            main_state     <= S_WAIT_POLL;
                        end

                        S_WAIT_POLL: begin
                            if (poll_cnt == POLL_TICKS-1) begin
                                poll_cnt   <= {POLL_W{1'b0}};
                                main_state <= S_ID48;
                            end else begin
                                poll_cnt <= poll_cnt + 1'b1;
                            end
                        end

                        default: main_state <= S_BOOT_WAIT;
                    endcase
                end

                X_START_W0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_START_COND;
                    xstate      <= X_START_W1;
                end

                X_START_W1: if (drv_done) begin
                    drv_tx_byte <= active_addr_w;
                    xstate      <= X_ADDRW0;
                end

                X_ADDRW0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    xstate      <= X_ADDRW1;
                end

                X_ADDRW1: if (drv_done) begin
                    drv_tx_byte <= active_reg;
                    xstate      <= X_REG0;
                end

                X_REG0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    xstate      <= X_REG1;
                end

                X_REG1: if (drv_done) begin
                    xstate <= X_STOPA0;
                end

                X_STOPA0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_STOP_COND;
                    xstate      <= X_STOPA1;
                end

                X_STOPA1: if (drv_done) begin
                    xstate <= X_START_R0;
                end

                X_START_R0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_START_COND;
                    xstate      <= X_START_R1;
                end

                X_START_R1: if (drv_done) begin
                    drv_tx_byte <= active_addr_r;
                    xstate      <= X_ADDRR0;
                end

                X_ADDRR0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_WRITE;
                    xstate      <= X_ADDRR1;
                end

                X_ADDRR1: if (drv_done) begin
                    drv_ack <= 1'b1;   // ACK after first byte
                    xstate  <= X_READ0_0;
                end

                X_READ0_0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_READ;
                    xstate      <= X_READ0_1;
                end

                X_READ0_1: begin
                    if (drv_data_valid) rx_msb <= drv_read_byte;
                    if (drv_done) begin
                        drv_ack <= 1'b0; // NACK after second byte
                        xstate  <= X_READ1_0;
                    end
                end

                X_READ1_0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_READ;
                    xstate      <= X_READ1_1;
                end

                X_READ1_1: begin
                    if (drv_data_valid) rx_lsb <= drv_read_byte;
                    if (drv_done) xstate <= X_STOPB0;
                end

                X_STOPB0: if (!drv_busy) begin
                    drv_command <= DRVR_CMD_STOP_COND;
                    xstate      <= X_STOPB1;
                end

                X_STOPB1: if (drv_done) begin
                    xstate <= X_IDLE;
                end

                default: xstate <= X_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
