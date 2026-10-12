`timescale 1ns/1ps
`include "map.svh"
module uart_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1,select=0,write=0,rx=1;
 reg [11:0] offset=0;reg [31:0] data=0;reg [3:0] strobes=15;
 wire [31:0] read_data;wire error,tx,irq,event_tx;wire [7:0] byte_tx;
 ringisa_uart #(.CLOCK_HZ(460800)) dut(clk,reset,select,write,offset,data,strobes,read_data,error,rx,tx,irq,event_tx,byte_tx);
 task frame(input [7:0] value);begin
  @(negedge clk);rx=0;repeat(4)@(negedge clk);
  for(integer i=0;i<8;i=i+1)begin rx=value[i];repeat(4)@(negedge clk);end
  rx=1;repeat(12)@(negedge clk);
 end endtask
 task consume_during_completion(input [7:0] old_value);begin
  wait(dut.rx_state==10&&dut.rx_count==0);
  @(negedge clk);offset=`SOC_UART_RX;select=1;
  #1;if(read_data[7:0]!==old_value)$fatal(1,"RX old read data");
  @(negedge clk);select=0;
 end endtask
 initial begin
  #32;reset=0;
  fork frame(8'h35);consume_during_completion(0);join
  if(!dut.rx_ready||dut.rx_byte!=8'h35)$fatal(1,"new byte lost during empty read");
  fork frame(8'h69);consume_during_completion(8'h35);join
  if(!dut.rx_ready||dut.rx_byte!=8'h69||dut.overrun)$fatal(1,"new byte lost during occupied read");
  frame(8'h77);if(dut.rx_byte!=8'h69||!dut.overrun)$fatal(1,"unread-byte overrun semantics");
  @(negedge clk);offset=`SOC_UART_RX;select=1;@(negedge clk);select=0;
  if(dut.rx_ready)$fatal(1,"read-clear");
  $display("PASS UART RX completion/read races and retained-byte overrun (4 checks)");$finish;
 end
 initial begin #100000;$fatal(1,"UART timeout");end
endmodule
