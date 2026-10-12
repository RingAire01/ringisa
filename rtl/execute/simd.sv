`timescale 1ns/1ps
`include "constants.svh"
module ringisa_simd(
 input wire [7:0] op,input wire [3:0] width_code,
 input wire [255:0] left,right,output reg [255:0] result
);
 wire [255:0] results[0:3];
 genvar w,l;
 generate for(w=0;w<4;w=w+1)begin:widths
  localparam BITS=8<<w;
  for(l=0;l<256/BITS;l=l+1)begin:lanes
   wire [BITS-1:0] x=left[l*BITS+:BITS],y=right[l*BITS+:BITS];
   reg [BITS-1:0] z;
   always @* case(op)
    `RINGISA_VADD:z=x+y;`RINGISA_VSUB:z=x-y;`RINGISA_VAND:z=x&y;`RINGISA_VOR:z=x|y;`RINGISA_VXOR:z=x^y;
    `RINGISA_VMUL:z=x*y;`RINGISA_VEQ:z=x==y?{BITS{1'b1}}:{BITS{1'b0}};
    default:z=0;
   endcase
   assign results[w][l*BITS+:BITS]=z;
  end
 end endgenerate
 always @* case(width_code)
  0:result=results[0];1:result=results[1];2:result=results[2];3:result=results[3];default:result=0;
 endcase
endmodule
