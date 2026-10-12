`timescale 1ns/1ps
`include "constants.svh"
module ringisa_scalar(
 input wire [7:0] op,input wire [3:0] width_code,
 input wire [255:0] left,right,output reg [255:0] result
);
 reg [255:0] mask,x,y,signed_x,raw;integer bits,shift;
 always @* begin
  bits=8<<width_code;mask={256{1'b1}};
  case(width_code)
   0:mask=256'hff;1:mask=256'hffff;2:mask=256'hffffffff;
   3:mask=256'hffffffffffffffff;4:mask=256'hffffffffffffffffffffffffffffffff;
   default:mask={256{1'b1}};
  endcase
  x=left&mask;y=right&mask;signed_x=x;
  if(x[bits-1])signed_x=x|~mask;
  shift=right[7:0]&(bits-1);raw=0;
  case(op)
   `RINGISA_ADD:raw=x+y;`RINGISA_SUB:raw=x-y;`RINGISA_AND:raw=x&y;`RINGISA_OR:raw=x|y;`RINGISA_XOR:raw=x^y;
   `RINGISA_SHL:raw=x<<shift;`RINGISA_SHR:raw=x>>shift;`RINGISA_SAR:raw=$signed(signed_x)>>>shift;
   `RINGISA_SLTU:raw={255'b0,x<y};
   `RINGISA_SLTS:raw={255'b0,(x[bits-1]!=y[bits-1])?x[bits-1]:(x<y)};
   `RINGISA_MUL:raw=x*y;
   default:raw=0;
  endcase
  result=raw&mask;
  if(op==`RINGISA_SAR&&result[bits-1])result=result|~mask;
 end
endmodule
