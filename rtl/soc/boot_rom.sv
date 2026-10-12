`timescale 1ns/1ps
`include "map.svh"
module ringisa_boot_rom #(parameter IMAGE="",parameter BYTES=`SOC_ROM_BYTES)(
 input wire [63:0] address,output wire [31:0] data
);
 reg [7:0] memory[0:BYTES-1];integer i;
 initial begin
  for(i=0;i<BYTES;i=i+1)memory[i]=0;
  if(IMAGE!="")$readmemh(IMAGE,memory);
 end
 wire [63:0] offset=(address-`SOC_ROM_BASE)&~64'd3;
 assign data=offset<BYTES-3?{memory[offset+3],memory[offset+2],memory[offset+1],memory[offset]}:32'b0;
endmodule
