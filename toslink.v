`timescale 1ns / 1ps

module toslink(
    input 	  sys_clk50M,
    input 	  sys_reset,

    // TOSLink input
    input 	  tos_in,

    // USB async FIFO Interface
    inout [7:0]   usb_data,
    input 	  usb_rxf,
    input 	  usb_txe,
    output 	  usb_rd,
    output 	  usb_wr,
    output 	  usb_siwua,

    // DRAM interface
    inout [15:0]  mcb3_dram_dq,
    output [12:0] mcb3_dram_a,
    output [1:0]  mcb3_dram_ba,
    output 	  mcb3_dram_cke,
    output 	  mcb3_dram_ras_n,
    output 	  mcb3_dram_cas_n,
    output 	  mcb3_dram_we_n,
    output 	  mcb3_dram_dm,
    inout 	  mcb3_dram_udqs,
    inout 	  mcb3_rzq,
    output 	  mcb3_dram_udm,
    inout 	  mcb3_dram_dqs,
    output 	  mcb3_dram_ck,
    output 	  mcb3_dram_ck_n,

    // LEDs
    output 	  done_led,
    output 	  sync_led,

    // Debug
    output [15:0] debug);

   // 100MHz clock from memory module
   wire        clock;
   wire        reset;

   wire        c3_calib_done;

   // Memory port 0
   wire        port0_cmd_clk;
   wire        port0_cmd_en;
   wire [2:0]  port0_cmd_instr;
   wire [5:0]  port0_cmd_bl;
   wire [29:0] port0_cmd_byte_addr;
   wire        port0_cmd_empty;
   wire        port0_cmd_full;
   wire        port0_wr_clk;
   wire        port0_wr_en;
   wire [3:0]  port0_wr_mask;
   wire [31:0] port0_wr_data;
   wire        port0_wr_full;
   wire        port0_wr_empty;
   wire [6:0]  port0_wr_count;
   wire        port0_wr_underrun;
   wire        port0_wr_error;
   wire        port0_rd_clk;
   wire        port0_rd_en;
   wire [31:0] port0_rd_data;
   wire        port0_rd_full;
   wire        port0_rd_empty;
   wire [6:0]  port0_rd_count;
   wire        port0_rd_overflow;
   wire        port0_rd_error;

   // Memory port 1
   wire        port1_cmd_clk;
   wire        port1_cmd_en;
   wire [2:0]  port1_cmd_instr;
   wire [5:0]  port1_cmd_bl;
   wire [29:0] port1_cmd_byte_addr;
   wire        port1_cmd_empty;
   wire        port1_cmd_full;
   wire        port1_wr_clk;
   wire        port1_wr_en;
   wire [3:0]  port1_wr_mask;
   wire [31:0] port1_wr_data;
   wire        port1_wr_full;
   wire        port1_wr_empty;
   wire [6:0]  port1_wr_count;
   wire        port1_wr_underrun;
   wire        port1_wr_error;
   wire        port1_rd_clk;
   wire        port1_rd_en;
   wire [31:0] port1_rd_data;
   wire        port1_rd_full;
   wire        port1_rd_empty;
   wire [6:0]  port1_rd_count;
   wire        port1_rd_overflow;
   wire        port1_rd_error;

   // FTDI FIFO
   wire [31:0] fifo_tx;
   wire        fifo_tx_en;
   wire        fifo_tx_ce;
   wire [31:0] fifo_rx;
   wire        fifo_rx_en;
   wire        fifo_rx_ce;

   // Capture interface
   wire [31:0] capture_frames;
   wire [31:0] capture_frames_remaining;
   wire        capture_start;
   wire        capture_done;
   wire        capture_sync;

   wire [2:0]  cs_word_sel;
   wire [31:0] cs_word;

   // Tie the LEDs to the capture interface
   assign done_led = capture_done;
   assign sync_led = capture_sync;

   // Control logic
   command command(.clock(clock),
                   .reset(reset),

		   .capture_frames(capture_frames),
		   .capture_start(capture_start),
		   .capture_done(capture_done),
		   .capture_frames_remaining(capture_frames_remaining),
		   .capture_sync(capture_sync),

		   .cs_word_sel(cs_word_sel),
		   .cs_word(cs_word),

                   .rx(fifo_rx),
                   .rx_en(fifo_rx_en),
                   .rx_ce(fifo_rx_ce),

                   .tx(fifo_tx),
                   .tx_en(fifo_tx_en),
                   .tx_ce(fifo_tx_ce),

                   .cmd_clk(port0_cmd_clk),
                   .cmd_en(port0_cmd_en),
                   .cmd_instr(port0_cmd_instr),
                   .cmd_bl(port0_cmd_bl),
                   .cmd_byte_addr(port0_cmd_byte_addr),
                   .cmd_empty(port0_cmd_empty),
                   .cmd_full(port0_cmd_full),

                   .wr_clk(port0_wr_clk),
                   .wr_en(port0_wr_en),
                   .wr_mask(port0_wr_mask),
                   .wr_data(port0_wr_data),
                   .wr_full(port0_wr_full),
                   .wr_empty(port0_wr_empty),
                   .wr_count(port0_wr_count),
                   .wr_underrun(port0_wr_underrun),
                   .wr_error(port0_wr_error),

                   .rd_clk(port0_rd_clk),
                   .rd_en(port0_rd_en),
                   .rd_data(port0_rd_data),
                   .rd_full(port0_rd_full),
                   .rd_empty(port0_rd_empty),
                   .rd_count(port0_rd_count),
                   .rd_overflow(port0_rd_overflow),
                   .rd_error(port0_rd_error));

   // The FTDI fifo
   ftdififo fifo(.clock(clock),
                 .reset(reset),
                 .usb_data(usb_data),
                 .usb_rxf(usb_rxf),
                 .usb_txe(usb_txe),
                 .usb_rd(usb_rd),
                 .usb_wr(usb_wr),
                 .usb_siwua(usb_siwua),
                 .tx(fifo_tx),
                 .tx_en(fifo_tx_en),
                 .tx_ce(fifo_tx_ce),
                 .rx(fifo_rx),
                 .rx_en(fifo_rx_en),
                 .rx_ce(fifo_rx_ce));

   // TOSLink data capture
   capture capture(.clock(clock),
		   .reset(reset),

		   .tos_in(tos_in),
		   .frames(capture_frames),
		   .start(capture_start),
		   .frames_remaining(capture_frames_remaining),
		   .done(capture_done),
		   .sync(capture_sync),

		   .cs_word_sel(cs_word_sel),
		   .cs_word(cs_word),

                   .cmd_clk(port1_cmd_clk),
                   .cmd_en(port1_cmd_en),
                   .cmd_instr(port1_cmd_instr),
                   .cmd_bl(port1_cmd_bl),
                   .cmd_byte_addr(port1_cmd_byte_addr),
                   .cmd_empty(port1_cmd_empty),
                   .cmd_full(port1_cmd_full),

                   .wr_clk(port1_wr_clk),
                   .wr_en(port1_wr_en),
                   .wr_mask(port1_wr_mask),
                   .wr_data(port1_wr_data),
                   .wr_full(port1_wr_full),
                   .wr_empty(port1_wr_empty),
                   .wr_count(port1_wr_count),
                   .wr_underrun(port1_wr_underrun),
                   .wr_error(port1_wr_error),

                   .rd_clk(port1_rd_clk),
                   .rd_en(port1_rd_en),
                   .rd_data(port1_rd_data),
                   .rd_full(port1_rd_full),
                   .rd_empty(port1_rd_empty),
                   .rd_count(port1_rd_count),
                   .rd_overflow(port1_rd_overflow),
                   .rd_error(port1_rd_error),

		   .debug(debug));

   // The memory
   memory memory(.c3_sys_clk(sys_clk50M),
		 .c3_sys_rst_i(sys_reset),
		 .c3_calib_done(c3_calib_done),
		 .c3_clk0(clock),
		 .c3_rst0(reset),

		 // DRAM interface
		 .mcb3_dram_dq(mcb3_dram_dq),
		 .mcb3_dram_a(mcb3_dram_a),
		 .mcb3_dram_ba(mcb3_dram_ba),
		 .mcb3_dram_cke(mcb3_dram_cke),
		 .mcb3_dram_ras_n(mcb3_dram_ras_n),
		 .mcb3_dram_cas_n(mcb3_dram_cas_n),
		 .mcb3_dram_we_n(mcb3_dram_we_n),
		 .mcb3_dram_dm(mcb3_dram_dm),
		 .mcb3_dram_udqs(mcb3_dram_udqs),
		 .mcb3_rzq(mcb3_rzq),
		 .mcb3_dram_udm(mcb3_dram_udm),
		 .mcb3_dram_dqs(mcb3_dram_dqs),
		 .mcb3_dram_ck(mcb3_dram_ck),
		 .mcb3_dram_ck_n(mcb3_dram_ck_n),

		 // Port 0
		 .c3_p0_cmd_clk(port0_cmd_clk),
		 .c3_p0_cmd_en(port0_cmd_en),
		 .c3_p0_cmd_instr(port0_cmd_instr),
		 .c3_p0_cmd_bl(port0_cmd_bl),
		 .c3_p0_cmd_byte_addr(port0_cmd_byte_addr),
		 .c3_p0_cmd_empty(port0_cmd_empty),
		 .c3_p0_cmd_full(port0_cmd_full),
		 .c3_p0_wr_clk(port0_wr_clk),
		 .c3_p0_wr_en(port0_wr_en),
		 .c3_p0_wr_mask(port0_wr_mask),
		 .c3_p0_wr_data(port0_wr_data),
		 .c3_p0_wr_full(port0_wr_full),
		 .c3_p0_wr_empty(port0_wr_empty),
		 .c3_p0_wr_count(port0_wr_count),
		 .c3_p0_wr_underrun(port0_wr_underrun),
		 .c3_p0_wr_error(port0_wr_error),
		 .c3_p0_rd_clk(port0_rd_clk),
		 .c3_p0_rd_en(port0_rd_en),
		 .c3_p0_rd_data(port0_rd_data),
		 .c3_p0_rd_full(port0_rd_full),
		 .c3_p0_rd_empty(port0_rd_empty),
		 .c3_p0_rd_count(port0_rd_count),
		 .c3_p0_rd_overflow(port0_rd_overflow),
		 .c3_p0_rd_error(port0_rd_error),

		 // Port 1
		 .c3_p1_cmd_clk(port1_cmd_clk),
		 .c3_p1_cmd_en(port1_cmd_en),
		 .c3_p1_cmd_instr(port1_cmd_instr),
		 .c3_p1_cmd_bl(port1_cmd_bl),
		 .c3_p1_cmd_byte_addr(port1_cmd_byte_addr),
		 .c3_p1_cmd_empty(port1_cmd_empty),
		 .c3_p1_cmd_full(port1_cmd_full),
		 .c3_p1_wr_clk(port1_wr_clk),
		 .c3_p1_wr_en(port1_wr_en),
		 .c3_p1_wr_mask(port1_wr_mask),
		 .c3_p1_wr_data(port1_wr_data),
		 .c3_p1_wr_full(port1_wr_full),
		 .c3_p1_wr_empty(port1_wr_empty),
		 .c3_p1_wr_count(port1_wr_count),
		 .c3_p1_wr_underrun(port1_wr_underrun),
		 .c3_p1_wr_error(port1_wr_error),
		 .c3_p1_rd_clk(port1_rd_clk),
		 .c3_p1_rd_en(port1_rd_en),
		 .c3_p1_rd_data(port1_rd_data),
		 .c3_p1_rd_full(port1_rd_full),
		 .c3_p1_rd_empty(port1_rd_empty),
		 .c3_p1_rd_count(port1_rd_count),
		 .c3_p1_rd_overflow(port1_rd_overflow),
		 .c3_p1_rd_error(port1_rd_error));


endmodule
