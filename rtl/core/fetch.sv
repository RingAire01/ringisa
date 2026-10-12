`timescale 1ns/1ps
module ringisa_fetch(
 input wire clk,reset,start,input wire [127:0] pc,
 output reg done,output reg [4:0] fault,output reg [127:0] fault_address,
 output reg [31:0] w0,w1,
 output wire memory_start,output wire [127:0] memory_address,
 input wire memory_done,input wire [4:0] memory_fault,input wire [127:0] memory_fault_address,
 input wire [255:0] memory_data
);
 localparam IDLE=0,FIRST=1,WAIT_FIRST=2,SECOND=3,WAIT_SECOND=4;
 reg [2:0] state;reg [127:0] saved_pc;wire [127:0] extension;wire overflow;
 ringisa_address next_word(saved_pc,128'sd4,extension,overflow);
 assign memory_start=state==FIRST||(state==SECOND&&!overflow);
 assign memory_address=state==SECOND?extension:saved_pc;
 always @(posedge clk)begin
  done<=0;
  if(reset)begin state<=IDLE;fault<=0;fault_address<=0;w0<=0;w1<=0;saved_pc<=0;end
  else case(state)
   IDLE:if(start)begin saved_pc<=pc;fault<=0;w1<=0;
    if(pc[1:0]!=0)begin done<=1;fault<=6;fault_address<=pc;end else state<=FIRST;
   end
   FIRST:state<=WAIT_FIRST;
   WAIT_FIRST:if(memory_done)begin w0<=memory_data[31:0];
    if(memory_fault!=0)begin done<=1;fault<=memory_fault;fault_address<=memory_fault_address;state<=IDLE;end
    else if(memory_data[1:0]==1)state<=SECOND;else begin done<=1;state<=IDLE;end
   end
   SECOND:if(overflow)begin done<=1;fault<=5;fault_address<=saved_pc;state<=IDLE;end else state<=WAIT_SECOND;
   WAIT_SECOND:if(memory_done)begin done<=1;w1<=memory_data[31:0];fault<=memory_fault;fault_address<=memory_fault_address;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
endmodule
