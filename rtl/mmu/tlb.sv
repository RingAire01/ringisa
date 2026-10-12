`timescale 1ns/1ps
module ringisa_tlb #(parameter ENTRIES=32)(
 input wire clk,reset,invalidate,
 input wire [115:0] lookup_vpn,input wire [15:0] lookup_asid,
 input wire [63:0] lookup_root,
 output reg hit,output reg [51:0] ppn,output reg [8:0] flags,output reg device,
 input wire insert,input wire [115:0] insert_vpn,input wire [15:0] insert_asid,
 input wire [63:0] insert_root,input wire [51:0] insert_ppn,
 input wire [8:0] insert_flags,input wire insert_device
);
 reg valid[0:ENTRIES-1];reg [115:0] tags[0:ENTRIES-1];reg [15:0] asids[0:ENTRIES-1];
 reg [63:0] roots[0:ENTRIES-1];reg [51:0] ppns[0:ENTRIES-1];reg [8:0] permissions[0:ENTRIES-1];
 reg devices[0:ENTRIES-1];integer next_slot,i;
 always @*begin hit=0;ppn=0;flags=0;device=0;
  for(integer j=0;j<ENTRIES;j=j+1)if(valid[j]&&tags[j]==lookup_vpn&&roots[j]==lookup_root&&(permissions[j][6]||asids[j]==lookup_asid))begin hit=1;ppn=ppns[j];flags=permissions[j];device=devices[j];end
 end
 always @(posedge clk)begin
  if(reset||invalidate)begin for(i=0;i<ENTRIES;i=i+1)valid[i]<=0;next_slot<=0;end
  else if(insert)begin valid[next_slot]<=1;tags[next_slot]<=insert_vpn;asids[next_slot]<=insert_asid;roots[next_slot]<=insert_root;ppns[next_slot]<=insert_ppn;permissions[next_slot]<=insert_flags;devices[next_slot]<=insert_device;
   if(next_slot==ENTRIES-1)next_slot<=0;else next_slot<=next_slot+1;
  end
 end
endmodule
