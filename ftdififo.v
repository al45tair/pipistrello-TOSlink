`timescale 1ns / 1ps

module ftdififo(input             clock,
		input 		  reset,

		// USB async FIFO interface
		inout [7:0] 	  usb_data,
		input 		  usb_rxf,
		input 		  usb_txe,
		output reg 	  usb_rd,
		output reg 	  usb_wr,
		output 		  usb_siwua,

		// User interface (32-bit)
		input [31:0] 	  tx,
		input 		  tx_en,
		output reg 	  tx_ce,

		output reg [31:0] rx,
		input 		  rx_en,
		output reg 	  rx_ce);

   assign usb_siwua = 0;

   reg [31:0] 		      tx_data;
   reg [1:0] 		      tx_bytes;

   reg [1:0] 		      rx_bytes;

   localparam STATE_IDLE    = 4'b0000;
   localparam STATE_READ    = 4'b0001; //  0ns - drop RD#
   localparam STATE_READ_1  = 4'b0010; // 10ns
   localparam STATE_READ_2  = 4'b0011; // 20ns - read data
   localparam STATE_READ_3  = 4'b0100; // 30ns - raise RD#
   localparam STATE_READ_4  = 4'b0101; // 40ns

   localparam STATE_WRITE   = 4'b1000; //  0ns - put data on output
   localparam STATE_WRITE_1 = 4'b1001; // 10ns - drop WR#
   localparam STATE_WRITE_2 = 4'b1010; // 20ns - tristate output
   localparam STATE_WRITE_3 = 4'b1011; // 30ns

   reg [4:0] 		      state;
   reg [4:0] 		      next_state;

   reg [7:0] 		      usb_out;
   reg 			      usb_oe;
   assign usb_data = usb_oe ? usb_out : 8'bzzzzzzzz;

   // Synchronise txe/rxf (they're asynchronous)
   reg [1:0] 		      txebuf;
   reg [1:0] 		      rxfbuf;

   always @(posedge clock or posedge reset) begin
      if (reset) begin
	 txebuf = 2'b11;
	 rxfbuf = 2'b11;
      end else begin
	 txebuf = { txebuf[0] | usb_txe, usb_txe };
	 rxfbuf = { rxfbuf[0] | usb_rxf, usb_rxf };
      end
   end

   wire txe = txebuf[1];
   wire rxf = rxfbuf[1];

   // The state machine
   always @(posedge clock or posedge reset) begin
      if (reset)
	state <= STATE_IDLE;
      else
	state <= next_state;
   end

   always @(*) begin
      next_state = state;

      case (state)
	STATE_IDLE:
	  if (rx_en && !rxf)
	    next_state = STATE_READ;
	  else if (!tx_ce && !txe)
	    next_state = STATE_WRITE;

	STATE_READ:
	  next_state = STATE_READ_1;
	STATE_READ_1:
	  next_state = STATE_READ_2;
	STATE_READ_2:
	  next_state = STATE_READ_3;
	STATE_READ_3:
	  next_state = STATE_READ_4;
	STATE_READ_4:
	  next_state = STATE_IDLE;

	STATE_WRITE:
	  next_state = STATE_WRITE_1;
	STATE_WRITE_1:
	  next_state = STATE_WRITE_2;
	STATE_WRITE_2:
	  next_state = STATE_WRITE_3;
	STATE_WRITE_3:
	  next_state = STATE_IDLE;
      endcase // case (state)
   end

   always @(posedge clock or posedge reset) begin
      if (reset) begin
	 usb_oe <= 1'b0;
	 usb_rd <= 1'b1;
	 usb_wr <= 1'b1;
	 tx_ce <= 1'b1;
	 rx_ce <= 1'b0;
	 rx_bytes <= 2'b0;
	 tx_bytes <= 2'b0;
      end else begin
	 usb_oe <= 1'b0;
	 usb_rd <= 1'b1;
	 usb_wr <= 1'b1;
	 rx_ce <= 1'b0;

	 case (next_state)
	   STATE_IDLE:
	     if (tx_ce && tx_en) begin
		tx_data <= tx;
		tx_ce <= 1'b0;
	     end

	   STATE_READ:
	     usb_rd <= 1'b0;
	   STATE_READ_1:
	     usb_rd <= 1'b0;
	   STATE_READ_2:
	     begin
		usb_rd <= 1'b0;
		rx <= { rx[23:0], usb_data };
	     end
	   STATE_READ_3:
	     begin
		if (rx_bytes == 3)
		  rx_ce <= 1'b1;
		rx_bytes <= rx_bytes + 1'b1;
	     end

	   STATE_READ_4:
	     ;

	   STATE_WRITE:
	     begin
		usb_oe <= 1'b1;
		usb_out <= tx_data[31:24];
	     end
	   STATE_WRITE_1:
	     begin
		usb_oe <= 1'b1;
		usb_wr <= 1'b0;
		tx_data <= { tx_data[23:0], 8'b0 };
	     end
	   STATE_WRITE_2:
	     usb_wr <= 1'b0;
	   STATE_WRITE_3:
	     begin
		usb_wr <= 1'b0;
		if (tx_bytes == 3)
		  tx_ce <= 1'b1;
		tx_bytes <= tx_bytes + 1'b1;
	     end
	 endcase
      end
   end

endmodule // ftdififo
