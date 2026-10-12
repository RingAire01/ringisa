`timescale 1ns/1ps
`include "constants.svh"
module ringisa_branch(
 input wire [7:0] op,input wire [5:0] base_index,
 input wire [255:0] left,right,input wire [127:0] pc,
 input wire signed [41:0] immediate,
 output wire taken,output wire [127:0] target,output wire overflow
);
 wire less_signed=left[255]!=right[255]?left[255]:(left<right);
 assign taken=(op==`RINGISA_BEQ&&left==right)||(op==`RINGISA_BNE&&left!=right)||(op==`RINGISA_BLTU&&left<right)||(op==`RINGISA_BLTS&&less_signed)||op==`RINGISA_JAL;
 wire [127:0] base=op==`RINGISA_JAL&&base_index!=0?right[127:0]:pc;
 wire signed [127:0] displacement={{84{immediate[41]}},immediate,2'b0};
 ringisa_address generator(base,displacement,target,overflow);
endmodule
