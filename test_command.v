`timescale 1ns / 1ps

module test_command;

   // Inputs
   reg clock;
   reg reset;

   reg usb_rxf;
   reg usb_txe;

   // Outputs
   wire       usb_rd;
   wire       usb_wr;

   // Bidirs
   wire [7:0]  usb_data;
   reg [7:0]   usb_out;
   reg         usb_oe;

   assign usb_data = usb_oe ? usb_out : 8'bzzzzzzzz;

   // FTDI FIFO interface
   wire [31:0] tx;
   wire        tx_en;
   wire        tx_ce;

   wire [31:0] rx;
   wire        rx_en;
   wire        rx_ce;

   // Memory interface
   wire        cmd_clk;
   wire        cmd_en;
   wire [2:0]  cmd_instr;
   wire [5:0]  cmd_bl;
   wire [29:0] cmd_byte_addr;
   reg 	       cmd_empty;
   reg 	       cmd_full;

   wire        wr_clk;
   wire        wr_en;
   wire [3:0]  wr_mask;
   wire [31:0] wr_data;
   reg 	       wr_full;
   reg 	       wr_empty;
   reg [6:0]   wr_count;
   reg 	       wr_underrun;
   reg 	       wr_error;

   wire        rd_clk;
   wire        rd_en;
   reg [31:0]  rd_data;
   reg 	       rd_full;
   reg 	       rd_empty;
   reg [6:0]   rd_count;
   reg 	       rd_overflow;
   reg 	       rd_error;

   localparam MEM_WRITE    = 3'b000;
   localparam MEM_READ     = 3'b001;
   localparam MEM_WRITE_AP = 3'b010;
   localparam MEM_READ_AP  = 3'b011;
   localparam MEM_REFRESH  = 3'b100;

   ftdififo fifo (.clock(clock),
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

   command cmd (.clock(clock),
		.reset(reset),

		.tx(tx), .tx_en(tx_en), .tx_ce(tx_ce),
		.rx(rx), .rx_en(rx_en), .rx_ce(rx_ce),

		.cmd_clk(cmd_clk), .cmd_en(cmd_en),
		.cmd_instr(cmd_instr), .cmd_bl(cmd_bl),
		.cmd_byte_addr(cmd_byte_addr),
		.cmd_empty(cmd_empty), .cmd_full(cmd_full),

		.wr_clk(wr_clk), .wr_en(wr_en),
		.wr_mask(wr_mask), .wr_data(wr_data),
		.wr_full(wr_full), .wr_empty(wr_empty),
		.wr_count(wr_count), .wr_underrun(wr_underrun),
		.wr_error(wr_error),

		.rd_clk(rd_clk), .rd_en(rd_en),
		.rd_data(rd_data), .rd_full(rd_full), .rd_empty(rd_empty),
		.rd_count(rd_count), .rd_overflow(rd_overflow),
		.rd_error(rd_error));

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

   task send32;
      input [31:0] data;
      begin
	 send(data[31:24]);
	 send(data[23:16]);
	 send(data[15:8]);
	 send(data[7:0]);
      end
   endtask // send32

   task receive;
      output [7:0] data;
      begin
	 usb_txe = 0;
	 @(negedge usb_wr);
	 data = usb_data;
	 #14 usb_txe = 1;
      end
   endtask // receive

   task receive32;
      output [31:0] data;
      begin
	 receive(data[31:24]);
	 receive(data[23:16]);
	 receive(data[15:8]);
	 receive(data[7:0]);
      end
   endtask // receive32

   reg [31:0] received;

   initial begin
      clock = 0;
      reset = 0;
      rd_empty = 1;
      wr_full = 0;
      rd_full = 0;
      cmd_full = 0;
      usb_rxf = 1;
      usb_txe = 0;

      reset = 0;
      #1 reset = 1;
      #99 reset = 0;

      #10;

      send32(32'h4);
      //send32(32'h4);
      //send32(32'h1);

      receive32(received);
      receive32(received);
      
`ifdef SEQUENCE_ONE
      send32(32'h1);
      send32(32'h4);
      send32(32'h2);

      receive32(received);
      receive32(received);

      send32(32'h2);
      send32(32'h4);
      send32(32'h2);
      send32(32'hcafebabe);
      send32(32'h1bad1dea);

      send32(32'h1);
      send32(32'h4);
      send32(32'h2);

      receive32(received);
      receive32(received);
`endif //  `ifdef SEQUENCE_ONE

   end

   always #5 clock = ~clock;

   always @(posedge clock) begin
      if (cmd_en) begin
	 case (cmd_instr)
	   MEM_WRITE:
	     begin
		;
	     end
	   MEM_READ:
	     begin
		rd_data = 0;
		rd_count = cmd_bl + 1;
		rd_empty = 0;
	     end
	 endcase
      end // if (cmd_en)

      if (rd_en) begin
	 rd_data = rd_data + 1;
	 rd_count = rd_count - 1;
	 if (rd_count == 0)
	   rd_empty = 1;
      end

   end // always @ (posedge clock)

endmodule // test_command
