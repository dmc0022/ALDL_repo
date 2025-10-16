	`timescale 1ns / 1ps
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// The purpose of this module is to create the I2C state machine logic as a top level module
	// to drive the read/write transactions
	// 
	// Goal: Create a skeleton outline of an I2c driver module to be able to further implement specific
	// device specifications when acquired
	// 
	// This first example is from the i2c specification sheet to provide an example to simulate in ModelSim
	// Once the device specs we have are available, we can replace the signals using the device data sheets
	// in order to properly interface with the device
	// 
	// TODO: Change sda and scl to function as open-drain (i.e drive only 0 or Z) 
	//		 Bit-phasing
	//		 Start/Stop bits while scl high
	// 		 Implement clock stretching
	// 		 Add read functionality, currently only write
	///////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	module step4(
		input wire  clk,
		input wire  reset,
		input wire  start,
		input wire  [6:0] addr,
		input wire  [7:0] data,
		output reg  i2c_sda,
		output wire i2c_scl,
		output wire ready
		);
		
		localparam STATE_IDLE = 0;
		localparam STATE_START = 1;
		localparam STATE_ADDR = 2;
		localparam STATE_RW = 3;
		localparam STATE_WACK = 4;
		localparam STATE_DATA = 5;
		localparam STATE_STOP = 6;
		localparam STATE_WACK2 = 7;
		
		reg [7:0] state;
		reg [7:0] count;
		reg i2c_scl_enable = 0;
		
		reg [6:0] saved_addr;
		reg [7:0] saved_data;
		
		assign i2c_scl = (i2c_scl_enable == 0) ? 1 : ~clk;
		assign ready = ((reset == 0) && (state == STATE_IDLE)) ? 1 : 0;
		
		always @(negedge clk) begin
			if (reset == 1) begin
				i2c_scl_enable <= 0;
			
			end else begin
				if (( state == STATE_IDLE) || ( state == STATE_START) || (state == STATE_STOP)) begin
					i2c_scl_enable <= 0;
				end
				else begin
					i2c_scl_enable <= 1;
				end
			end
		
		
		
		end
		always @(posedge clk) begin
			if (reset == 1) begin
				state <= 0;
				i2c_sda <= 1;
				count <= 8'd0;
			end
			else begin
				case(state)
					
					STATE_IDLE: begin
						i2c_sda <= 1;
						if (start) begin 
							state <= STATE_START;
							saved_addr <= addr;
							saved_data <= data;
							
						else state <= STATE_IDLE;

					end
					
					STATE_START: begin
						i2c_sda <= 0;
						state <= STATE_ADDR;
						count <= 6;
					
					end
					
					STATE_ADDR: begin
						i2c_sda <= saved_addr[count];
						if (count == 0) state <= STATE_RW;
						else count <= count - 1;
					
					end
					
					STATE_RW: begin
						i2c_sda <= 1;
						state <= STATE_WACK;
						
					
					
					end
					
					STATE_WACK: begin
						state <= STATE_DATA;
						count <= 7;
					
					
					end
					
					STATE_DATA: begin
						i2c_sda <= saved_data[count];
						if (count == 0) state <= STATE_WACK2;
						else count <= count - 1;
					
					end
					
					STATE_WACK2: begin
						state <= STATE_STOP;
					
					end
					
					STATE_STOP: begin
						i2c_sda <= 1;
						state <= STATE_IDLE;
					
					end
				endcase
			
			end
		end
		
		
		
	endmodule