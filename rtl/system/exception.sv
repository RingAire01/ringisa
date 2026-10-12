`timescale 1ns/1ps
module ringisa_exception(
 input wire illegal,overflow,privilege_fault,breakpoint,svc,interrupt_fault,
 input wire [4:0] memory_fault,input wire [127:0] pc,memory_value,
 input wire [41:0] immediate,
 output reg trap,output reg [4:0] cause,output reg [127:0] value
);
 always @*begin
  trap=1;cause=0;value=pc;
  if(interrupt_fault)begin cause=14;value=0;end
  else if(memory_fault!=0)begin cause=memory_fault;value=memory_value;end
  else if(illegal)cause=1;
  else if(overflow)cause=5;
  else if(privilege_fault)cause=13;
  else if(svc)begin cause=11;value={86'b0,immediate};end
  else if(breakpoint)begin cause=12;value={86'b0,immediate};end
  else trap=0;
 end
endmodule
