	`timescale 1ns / 1ps
	
	//////////////////////////////////////////////////////////////
	// Create a clock divider to satisfy device clock speeds from FPGA clock
	// Hardcoding clock speeds to verify waveforms and functionality with state machine
	// Will be able to update when device specs are acquired 
	//
	// Goal: Create a 100Khz clock from a default 100Mhz clock
	////////////////////////////////////////////////////////////////////////
	
	
	module i2c_clk_divider(
		input wire reset,
		input wire ref_clk,
		output reg i2c_clk
		);
		
		parameter DELAY = 1000;
		initial i2c_clk = 0;
		reg [9:0] count = 0;
		
		always @(posedge ref_clk) begin
				if (count == (DELAY / 2) - 1) begin
					i2c_clk = ~i2c_clk;
					count = 0;
				end
				else begin
					count = count + 1;
				
				end
					
		end
	
	
	endmodule