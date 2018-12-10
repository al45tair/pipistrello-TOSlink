`timescale 1ns / 1ps

module command(input             clock,
	       input 		 reset,

	       // Capture interface
	       output reg [31:0] capture_frames,
	       output reg 	 capture_start,
	       input [31:0] 	 capture_frames_remaining,
	       input 		 capture_done,
	       input 		 capture_sync,

	       output reg [2:0]  cs_word_sel,
	       input [31:0] 	 cs_word,

	       // FTDI FIFO interface
	       output reg [31:0] tx,
	       output reg 	 tx_en,
	       input 		 tx_ce,

	       input [31:0] 	 rx,
	       output reg 	 rx_en,
	       input 		 rx_ce,

               // Memory interface
               output 		 cmd_clk,
               output reg 	 cmd_en,
               output reg [2:0]  cmd_instr,
               output reg [5:0]  cmd_bl,
               output reg [29:0] cmd_byte_addr,
               input 		 cmd_empty,
               input 		 cmd_full,

               output 		 wr_clk,
               output reg 	 wr_en,
               output [3:0] 	 wr_mask,
               output reg [31:0] wr_data,
               input 		 wr_full,
               input 		 wr_empty,
               input [6:0] 	 wr_count,
               input 		 wr_underrun,
               input 		 wr_error,

               output 		 rd_clk,
               output reg 	 rd_en,
               input [31:0] 	 rd_data,
               input 		 rd_full,
               input 		 rd_empty,
               input [6:0] 	 rd_count,
               input 		 rd_overflow,
               input 		 rd_error);

   assign cmd_clk = clock;
   assign wr_clk = clock;
   assign rd_clk = clock;
   assign wr_mask = 0;

   localparam CMD_NOP      = 31'd0;
   localparam CMD_READ     = 31'd1;
   localparam CMD_WRITE    = 31'd2;
   localparam CMD_CAPTURE  = 31'd3;
   localparam CMD_STATUS   = 31'd4;
   localparam CMD_CHSTATUS = 31'd5;

   localparam STATE_IDLE             = 4'b0000;
   localparam STATE_CMD              = 4'b0001;
   localparam STATE_ARGS             = 4'b0010;
   localparam STATE_READ             = 4'b0011;
   localparam STATE_READ_BURST       = 4'b0100;
   localparam STATE_READ_BURST_WAIT  = 4'b0101;
   localparam STATE_WRITE            = 4'b0110;
   localparam STATE_WRITE_BURST      = 4'b0111;
   localparam STATE_CAPTURE          = 4'b1000;
   localparam STATE_STATUS           = 4'b1001;
   localparam STATE_STATUS_2         = 4'b1010;
   localparam STATE_STATUS_3         = 4'b1011;
   localparam STATE_CHSTATUS         = 4'b1100;
   localparam STATE_CHSTATUS_2       = 4'b1101;
   localparam STATE_CHSTATUS_3       = 4'b1110;

   localparam MEM_WRITE    = 3'b000;
   localparam MEM_READ     = 3'b001;
   localparam MEM_WRITE_AP = 3'b010;
   localparam MEM_READ_AP  = 3'b011;
   localparam MEM_REFRESH  = 3'b100;

   reg [31:0] command;
   reg [31:0] args[0:7];

   reg [2:0]  nargs;
   reg [2:0]  argndx;

   reg [3:0]  state;
   reg [3:0]  next_state;

   initial state = STATE_IDLE;
   initial capture_start = 1'b0;

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
	  if (rx_ce)
	    next_state = STATE_CMD;
	STATE_CMD:
	  // Handle commands with no args straight away
	  case (command)
	    CMD_NOP:
	      next_state = STATE_IDLE;
	    CMD_STATUS:
	      next_state = STATE_STATUS;
	    CMD_CHSTATUS:
	      next_state = STATE_CHSTATUS;
	    CMD_READ, CMD_WRITE, CMD_CAPTURE:
	      next_state = STATE_ARGS;
	    default:
	      next_state = STATE_IDLE;
	  endcase
	STATE_ARGS:
	  if (nargs == argndx) begin
	     case (command)
	       CMD_READ:
		 next_state = STATE_READ;
	       CMD_WRITE:
		 next_state = STATE_WRITE;
	       CMD_CAPTURE:
		 next_state = STATE_CAPTURE;
	     endcase // case (command)
	  end // if (nargs == argndx)
	STATE_READ:
	  next_state = STATE_READ_BURST;
	STATE_READ_BURST:
	  if (tx_en)
	    next_state = STATE_READ_BURST_WAIT;
	STATE_READ_BURST_WAIT:
	  if (burst_len == 0) begin
	     if (args[1] == 0)
	       next_state = STATE_IDLE;
	     else
	       next_state = STATE_READ;
	  end else begin
	     next_state = STATE_READ_BURST;
	  end
	STATE_WRITE:
	  next_state = STATE_WRITE_BURST;
	STATE_WRITE_BURST:
	  if (burst_len == 0) begin
	     if (args[1] == 0)
	       next_state = STATE_IDLE;
	     else
	       next_state = STATE_WRITE;
	  end
	STATE_STATUS:
	  if (tx_en)
	    next_state = STATE_STATUS_2;
	STATE_STATUS_2:
	  next_state = STATE_STATUS_3;
	STATE_STATUS_3:
	  if (tx_en)
	    next_state = STATE_IDLE;
	STATE_CHSTATUS:
	  next_state = STATE_CHSTATUS_2;
	STATE_CHSTATUS_2:
	  if (tx_en)
	    next_state = STATE_CHSTATUS_3;
	STATE_CHSTATUS_3:
	  if (cs_word_sel == 3'd6)
	    next_state = STATE_IDLE;
	  else
	    next_state = STATE_CHSTATUS_2;
	default:
	  next_state = STATE_IDLE;
      endcase // case (state)
   end

   wire [2:0] next_argndx = argndx + 1'b1;

   // Burst control
   wire [5:0] to_do = args[1] > 32 ? 32 : args[1];
   reg [5:0]  burst_len;

   always @(posedge clock or posedge reset) begin

      if (reset) begin
	 capture_start <= 1'b0;
	 tx_en <= 1'b0;
	 rx_en <= 1'b0;
	 rd_en <= 1'b0;
	 wr_en <= 1'b0;
	 cmd_en <= 1'b0;
	 capture_start <= 1'b0;
      end else begin
	 tx_en <= 1'b0;
	 rx_en <= 1'b0;
	 rd_en <= 1'b0;
	 wr_en <= 1'b0;
	 cmd_en <= 1'b0;
	 capture_start <= 1'b0;

	 case (next_state)
	   STATE_IDLE:
	     rx_en <= 1'b1;
	   STATE_CMD:
	     begin
		command <= rx;
		argndx <= 0;

		case (rx)
		  CMD_NOP:
		    nargs <= 0;
		  CMD_READ:
		    begin
		       nargs <= 2;
		       rx_en <= 1'b1;
		    end
		  CMD_WRITE:
		    begin
		       nargs <= 2;
		       rx_en <= 1'b1;
		    end
		  CMD_CAPTURE:
		    begin
		       nargs <= 1;
		       rx_en <= 1'b1;
		    end
		  default:
		    nargs <= 0;
		endcase // case (rx)
	     end // case: STATE_CMD
	   STATE_ARGS:
	     begin
		if (!rx_ce)
		  rx_en <= 1'b1;
		else begin
		   args[argndx] <= rx;
		   argndx <= next_argndx;
		   rx_en <= next_argndx != nargs;
		end
	     end // case: STATE_ARGS

	   // Command implementations
	   STATE_READ:
	     begin
		args[0] <= args[0] + { to_do, 2'b00 };
		args[1] <= args[1] - to_do;

		cmd_instr <= MEM_READ;
		cmd_byte_addr <= { args[0][29:2], 2'b00 };
		cmd_bl <= to_do - 1'b1;
		cmd_en <= 1'b1;

		burst_len <= to_do;
	     end

	   STATE_READ_BURST:
	     begin
		if (!rd_empty && tx_ce) begin
		   tx <= rd_data;
		   tx_en <= 1'b1;
		   rd_en <= 1'b1;
		   burst_len <= burst_len - 1'b1;
		end
	     end

	   STATE_READ_BURST_WAIT:
	     ;

	   STATE_WRITE:
	     begin
		args[0] <= args[0] + { to_do, 2'b00 };
		args[1] <= args[1] - to_do;

		cmd_instr <= MEM_WRITE;
		cmd_byte_addr <= { args[0][29:2], 2'b00 };
		cmd_bl <= to_do - 1'b1;

		burst_len <= to_do;

		rx_en <= !wr_full;
	     end

	   STATE_WRITE_BURST:
	     begin
		if (!wr_full && rx_ce) begin
		   wr_data <= rx;
		   wr_en <= 1'b1;
		   burst_len <= burst_len - 1'b1;

		   if (burst_len == 1)
		     cmd_en <= 1'b1;
		end

		rx_en <= !wr_full;
	     end // case: STATE_WRITE_BURST

	   STATE_CAPTURE:
	     begin
		if (capture_done) begin
		   capture_frames <= args[0];
		   capture_start <= 1'b1;
		end
	     end

	   // CMD_STATUS returns two words; the first contains flags, the
	   // second tells you how many frames remain
	   STATE_STATUS:
	     begin
		if (tx_ce) begin
		   tx <= { 30'b0, capture_done, capture_sync };
		   tx_en <= 1'b1;
		end
	     end
	   STATE_STATUS_2:
	     ;
	   STATE_STATUS_3:
	     begin
		if (tx_ce) begin
		   tx <= capture_frames_remaining;
		   tx_en <= 1'b1;
		end
	     end

	   STATE_CHSTATUS:
	     cs_word_sel <= 0;

	   STATE_CHSTATUS_2:
	     begin
		if (tx_ce) begin
		   tx <= cs_word;
		   tx_en <= 1'b1;
		   cs_word_sel <= cs_word_sel + 1'b1;
		end
	     end

	   STATE_CHSTATUS_3:
	     ;
	 endcase // case (next_state)
      end
   end

endmodule // command
