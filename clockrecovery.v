`timescale 1ns / 1ps

module clockrecovery (input  clk,
		      input  reset,
		      input  tos_in,
		      output tos_ce,
		      output tos_data);

   parameter CLK_FREQUENCY = 100000000;
   parameter SAMPLE_RATE = 48000;
   parameter BIT_RATE = SAMPLE_RATE * 32 * 2 * 2;
   parameter CLOCKS_PER_PERIOD = CLK_FREQUENCY / BIT_RATE;
   parameter SAMPLE_AT = CLOCKS_PER_PERIOD / 2;

   // Counter
   reg [5:0] 	     ctr;
   wire 	     ctr_reset;

   always @(posedge clk)
     begin
	if (ctr_reset)
	  ctr <= 0;
	else begin
	   if (ctr == CLOCKS_PER_PERIOD - 1)
	     ctr <= 0;
	   else
	     ctr <= ctr + 1'b1;
	end
     end;

   // Input cleanup and edge detection
   reg [2:0] shift_reg;
   reg [1:0] clean_reg;

   always @(posedge clk or posedge reset)
     begin
	if (reset)
	  begin
	     shift_reg <= 3'b000;
	     clean_reg <= 2'b00;
	  end
	else
	  begin
	     shift_reg <= { tos_in, shift_reg[2:1] };

	     casez (shift_reg)
	       3'b010:  clean_reg <= 2'b00;
	       3'b101:  clean_reg <= 2'b11;
	       default: clean_reg <= shift_reg[1:0];
	     endcase // casez (shift_reg)
	  end; // else: !if(reset)
     end;

   wire at_edge = (~clean_reg[0] & clean_reg[1]);

   assign ctr_reset = reset | at_edge;

   // Input sampling
   reg data;
   reg dce;

   always @(posedge clk or posedge reset)
     begin
	if (reset)
	  begin
	     data <= 1'b0;
	     dce <= 1'b0;
	  end
	else
	  begin
	     dce <= 1'b0;
	     if (ctr == SAMPLE_AT) begin
		data <= clean_reg[0];
		dce <= 1'b1;
	     end
	  end; // else: !if(reset)
     end;

   assign tos_ce = dce;
   assign tos_data = data;

endmodule
