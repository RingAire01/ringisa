`timescale 1ns/1ps
`include "constants.svh"
module ringisa_decoder(
 input wire [31:0] w0,w1,
 output reg valid,
 output wire [7:0] op,
 output wire [5:0] a,b,c,
 output wire [3:0] func,
 output wire extended,
 output wire signed [41:0] immediate
);
 reg rtype;reg [3:0] func_limit;
 assign op=w0[31:24];assign a=w0[23:18];assign b=w0[17:12];
 assign c=w0[11:6];assign func=w0[5:2];assign extended=w0[1:0]==2'b01;
 assign immediate=extended?{w1,w0[11:2]}:{{32{w0[11]}},w0[11:2]};
 always @* begin
  valid=0;rtype=0;func_limit=0;
  case(op)
   `include "opcodes.svh"
   default:valid=0;
  endcase
  if(w0[1])valid=0;
  if(rtype&&(extended||func>=func_limit))valid=0;
  case(op)
   `RINGISA_MOVI:if(b!=0)valid=0;
   `RINGISA_CHUNK:if(!extended||b!=0||w0[11:2]>7)valid=0;
   `RINGISA_SVC,`RINGISA_BRK:if(a!=0||b!=0||immediate<0)valid=0;
   `RINGISA_ERET,`RINGISA_WFI,`RINGISA_FENCE,`RINGISA_TLBI:if(extended||a!=0||b!=0||immediate!=0)valid=0;
   `RINGISA_CSRR:if(extended||b!=0||immediate<0||immediate>=9)valid=0;
   `RINGISA_CSRW:if(extended||a!=0||immediate<0||immediate>=9)valid=0;
   default:begin end
  endcase
 end
endmodule
