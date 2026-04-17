`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SystemVerilog I2C master based on the CircuitDen design.
//
// Added debug outputs:
//   dbg_state            - current main FSM state
//   dbg_process_counter  - current 4-phase substep
//   dbg_bit_counter      - current bit counter
//   dbg_byte_counter     - current byte counter
//   dbg_last_acknowledge - last sampled ACK result
//////////////////////////////////////////////////////////////////////////////////
module i2c_master #(
    parameter NUMBER_OF_DATA_BYTES         = 1,
    parameter NUMBER_OF_REGISTER_BYTES     = 1,
    parameter ADDRESS_WIDTH                = 7,
    parameter CHECK_FOR_CLOCK_STRETCHING   = 1,
    parameter CLOCK_STRETCHING_MAX_COUNT   = 'hFF
)(
    input   wire                            clock,
    input   wire                            reset_n,
    input   wire                            enable,
    input   wire                            read_write,
    input   wire    [NUMBER_OF_DATA_BYTES*8-1:0]    mosi_data,
    input   wire    [NUMBER_OF_REGISTER_BYTES*8-1:0] register_address,
    input   wire    [ADDRESS_WIDTH-1:0]             device_address,
    input   wire    [15:0]                          divider,

    output  logic   [NUMBER_OF_DATA_BYTES*8-1:0]    miso_data,
    output  logic                                   busy,

    // Debug outputs
    output  logic   [3:0]                           dbg_state,
    output  logic   [1:0]                           dbg_process_counter,
    output  logic   [3:0]                           dbg_bit_counter,
    output  logic   [7:0]                           dbg_byte_counter,
    output  logic                                   dbg_last_acknowledge,

    inout   wire                                    external_serial_data,
    inout   wire                                    external_serial_clock
);

localparam DATA_WIDTH                   = (NUMBER_OF_DATA_BYTES > 0) ? (NUMBER_OF_DATA_BYTES * 8) : 8;
localparam REGISTER_WIDTH               = (NUMBER_OF_REGISTER_BYTES > 0) ? (NUMBER_OF_REGISTER_BYTES * 8) : 8;
localparam MAX_NUMBER_BYTES             = ((NUMBER_OF_DATA_BYTES > NUMBER_OF_REGISTER_BYTES) ? NUMBER_OF_DATA_BYTES : NUMBER_OF_REGISTER_BYTES);
localparam CLOCK_STRETCHING_TIMER_WIDTH = (CLOCK_STRETCHING_MAX_COUNT > 1) ? $clog2(CLOCK_STRETCHING_MAX_COUNT + 1) : 1;
localparam BYTE_COUNTER_WIDTH           = (MAX_NUMBER_BYTES > 1) ? $clog2(MAX_NUMBER_BYTES + 1) : 1;

logic timeout_cycle_timer_clock;
logic timeout_cycle_timer_reset_n;
logic timeout_cycle_timer_enable;
logic timeout_cycle_timer_load_count;
logic [CLOCK_STRETCHING_TIMER_WIDTH-1:0] timeout_cycle_timer_count;
logic timeout_cycle_timer_expired;

cycle_timer #(
    .BIT_WIDTH(CLOCK_STRETCHING_TIMER_WIDTH)
) timeout_cycle_timer (
    .clock      (timeout_cycle_timer_clock),
    .reset_n    (timeout_cycle_timer_reset_n),
    .enable     (timeout_cycle_timer_enable),
    .load_count (timeout_cycle_timer_load_count),
    .count      (timeout_cycle_timer_count),
    .expired    (timeout_cycle_timer_expired)
);

typedef enum logic [3:0] {
    S_IDLE            = 4'd0,
    S_START           = 4'd1,
    S_WRITE_ADDR_W    = 4'd2,
    S_CHECK_ACK       = 4'd3,
    S_WRITE_REG_ADDR  = 4'd4,
    S_RESTART         = 4'd5,
    S_WRITE_ADDR_R    = 4'd6,
    S_READ_REG        = 4'd7,
    S_SEND_NACK       = 4'd8,
    S_SEND_STOP       = 4'd9,
    S_WRITE_REG_DATA  = 4'd10,
    S_SEND_ACK        = 4'd11
} state_t;

state_t state, _state;
state_t post_state, _post_state;

logic serial_clock, _serial_clock;
logic [ADDRESS_WIDTH:0] saved_device_address, _saved_device_address;
logic [REGISTER_WIDTH-1:0] saved_register_address, _saved_register_address;
logic [DATA_WIDTH-1:0] saved_mosi_data, _saved_mosi_data;
logic [1:0] process_counter, _process_counter;
logic [3:0] bit_counter, _bit_counter;
logic serial_data, _serial_data;
logic post_serial_data, _post_serial_data;
logic last_acknowledge, _last_acknowledge;
logic _saved_read_write, saved_read_write;
logic [15:0] divider_counter, _divider_counter;
logic divider_tick;
logic [DATA_WIDTH-1:0] _miso_data;
logic _busy;
logic serial_data_output_enable;
logic serial_clock_output_enable;
logic [BYTE_COUNTER_WIDTH-1:0] _byte_counter, byte_counter;

assign external_serial_clock = serial_clock_output_enable ? serial_clock : 1'bz;
assign external_serial_data  = serial_data_output_enable  ? serial_data  : 1'bz;

assign timeout_cycle_timer_clock   = clock;
assign timeout_cycle_timer_reset_n = reset_n;
assign timeout_cycle_timer_enable  = (CLOCK_STRETCHING_MAX_COUNT != 0) ? divider_tick : 1'b0;
assign timeout_cycle_timer_count   = CLOCK_STRETCHING_MAX_COUNT[CLOCK_STRETCHING_TIMER_WIDTH-1:0];

// Debug mirrors
always_comb begin
    dbg_state            = state;
    dbg_process_counter  = process_counter;
    dbg_bit_counter      = bit_counter;
    dbg_byte_counter     = {{(8-BYTE_COUNTER_WIDTH){1'b0}}, byte_counter};
    dbg_last_acknowledge = last_acknowledge;
end

always_comb begin
    _state                  = state;
    _post_state             = post_state;
    _process_counter        = process_counter;
    _bit_counter            = bit_counter;
    _last_acknowledge       = last_acknowledge;
    _miso_data              = miso_data;
    _saved_read_write       = saved_read_write;
    _divider_counter        = divider_counter;
    _saved_register_address = saved_register_address;
    _saved_device_address   = saved_device_address;
    _saved_mosi_data        = saved_mosi_data;
    _serial_data            = serial_data;
    _serial_clock           = serial_clock;
    _post_serial_data       = post_serial_data;
    _byte_counter           = byte_counter;
    timeout_cycle_timer_load_count = 1'b0;
    serial_data_output_enable      = 1'b1;
    serial_clock_output_enable     = 1'b0;
    _busy                          = (state == S_IDLE) ? 1'b0 : 1'b1;

    if (divider_counter == divider) begin
        _divider_counter = 16'd0;
        divider_tick     = 1'b1;
    end else begin
        _divider_counter = divider_counter + 16'd1;
        divider_tick     = 1'b0;
    end

    if (state != S_IDLE && process_counter != 2'd1 && process_counter != 2'd2)
        serial_clock_output_enable = 1'b1;

    if (process_counter == 2'd0)
        timeout_cycle_timer_load_count = 1'b1;

    case (state)
        S_IDLE: begin
            serial_data_output_enable = 1'b0;
            _process_counter          = 2'd0;
            _bit_counter              = 4'd0;
            _last_acknowledge         = 1'b0;
            _serial_data              = 1'b1;
            _serial_clock             = 1'b1;
            _saved_read_write         = read_write;
            _saved_mosi_data          = mosi_data;
            _saved_register_address   = register_address;
            _saved_device_address     = {device_address, 1'b0}; // write address

            if (enable) begin
                _state      = S_START;
                _post_state = S_WRITE_ADDR_W;
            end
        end

        S_START: begin
            if (divider_tick) begin
                case (process_counter)
                    2'd0: _process_counter = 2'd1;
                    2'd1: begin
                        _serial_data     = 1'b0;
                        _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _bit_counter     = ADDRESS_WIDTH + 1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        _serial_clock    = 1'b0;
                        _process_counter = 2'd0;
                        _state           = post_state;
                        _serial_data     = saved_device_address[ADDRESS_WIDTH];
                    end
                endcase
            end
        end

        S_WRITE_ADDR_W: begin
            if (process_counter == 2'd3 && bit_counter == 0)
                serial_data_output_enable = 1'b0;

            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _serial_clock = 1'b0;
                        _bit_counter  = bit_counter - 1'b1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        _process_counter = 2'd0;
                        if (bit_counter == 0) begin
                            _post_serial_data       = saved_register_address[REGISTER_WIDTH-1];
                            _saved_register_address = {saved_register_address[REGISTER_WIDTH-2:0], saved_register_address[REGISTER_WIDTH-1]};
                            _post_state             = S_WRITE_REG_ADDR;
                            _state                  = S_CHECK_ACK;
                            _bit_counter            = 4'd8;
                            _byte_counter           = NUMBER_OF_REGISTER_BYTES - 1;
                        end else begin
                            _serial_data = saved_device_address[ADDRESS_WIDTH-1];
                        end
                        _saved_device_address = {saved_device_address[ADDRESS_WIDTH-1:0], saved_device_address[ADDRESS_WIDTH]};
                    end
                endcase
            end
        end

        S_CHECK_ACK: begin
            serial_data_output_enable = 1'b0;
            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING) begin
                            _last_acknowledge = 1'b0;
                            _process_counter  = 2'd2;
                        end
                    end
                    2'd2: begin
                        _serial_clock = 1'b0;
                        if (external_serial_data == 1'b0)
                            _last_acknowledge = 1'b1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        if (last_acknowledge) begin
                            _last_acknowledge = 1'b0;
                            _serial_data      = post_serial_data;
                            _state            = post_state;
                        end else begin
                            _state = S_SEND_STOP;
                        end
                        _process_counter = 2'd0;
                    end
                endcase
            end
        end

        S_WRITE_REG_ADDR: begin
            if (process_counter == 2'd3 && bit_counter == 0)
                serial_data_output_enable = 1'b0;

            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _serial_clock = 1'b0;
                        _bit_counter  = bit_counter - 1'b1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        if (bit_counter == 0) begin
                            _byte_counter = byte_counter - 1'b1;
                            _bit_counter  = 4'd8;
                            _serial_data  = 1'b0;
                            _state        = S_CHECK_ACK;
                            if (byte_counter == 0) begin
                                if (!saved_read_write) begin
                                    _post_state       = S_WRITE_REG_DATA;
                                    _post_serial_data = saved_mosi_data[DATA_WIDTH-1];
                                    _saved_mosi_data  = {saved_mosi_data[DATA_WIDTH-2:0], saved_mosi_data[DATA_WIDTH-1]};
                                    _byte_counter     = NUMBER_OF_DATA_BYTES - 1;
                                end else begin
                                    _post_state       = S_RESTART;
                                    _byte_counter     = {BYTE_COUNTER_WIDTH{1'b0}};
                                    _post_serial_data = 1'b1;
                                end
                            end else begin
                                _post_state = S_WRITE_REG_ADDR;
                            end
                        end else begin
                            _serial_data            = saved_register_address[REGISTER_WIDTH-1];
                            _saved_register_address = {saved_register_address[REGISTER_WIDTH-2:0], saved_register_address[REGISTER_WIDTH-1]};
                        end
                        _process_counter = 2'd0;
                    end
                endcase
            end
        end

        S_WRITE_REG_DATA: begin
            if (process_counter == 2'd3 && bit_counter == 0)
                serial_data_output_enable = 1'b0;

            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _serial_clock = 1'b0;
                        _bit_counter  = bit_counter - 1'b1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        if (bit_counter == 0) begin
                            _byte_counter = byte_counter - 1'b1;
                            _state        = S_CHECK_ACK;
                            _bit_counter  = 4'd8;
                            _serial_data  = 1'b0;
                            if (byte_counter == 0) begin
                                _byte_counter     = {BYTE_COUNTER_WIDTH{1'b0}};
                                _post_state       = S_SEND_STOP;
                                _post_serial_data = 1'b0;
                            end else begin
                                _post_state       = S_WRITE_REG_DATA;
                                _post_serial_data = saved_mosi_data[DATA_WIDTH-1];
                                _saved_mosi_data  = {saved_mosi_data[DATA_WIDTH-2:0], saved_mosi_data[DATA_WIDTH-1]};
                            end
                        end else begin
                            _serial_data     = saved_mosi_data[DATA_WIDTH-1];
                            _saved_mosi_data = {saved_mosi_data[DATA_WIDTH-2:0], saved_mosi_data[DATA_WIDTH-1]};
                        end
                        _process_counter = 2'd0;
                    end
                endcase
            end
        end

        S_RESTART: begin
            if (divider_tick) begin
                case (process_counter)
                    2'd0: _process_counter = 2'd1;
                    2'd1: begin _process_counter = 2'd2; _serial_clock = 1'b1; end
                    2'd2: _process_counter = 2'd3;
                    2'd3: begin
                        _state           = S_START;
                        _post_state      = S_WRITE_ADDR_R;
                        _process_counter = 2'd0;
                        _saved_device_address[0] = 1'b1; // read
                    end
                endcase
            end
        end

        S_WRITE_ADDR_R: begin
            if (process_counter == 2'd3 && bit_counter == 0)
                serial_data_output_enable = 1'b0;

            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _serial_clock = 1'b0;
                        _bit_counter  = bit_counter - 1'b1;
                        _process_counter = 2'd3;
                    end
                    2'd3: begin
                        _process_counter = 2'd0;
                        if (bit_counter == 0) begin
                            _post_state       = S_READ_REG;
                            _post_serial_data = 1'b0;
                            _state            = S_CHECK_ACK;
                            _bit_counter      = 4'd8;
                            _byte_counter     = NUMBER_OF_DATA_BYTES - 1;
                        end else begin
                            _serial_data = saved_device_address[ADDRESS_WIDTH-1];
                        end
                        _saved_device_address = {saved_device_address[ADDRESS_WIDTH-1:0], saved_device_address[ADDRESS_WIDTH]};
                    end
                endcase
            end
        end

        S_READ_REG: begin
            if (process_counter != 2'd3)
                serial_data_output_enable = 1'b0;

            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin
                        _serial_clock          = 1'b0;
                        _miso_data[0]          = external_serial_data;
                        _miso_data[DATA_WIDTH-1:1] = miso_data[DATA_WIDTH-2:0];
                        _bit_counter           = bit_counter - 1'b1;
                        _process_counter       = 2'd3;
                    end
                    2'd3: begin
                        if (bit_counter == 0) begin
                            _byte_counter = byte_counter - 1'b1;
                            _bit_counter  = 4'd8;
                            _serial_data  = 1'b0;
                            if (byte_counter == 0) begin
                                _byte_counter = {BYTE_COUNTER_WIDTH{1'b0}};
                                _state        = S_SEND_NACK;
                            end else begin
                                _post_state   = S_READ_REG;
                                _state        = S_SEND_ACK;
                            end
                        end
                        _process_counter = 2'd0;
                    end
                endcase
            end
        end

        S_SEND_NACK: begin
            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _serial_data = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin _process_counter = 2'd3; _serial_clock = 1'b0; end
                    2'd3: begin _state = S_SEND_STOP; _process_counter = 2'd0; _serial_data = 1'b0; end
                endcase
            end
        end

        S_SEND_ACK: begin
            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _serial_data = 1'b0; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin _process_counter = 2'd3; _serial_clock = 1'b0; end
                    2'd3: begin _state = post_state; _process_counter = 2'd0; end
                endcase
            end
        end

        S_SEND_STOP: begin
            if (divider_tick) begin
                case (process_counter)
                    2'd0: begin _serial_clock = 1'b1; _process_counter = 2'd1; end
                    2'd1: begin
                        if (CLOCK_STRETCHING_MAX_COUNT != 0 && timeout_cycle_timer_expired) begin
                            _process_counter = 2'd0; _state = S_IDLE;
                        end
                        if (external_serial_clock || !CHECK_FOR_CLOCK_STRETCHING)
                            _process_counter = 2'd2;
                    end
                    2'd2: begin _process_counter = 2'd3; _serial_data = 1'b1; end
                    2'd3: begin _state = S_IDLE; end
                endcase
            end
        end

        default: begin
            _state = S_IDLE;
        end
    endcase
end

always_ff @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        state                  <= S_IDLE;
        post_state             <= S_IDLE;
        process_counter        <= 2'd0;
        bit_counter            <= 4'd0;
        last_acknowledge       <= 1'b0;
        miso_data              <= {DATA_WIDTH{1'b0}};
        saved_read_write       <= 1'b0;
        divider_counter        <= 16'd0;
        saved_device_address   <= {(ADDRESS_WIDTH+1){1'b0}};
        saved_register_address <= {REGISTER_WIDTH{1'b0}};
        saved_mosi_data        <= {DATA_WIDTH{1'b0}};
        serial_clock           <= 1'b0;
        serial_data            <= 1'b0;
        post_serial_data       <= 1'b0;
        byte_counter           <= {BYTE_COUNTER_WIDTH{1'b0}};
        busy                   <= 1'b0;
    end else begin
        state                  <= _state;
        post_state             <= _post_state;
        process_counter        <= _process_counter;
        bit_counter            <= _bit_counter;
        last_acknowledge       <= _last_acknowledge;
        miso_data              <= _miso_data;
        saved_read_write       <= _saved_read_write;
        divider_counter        <= _divider_counter;
        saved_device_address   <= _saved_device_address;
        saved_register_address <= _saved_register_address;
        saved_mosi_data        <= _saved_mosi_data;
        serial_clock           <= _serial_clock;
        serial_data            <= _serial_data;
        post_serial_data       <= _post_serial_data;
        byte_counter           <= _byte_counter;
        busy                   <= _busy;
    end
end

endmodule
