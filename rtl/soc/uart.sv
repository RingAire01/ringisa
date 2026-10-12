`timescale 1ns/1ps
`include "map.svh"
module ringisa_uart #(parameter CLOCK_HZ=50000000,parameter BAUD=115200)(
 input wire clk,reset,select,write,input wire [11:0] offset,input wire [31:0] data,
 input wire [3:0] strobes,output reg [31:0] read_data,output reg error,
 input wire rx,output wire tx,output wire irq,output reg tx_event,output reg [7:0] tx_byte
);
 reg [31:0] divisor,control,tx_count,rx_count;
 reg [9:0] tx_shift;reg [3:0] tx_bits;reg busy;
 reg rx_sync,rx_meta;reg [3:0] rx_state;reg [7:0] rx_shift,rx_byte;reg rx_ready,overrun,framing;
 assign tx=busy?tx_shift[0]:1'b1;assign irq=control[0]&&rx_ready;
 function [31:0] merge(input [31:0] old,input [31:0] value,input [3:0] mask);
  begin merge=old;for(integer i=0;i<4;i=i+1)if(mask[i])merge[i*8+:8]=value[i*8+:8];end
 endfunction
 wire [31:0] new_divisor=merge(divisor,data,strobes);
 wire consume_rx=select&&!error&&!write&&offset==`SOC_UART_RX;
 always @*begin
  read_data=0;error=0;
  case(offset)
   `SOC_UART_TX:begin if(!write)error=1;else if(strobes[0]&&busy)error=1;end
   `SOC_UART_RX:begin read_data={24'b0,rx_byte};if(write)error=1;end
   `SOC_UART_STATUS:begin read_data={28'b0,framing,overrun,rx_ready,!busy};if(write)error=1;end
   `SOC_UART_CONTROL:read_data=control;
   `SOC_UART_DIVISOR:begin read_data=divisor;if(write&&(new_divisor<4||busy||rx_state!=0))error=1;end
   default:error=1;
  endcase
 end
 always @(posedge clk)begin
  tx_event<=0;
  if(reset)begin divisor<=CLOCK_HZ/BAUD<4?4:CLOCK_HZ/BAUD;control<=0;tx_count<=0;tx_shift<=10'h3ff;tx_bits<=0;busy<=0;rx_meta<=1;rx_sync<=1;rx_state<=0;rx_count<=0;rx_shift<=0;rx_byte<=0;rx_ready<=0;overrun<=0;framing<=0;tx_byte<=0;end
  else begin
   rx_meta<=rx;rx_sync<=rx_meta;
   if(busy)begin if(tx_count==0)begin
    if(tx_bits==9)begin busy<=0;tx_event<=1;end
    else begin tx_shift<={1'b1,tx_shift[9:1]};tx_bits<=tx_bits+1;tx_count<=divisor-1;end
   end else tx_count<=tx_count-1;end
   if(consume_rx)rx_ready<=0;
   case(rx_state)
    0:if(!rx_sync)begin rx_state<=1;rx_count<=divisor/2-1;end
    1:if(rx_count==0)begin if(rx_sync)rx_state<=0;else begin rx_state<=2;rx_count<=divisor-1;end end else rx_count<=rx_count-1;
    2,3,4,5,6,7,8,9:if(rx_count==0)begin rx_shift[rx_state-2]<=rx_sync;rx_state<=rx_state+1;rx_count<=divisor-1;end else rx_count<=rx_count-1;
    10:if(rx_count==0)begin rx_state<=0;if(!rx_sync)framing<=1;else if(rx_ready&&!consume_rx)overrun<=1;else begin rx_byte<=rx_shift;rx_ready<=1;end end else rx_count<=rx_count-1;
    default:rx_state<=0;
   endcase
   if(select&&!error)begin
    if(write)case(offset)
     `SOC_UART_TX:if(strobes[0])begin tx_shift<={1'b1,data[7:0],1'b0};tx_bits<=0;tx_count<=divisor-1;busy<=1;tx_byte<=data[7:0];end
     `SOC_UART_CONTROL:begin control<=merge(control,data,strobes)&1;if(strobes[0]&&data[1])begin overrun<=0;framing<=0;end end
     `SOC_UART_DIVISOR:divisor<=new_divisor;
     default:begin end
    endcase
   end
  end
 end
endmodule
