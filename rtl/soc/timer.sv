`timescale 1ns/1ps
`include "map.svh"
module ringisa_timer(
 input wire clk,reset,select,write,input wire [11:0] offset,
 input wire [31:0] data,input wire [3:0] strobes,
 output reg [31:0] read_data,output reg error,output wire irq
);
 reg [31:0] counter,compare;reg enabled,pending;
 assign irq=pending;
 function [31:0] merge(input [31:0] old,input [31:0] value,input [3:0] mask);
  begin merge=old;for(integer i=0;i<4;i=i+1)if(mask[i])merge[i*8+:8]=value[i*8+:8];end
 endfunction
 always @*begin
  error=0;read_data=0;
  case(offset)
   `SOC_TIMER_COUNT:read_data=counter;
   `SOC_TIMER_COMPARE:read_data=compare;
   `SOC_TIMER_CONTROL:read_data={31'b0,enabled};
   `SOC_TIMER_PENDING:read_data={31'b0,pending};
   default:error=1;
  endcase
 end
 always @(posedge clk)begin
  if(reset)begin counter<=0;compare<=32'hffffffff;enabled<=0;pending<=0;end
  else begin
   if(enabled)begin counter<=counter+1;if(counter>=compare)pending<=1;end
   if(select&&write&&!error)case(offset)
    `SOC_TIMER_COUNT:counter<=merge(counter,data,strobes);
    `SOC_TIMER_COMPARE:compare<=merge(compare,data,strobes);
    `SOC_TIMER_CONTROL:if(strobes[0])enabled<=data[0];
    `SOC_TIMER_PENDING:if(strobes[0]&&data[0])pending<=0;
    default:begin end
   endcase
  end
 end
endmodule
