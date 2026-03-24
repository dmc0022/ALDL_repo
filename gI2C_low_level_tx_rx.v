//  ------------------------------------------------------------------------------
//
//  gI2C_low_level_tx_rx.v -- low level I2C comm for Nintendo Class Mini controller
//
//  Copyright (C) 2020 Michael Gansler
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  ------------------------------------------------------------------------------
//
//  Module:       gI2C_low_leveL_tx_rx.v
//
//  Objective:    Performs basic low-level I2C Master operations to 
//                support communications witha Nintendo Class Mini controller.
//
//  Assumptions:  - 40 MHz input clock
//                  Altera MAX10 FPGA
//                - Does not check for ACK's from slave !!
//                - Does not perform clock stretching
//                - Development done on Terasic DE10-Lite board with 
//                - No clock domain crossings accomodated.  If this module 
//                  were used in an actual situation with clock domain 
//                  crossings or asynchronous inputs, more attention 
//                  (i.e. code changes) would be necessary to manage the 
//                  situation.
//
//  Notes:
//
//  This module performs a number of low-level I2C Master activities.  The
//  intention is that a higher level module coordinates the overall
//  transaction, while this module is commanded by that module 
//  to perform any of the following operations:
//
//    1.  create a start condtion
//    2.  create a stop condtion
//    3.  transmit a byte from master to slave
//    4.  receive a byte from slave to master
//
//  Note that clock stretching is not implemented since this
//  appeared to not be necessary for the the Nintendo Classic Mini 
//  retro controller interfacing application.  Likewise, ACKs/NACKs
//  from the slave are not evaluated.
//
//  The diagram below shows typical  I2C SDA and SCL waverforms:
//
//      START                                                STOP 
//      COND                                                 COND
//      ____       __  __  __  __  __  __  __  __  __         ___
//  SDA     |_____/A6\/A5\/A4\/A3\/A2\/A1\/A0\/RW\/AK\_______|
//
//                  ^   ^   ^   ^   ^   ^   ^   ^   ^
//      ______       _   _   _   _   _   _   _   _   _      _____
//  SCL       |_____| |_| |_| |_| |_| |_| |_| |_| |_| |____|
//
//
// ^'s show SCL rising edge, where receiver samples SDA.
//
// The above shows the case of TX'ing the Address (7 bits) and the
// R/*W bit followed by receiving an ACK from the receiver.  
//
// Data byte transfers in the opposite direction are analogous, 
// 8 bits of data + an ACK/NACK bit.
//
`default_nettype none            // Require all nets to be declared before used.
                                 // --> typo'd net names get trapped

module gI2C_low_level_tx_rx
#(
   parameter TICKS_PER_I2C_CLK_PERIOD = 400   // Ticks of input clock per I2C SCL period (10 usec).
)
(
   //
   // INPUTS
   //
   input wire       clk,         // Input clock, tested with 40 MHz
   
   input wire       rst,         // Reset input
   
   input wire [2:0] command,     // Input command for which I2C operation to create
   
   input wire [7:0] tx_byte,     // Byte to transmit from master to slave (if requested)

   input wire       ACK,         // 1=Master ACKs after slave read, 0=Master NACKs
   
   //
   // OUTPUTS
   //
   output reg [7:0] read_byte,   // Byte read from slave (if requested)
   
   output reg       busy,        // Indicates that this module is busy performing a sequence of actions
   
   output reg       data_valid,  // Indicates that a byte has been read from the slave and is available
   
   output reg       done,        // Indicates that requested action is complete.
   
   //
   // I2C I/O
   //
   input wire       i_sda,       // Input from tristate driver output, connected externally to SDA line   
   
   output reg       o_sda,       // Output from this module indicating how to drive I2C SDA externally
   
   output reg       o_scl        // Output from this module indicating how to drive I2C SCL externally
);

//
// Legal values for input signal 'command'.   This driver expects to
// see a single clock duration pulse on 'command' to trigger one
// of the possible sequences below.
//
localparam DRVR_CMD_NONE        = 3'd0;
localparam DRVR_CMD_WRITE       = 3'd1;
localparam DRVR_CMD_READ        = 3'd2;
localparam DRVR_CMD_START_COND  = 3'd3;
localparam DRVR_CMD_STOP_COND   = 3'd4;

//
// Legal values for 'drvr_state' FSM.
//
localparam IDLE           = 3'b000; // 0
localparam TX_BYTE        = 3'b001; // 1
localparam RX_BYTE        = 3'b010; // 2
localparam START_COND     = 3'b011; // 3
localparam STOP_COND      = 3'b100; // 4
localparam DELAY          = 3'b101; // 5

reg   [2:0]  state = IDLE;          // State variable for main state machine

reg   [3:0]  bit_idx = 8;           // index of bit currently TX'ing or RX'ing

reg   [8:0]  shifted_tx_byte = 0;   // byte transmitting.  9 bits since data byte + ACK

reg  [15:0]  ctr = 0;    // Generic counter, counts at input clk rate.
                         // Used for timing I2C waveforms/SCL.
                         //
                         // Note: if use a faster input clock than 40MHz, 
                         // make sure this ctr has sufficient width.
                         //
                         // ctr must be able to count up to at least 9 SCL
                         // clock periods, which is:
                         //
                         //   9 / (100KHz) = 90 usec.
                         //
                         // For a 40 MHz input clk, this means ctr's max 
                         // value is: 
                         //
                         //   90 usec * 40MHz = 3600 counts
                         //
                                  
//
// Main state machine
//
always @(posedge clk) begin

   if (rst) begin
   
      state <= IDLE;

   end else begin
   
      case (state)

      //
      // IDLE - wait for any of the 4 triggers:
      //
      //   - transmit a byte
      //   - receive a byte 
      //   - create a start condition
      //   - create a stop condition
      //      
      IDLE: 
      begin
      
         busy       <= 1'b0;
         done       <= 1'b0;
         data_valid <= 1'b0;
         bit_idx    <= 8;
         ctr        <= 0;

         if (command==DRVR_CMD_WRITE) begin          // Write a byte from Master to Slave 
         
            busy            <= 1'b1;
            shifted_tx_byte <= {tx_byte, 1'b1};      // SDA is 1 (HiZ) during ACK cycle to allow slave to ACK/NACK
            state           <= TX_BYTE;
            
         end else if (command==DRVR_CMD_READ) begin  // Read a byte from Slave to Master
         
            busy      <= 1'b1;
            read_byte <= 7'd0;
            state     <= RX_BYTE;                    // Move on to next state
            
         end else if (command==DRVR_CMD_START_COND) begin  // Generate START condition
            
            busy  <= 1'b1;
            state <= START_COND;                     // Move on to next state
            
         end else if (command==DRVR_CMD_STOP_COND) begin   // Generate STOP condition
         
            busy  <= 1'b1;
            state <= STOP_COND;                      // Move on to next state
            
         end
         
      end

      //
      // Generate START condition
      //
      START_COND:
      begin
      
         ctr <= ctr + 1;
         
         //
         // Regulate timing of START condition.  Each phase lasts
         // 3 SCL clock ticks long.  
         //
         // Recall that a START condition is a falling edge of SDA
         // while SCL is high.
         //
         if (ctr<TICKS_PER_I2C_CLK_PERIOD*3) begin     // SDA H, SCL H
            
            o_sda <= 1'b1;
            o_scl <= 1'b1;
            
         end else if (ctr<TICKS_PER_I2C_CLK_PERIOD*6)  // SDA L, SCL H
            
            o_sda <= 1'b0;
         
         else if (ctr<TICKS_PER_I2C_CLK_PERIOD*9)      // SDA L, SCL L
         
            o_scl <= 1'b0;

         else begin

            ctr   <= 0;
            state <= DELAY;
            
         end
         
      end
      
      //
      // Generate STOP condition
      //
      STOP_COND:
      begin
      
         ctr <= ctr + 1;
         
         //
         // Regulate timing of STOP condition.  Each phase lasts
         // 3 SCL clock ticks long.  
         //
         // Recall that a STOP condition is a rising edge of SDA
         // while SCL is high.
         //
         if (ctr<TICKS_PER_I2C_CLK_PERIOD*3) begin     // SDA L, SCL L
            
               o_sda <= 1'b0;
               o_scl <= 1'b0;
               
         end else if (ctr<TICKS_PER_I2C_CLK_PERIOD*6)  // SDA L, SCL H
            
            o_scl <= 1'b1;
         
         else if (ctr<TICKS_PER_I2C_CLK_PERIOD*9)      // SDA H, SCL H
         
            o_sda <= 1'b1;

         else begin
         
            ctr   <= 0;
            state <= DELAY;
            
         end
         
      end

      //
      // Transmit a byte from master to slave
      //
      TX_BYTE:
      begin
      
         ctr <= ctr + 1;
         
         if (ctr<=TICKS_PER_I2C_CLK_PERIOD/2)  begin    // Low portion of SCL clk period

               o_scl <= 1'b0;                          
               if (ctr>TICKS_PER_I2C_CLK_PERIOD/5)      // TX bit over SDA, but only once SCL
                  o_sda <= shifted_tx_byte[bit_idx];    // has been low for 2 usec to avoid
                                                        // transitioning SDA during SCL high.
            
         end else if (ctr<TICKS_PER_I2C_CLK_PERIOD-1)   // High portion of SCL clk period

            o_scl <= 1'b1;
            
         else begin                           // SCL clk period is complete.

            ctr <= 0;
            
            if (bit_idx>0)                    // If not yet iterated through all 9 bits
               bit_idx <= bit_idx - 1;        // continue with next lower bit.
            else begin
               o_scl <= 0;                    // If done with all 9 bits, bring SCL low
               ctr   <= 0;                    // and move on to DELAY state.
               state <= DELAY;
            end
            
         end
         
      end


      //
      // Read a byte from slave to master
      //
      RX_BYTE:
      begin
      
         ctr <= ctr + 1;
         
         if (ctr<=TICKS_PER_I2C_CLK_PERIOD/2) begin    // Low portion of SCL clk period

            o_scl <= 1'b0;
            
            if (ctr>TICKS_PER_I2C_CLK_PERIOD/5) begin  // Holdoff SDA transition for 2 usec to prevent
                                                       // changing SDA while SCL still high.
               if (bit_idx>=1 || !ACK)            
                  o_sda <= 1'b1;                       // HiZ SDA if receiving bits from slave, or master is NACKing.
               else
                  o_sda <= 1'b0;                       // Received all bits from slave so have master ACK
                  
            end
               
         end else if (ctr<TICKS_PER_I2C_CLK_PERIOD-1) begin  // High portion of SCL clk period

            o_scl <= 1'b1;
            if (bit_idx>=1)                     
               read_byte[bit_idx-1] <= i_sda;          // Read bit from slave and store

         end else begin                   // SCL clk period is complete
         
            ctr <= 0;
            
            if (bit_idx>0)                // If not yet iterated through all 9 bits.
                                          // continue with next lower bit
               bit_idx <= bit_idx - 1;    
               
            else begin
            
               ctr        <= 0;        // Done with all 9 bits, 
               o_scl      <= 0;        // so bring SCL low,
               o_sda      <= 1;        // and release SDA.
               data_valid <= 1;        // Set data valid (for one clk tick),
               state      <= DELAY;    // and move on to DELAY state.
               
            end
            
         end
         
      end

      //
      // Perform 3 SCL period delay after action completed.
      // Creates heart-warming inter-character spacing.
      //
      DELAY:                 
      begin                
      
         data_valid <= 0;    // Clear flag set during RX_BYTE state

         ctr <= ctr + 1;

         if (ctr>(TICKS_PER_I2C_CLK_PERIOD*3)) begin
         
            done  <= 1;      // Set overall done flag, indicating action+delay are complete.
            state <= IDLE;   // Return to IDLE state, awaiting next command
            
         end
         
      end

      //
      // Should never get here unless something goes wrong
      //
      default:
      begin
      
         state <= IDLE;      
         
      end
      
      endcase
      
   end  // end of else-reset
   
end // end of always


endmodule