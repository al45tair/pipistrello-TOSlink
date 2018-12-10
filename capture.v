`timescale 1ns / 1ps

module capture(input 		 clock,
	       input 		 reset,

	       // Capture interface
	       input 		 tos_in,
	       input [31:0] 	 frames,
	       input 		 start,
	       output reg [31:0] frames_remaining,
	       output 		 done,
	       output reg 	 sync,

	       input [2:0] 	 cs_word_sel,
	       output reg [31:0] cs_word,

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
	       output 		 rd_en,
	       input [31:0] 	 rd_data,
	       input 		 rd_full,
	       input 		 rd_empty,
	       input [6:0] 	 rd_count,
	       input 		 rd_overflow,
	       input 		 rd_error,

	       output [15:0] 	 debug);

   assign cmd_clk = clock;
   assign wr_clk = clock;
   assign rd_clk = clock;
   assign wr_mask = 0;
   assign rd_en = 0;

   // Memory commands
   localparam MEM_WRITE    = 3'b000;
   localparam MEM_READ     = 3'b001;
   localparam MEM_WRITE_AP = 3'b010;
   localparam MEM_READ_AP  = 3'b011;
   localparam MEM_REFRESH  = 3'b100;

   // The address we're writing at
   reg [29:0] 	  address;

   assign done = frames_remaining == 0;

   // Recover the data and clock enable from the input
   wire       tos_ce;
   wire       tos_data;

   clockrecovery cdr(clock, reset, tos_in, tos_ce, tos_data);

   // Locate the syncwords
   reg [7:0] 	syncword;

   always @(posedge clock or posedge reset) begin
      if (reset)
	syncword <= 0;
      else if (tos_ce)
	syncword <= { syncword[6:0], tos_data };
   end;

   assign tos_bsync = (syncword == 8'b11101000
		       || syncword == 8'b00010111);
   assign tos_msync = (syncword == 8'b11100010
		       || syncword == 8'b00011101);
   assign tos_wsync = (syncword == 8'b11100100
		       || syncword == 8'b00011011);

   // Read the 32-bit words
   reg [31:0] word;
   reg        word_complete;
   wire       tos_sync = tos_bsync || tos_msync || tos_wsync;
   reg 	      prev_bm; // Prev bit for Biphase Mark decide
   reg 	      bm_bit;  // 1 if we're looking at the second bit of a pair
   reg [4:0]  bits;    // Count of bits received so far
   reg        parity;  // Running parity

   // Combinatorial logic
   wire        decoded_bit = prev_bm ^ tos_data;
   wire        next_parity = parity ^ decoded_bit;
   wire [31:0] next_word = { next_parity, word[29:0], decoded_bit };

   // Output format is
   //
   //  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
   //  1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
   // +-+-+-+-+---------------------------------------+-------+---+-+-+
   // |P|C|S|V| sample                                |  aux  |syn|#|E|
   // +-+-+-+-+---------------------------------------+-------+---+-+-+
   //
   //  E      = Parity error detected
   //  syn    = Sync indicator - 00 = B, 01 = M, 10 = W
   //  aux    = Auxiliary audio databits (used if 24-bit sample)
   //  sample = Audio sample
   //  V      = Valid
   //  S      = Subcode data
   //  C      = Channel status information
   //  P      = Parity (excluding top four bits)

   localparam STATE_IDLE          = 3'b000;
   localparam STATE_BEGIN_CAPTURE = 3'b001;
   localparam STATE_WAIT_WORD     = 3'b010;
   localparam STATE_WRITE_WORD    = 3'b011;

   reg [2:0]  state;
   reg [2:0]  next_state;

   // Capture control
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
	  if (start)
	    next_state = STATE_BEGIN_CAPTURE;
	STATE_BEGIN_CAPTURE:
	  next_state = STATE_WAIT_WORD;
	STATE_WAIT_WORD:
	  if (frames_remaining == 0)
	    next_state = STATE_IDLE;
	  else if (word_complete)
	    next_state = STATE_WRITE_WORD;
	STATE_WRITE_WORD:
	  next_state = STATE_WAIT_WORD;
      endcase
   end

   integer n;

   always @(posedge clock or posedge reset) begin
      if (reset) begin
	 wr_en <= 1'b0;
	 cmd_en <= 1'b0;
	 frames_remaining <= 0;
      end else begin
	 wr_en <= 1'b0;
	 cmd_en <= 1'b0;

	 case (next_state)
	   STATE_IDLE:
	     ;
	   STATE_BEGIN_CAPTURE:
	     begin
		frames_remaining <= frames;
		address <= 0;
	     end
	   STATE_WAIT_WORD:
	     ;
	   STATE_WRITE_WORD:
	     begin
		// Put the word into the FIFO
		for (n = 0; n < 32; n = n + 1) begin
		   wr_data[n] <= word[31 - n];
		end
		wr_en <= 1'b1;

		// Now write the FIFO to memory
		frames_remaining <= frames_remaining - 1;

		cmd_instr <= MEM_WRITE;
		cmd_byte_addr <= address;
		cmd_bl <= 0;
		cmd_en <= 1'b1;

		address <= address + 29'h4;
	     end
	 endcase // case (next_state)
      end // else: !if(reset)
   end // always @ (posedge clock or posedge reset)

   // Channel status
   reg [191:0] channel_status;
   reg [191:0] next_channel_status;

   assign debug[0] = word_complete;
   assign debug[1] = word[1];
   assign debug[2] = tos_bsync;
   assign debug[5:3] = cs_word_sel;
   assign debug[15:6] = 0;
   
   always @(posedge clock) begin
      if (word_complete)
	 next_channel_status <= { next_channel_status[190:0], word[1] };

      if (tos_bsync)
	channel_status <= next_channel_status;
   end // always @ (posedge clock)

   always @(*) begin
      case (cs_word_sel)
	3'd0:
	  cs_word = channel_status[191:160];
	3'd1:
	  cs_word = channel_status[159:128];
	3'd2:
	  cs_word = channel_status[127:96];
	3'd3:
	  cs_word = channel_status[95:64];
	3'd4:
	  cs_word = channel_status[63:32];
	3'd5:
	  cs_word = channel_status[31:0];
	default:
	  cs_word = 0;
      endcase
   end

   // Decoding
   always @(posedge clock or posedge reset) begin
      if (reset) begin
	 sync <= 1'b0;
	 word_complete <= 1'b0;
      end else begin
	 word_complete <= 1'b0;

	 if (tos_ce) begin

	    if (tos_sync) begin
	       // When we detect sync, tos_data is the *first* bit of
	       // the actual data, so bm_bit must be one here
	       bm_bit <= 1'b1;

	       // Start the word with the sync indicator (the parity error
	       // is calculated as we receive data)
	       if (tos_bsync)
		 word <= 4'b0000;
	       else if (tos_msync)
		 word <= 4'b0010;
	       else if (tos_wsync)
		 word <= 4'b0001;
	       bits <= 4;

	       // No parity yet
	       parity <= 1'b0;

	       // We've locked sync
	       sync <= 1'b1;
	    end else if (sync) begin
	       bm_bit <= ~bm_bit;

	       if (bm_bit) begin
		  // Update word and parity
		  parity <= next_parity;
		  word <= next_word;

		  // If we've finished, unlock sync
		  bits <= bits + 1'b1;
		  if (bits == 5'b11111) begin
		     word_complete <= 1'b1;
		     sync <= 1'b0;
		  end
	       end
	    end // if (sync)

	    prev_bm <= tos_data;

	 end // if (tos_ce)

      end // else: !if(reset)
   end // always @ (posedge clock or posedge reset)

endmodule // capture
