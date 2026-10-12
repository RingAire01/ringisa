// Atomic gather/scatter transaction interface: the memory fabric validates all
// enabled byte addresses before performing ANY store side effect.
`timescale 1ns/1ps
module ringisa_load_store(
 input wire clk,reset,start,
 input wire [127:0] virtual_address,input wire [5:0] byte_count,
 input wire [1:0] access_kind,privilege,input wire [255:0] store_data,
 input wire [63:0] satp,input wire [15:0] asid,input wire invalidate,
 output reg done,output reg [4:0] fault,output reg [127:0] fault_address,
 output reg [255:0] load_data,
 output wire request,output wire write,
 output wire [2047:0] addresses,output wire [31:0] enables,output wire [255:0] write_data,
 input wire response,response_error,input wire [4:0] response_fault_index,input wire [255:0] read_data,
 output wire walk_request,output wire [63:0] walk_address,
 input wire walk_response,walk_error,input wire [127:0] walk_pte
);
 localparam IDLE=0,TRANSLATE=1,WAIT_TRANSLATE=2,TRANSACTION=3;
 reg [2:0] state;reg [127:0] base;reg [5:0] count,index;
 reg [1:0] kind;reg [255:0] data;reg [2047:0] physical;
 wire [127:0] current;wire overflow;
 ringisa_address address_generator(base,$signed({122'b0,index}),current,overflow);
 wire translated;wire [4:0] translation_fault;wire [63:0] pa;wire device;
 ringisa_mmu mmu(clk,reset,invalidate,state==TRANSLATE&&!overflow,current,kind,privilege,satp,asid,translated,translation_fault,pa,device,walk_request,walk_address,walk_response,walk_error,walk_pte);
 assign request=state==TRANSACTION;assign write=kind==2;assign addresses=physical;
 assign enables=count==32?32'hffffffff:((32'b1<<count)-1);assign write_data=data;
 always @(posedge clk)begin
  done<=0;
  if(reset)begin state<=IDLE;fault<=0;fault_address<=0;load_data<=0;base<=0;count<=0;index<=0;kind<=0;data<=0;physical<=0;end
  else case(state)
   IDLE:if(start)begin base<=virtual_address;count<=byte_count;index<=0;kind<=access_kind;data<=store_data;fault<=0;physical<=0;
    if(byte_count==0||byte_count>32)begin done<=1;fault<=1;fault_address<=virtual_address;end else state<=TRANSLATE;
   end
   TRANSLATE:if(overflow)begin done<=1;fault<=5;fault_address<=base;state<=IDLE;end else state<=WAIT_TRANSLATE;
   WAIT_TRANSLATE:if(translated)begin
    if(translation_fault!=0)begin done<=1;fault<=translation_fault;fault_address<=current;state<=IDLE;end
    else if(device&&((base[4:0]&(count-1))!=0||({1'b0,base[11:0]}+count)>4096))begin done<=1;fault<=6;fault_address<=base;state<=IDLE;end
    else begin physical[index*64+:64]<=pa;if(index+1==count)state<=TRANSACTION;else begin index<=index+1;state<=TRANSLATE;end end
   end
   TRANSACTION:if(response)begin done<=1;fault<=response_error?5'd10:5'd0;fault_address<=base+{123'b0,response_fault_index};load_data<=read_data;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
endmodule
