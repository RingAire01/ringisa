`timescale 1ns/1ps
`include "map.svh"
module ringisa_interrupt_controller(
 input wire clk,reset,input wire [2:0] sources,
 input wire select,write,input wire [11:0] offset,input wire [31:0] data,input wire [3:0] strobes,
 output reg [31:0] read_data,output reg error,output wire [63:0] interrupts
);
 reg [2:0] pending,mask;
 assign interrupts={61'b0,pending&mask};
 always @*begin
  error=0;read_data=0;
  case(offset)
   `SOC_IRQ_PENDING:begin read_data={29'b0,pending};if(write)error=1;end
   `SOC_IRQ_MASK:read_data={29'b0,mask};
   `SOC_IRQ_ACK:if(!write)error=1;
   `SOC_IRQ_ACTIVE:begin read_data={29'b0,pending&mask};if(write)error=1;end
   default:error=1;
  endcase
 end
 always @(posedge clk)begin
  if(reset)begin pending<=0;mask<=0;end
  else begin
   pending<=pending|sources;
   if(select&&write&&!error&&strobes[0])begin
    if(offset==`SOC_IRQ_MASK)mask<=data[2:0];
    if(offset==`SOC_IRQ_ACK)pending<=(pending&~data[2:0])|sources;
   end
  end
 end
endmodule
