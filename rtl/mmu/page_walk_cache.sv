`timescale 1ns/1ps
module ringisa_page_walk_cache #(parameter ENTRIES=32)(
 input wire clk,reset,invalidate,
 input wire [63:0] address,root,input wire [15:0] asid,
 output reg hit,output reg [127:0] pte,
 input wire insert,input wire [127:0] insert_pte
);
 reg valid[0:ENTRIES-1];reg [63:0] addresses[0:ENTRIES-1],roots[0:ENTRIES-1];
 reg [15:0] asids[0:ENTRIES-1];reg [127:0] values[0:ENTRIES-1];integer slot,i;
 always @*begin hit=0;pte=0;for(integer j=0;j<ENTRIES;j=j+1)if(valid[j]&&addresses[j]==address&&roots[j]==root&&asids[j]==asid)begin hit=1;pte=values[j];end end
 always @(posedge clk)begin
  if(reset||invalidate)begin slot<=0;for(i=0;i<ENTRIES;i=i+1)valid[i]<=0;end
  else if(insert)begin valid[slot]<=1;addresses[slot]<=address;roots[slot]<=root;asids[slot]<=asid;values[slot]<=insert_pte;if(slot==ENTRIES-1)slot<=0;else slot<=slot+1;end
 end
endmodule
