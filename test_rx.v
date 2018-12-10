`timescale 1ns / 1ps

module test_rx;

   reg clock;
   reg reset;

   wire [7:0] usb_data;
   reg 	      usb_rxf;
   reg 	      usb_txe;
   wire       usb_rd;
   wire       usb_wr;
   wire       usb_siwua;

   reg [31:0] tx;
   reg 	      tx_en;
   wire       tx_ce;

   wire [31:0] rx;
   reg 	       rx_en;
   wire        rx_ce;

   reg [7:0]   usb_out;
   reg 	       usb_oe;
   assign usb_data = usb_oe ? usb_out : 8'bzzzzzzzz;

   ftdififo fifo(.clock(clock),
		 .reset(reset),

		 .usb_data(usb_data),
		 .usb_rxf(usb_rxf),
		 .usb_txe(usb_txe),
		 .usb_rd(usb_rd),
		 .usb_wr(usb_wr),
		 .usb_siwua(usb_siwua),

		 .tx(tx),
		 .tx_en(tx_en),
		 .tx_ce(tx_ce),

		 .rx(rx),
		 .rx_en(rx_en),
		 .rx_ce(rx_ce));

   task send;
      input [7:0] data;
      begin
	 usb_rxf = 0;
	 @(negedge usb_rd);
	 usb_oe = 1;
	 #14 usb_out = data;
	 @(posedge usb_rd);
	 #14 usb_oe = 0;
	 usb_rxf = 1;
      end
   endtask // send

   initial begin
      clock = 0;
      reset = 1;
      usb_rxf = 1;
      usb_txe = 1;
      usb_oe = 0;
      rx_en = 0;
      tx_en = 0;
      
      #100 reset = 0;

      rx_en = 1;

      send(8'hab);
      send(8'had);
      send(8'hba);
      send(8'hbe);

      #33;

      send(8'hfe);
      send(8'hed);
      send(8'hf0);
      send(8'h0d);
   end // initial begin

   always #5 clock = ~clock;

endmodule
