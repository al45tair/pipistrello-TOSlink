`timescale 1ns / 1ps

module test_tx;

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

   reg [7:0]   received;

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

   task receive;
      output [7:0] data;
      begin
	 usb_txe = 0;
	 @(negedge usb_wr);
	 data = usb_data;
	 #14 usb_txe = 1;
      end
   endtask // receive

   initial begin
      clock = 0;
      reset = 1;
      usb_rxf = 1;
      usb_txe = 1;
      usb_oe = 0;
      rx_en = 0;
      tx_en = 0;

      #100 reset = 0;

      #5;
      
      tx = 32'habadbabe;
      tx_en = 1;
      #10 tx_en = 0;

      receive(received);
      receive(received);
      receive(received);
      receive(received);

      @(posedge tx_ce);

      #33;

      tx = 32'hfeedf00d;
      tx_en = 1;
      #10 tx_en = 0;
      
      receive(received);
      receive(received);
      receive(received);
      receive(received);
   end // initial begin

   always #5 clock = ~clock;

endmodule // test_tx
