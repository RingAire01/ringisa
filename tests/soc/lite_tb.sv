`timescale 1ns/1ps
`include "map.svh"
module lite_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg av=0,wv=0,br=0,arv=0,rr=0;wire ar,wr,bv,arr,rv;
 reg [63:0] aa=0,ara=0;reg [31:0] wd=0;reg [3:0] st=15;
 wire [1:0] bc,rc;wire [31:0] rd;wire tx,event_tx;wire [7:0] byte_tx;wire [63:0] irq;
 ringisa_peripherals dut(clk,reset,av,ar,aa,wv,wr,wd,st,bv,br,bc,arv,arr,ara,rv,rr,rd,rc,1'b1,tx,1'b0,irq,event_tx,byte_tx);
 integer checks=0;
 task aw;begin @(negedge clk);av=1;do @(posedge clk);while(!ar);@(negedge clk);av=0;end endtask
 task w;begin @(negedge clk);wv=1;do @(posedge clk);while(!wr);@(negedge clk);wv=0;end endtask
 task ack(input [1:0] code);begin wait(bv);repeat(7)begin @(negedge clk);if(!bv||bc!==code)$fatal(1,"Lite B hold/response");end br=1;@(negedge clk);br=0;checks=checks+1;end endtask
 task read_check(input [63:0] a,input [31:0] value,input [1:0] code);
  begin @(negedge clk);ara=a;arv=1;do @(posedge clk);while(!arr);@(negedge clk);arv=0;wait(rv);
   repeat(7)begin @(negedge clk);if(!rv||rd!==value||rc!==code)$fatal(1,"Lite read a=%h data%h expected%h code%d/%d",a,rd,value,rc,code);end
   rr=1;@(negedge clk);rr=0;checks=checks+1;
  end
 endtask
 task rst;begin @(negedge clk);reset=1;av=0;wv=0;arv=0;br=0;rr=0;repeat(3)@(negedge clk);reset=0;end endtask
 initial begin
  #32;reset=0;
  aa=`SOC_TIMER_BASE+4;wd=32'h12345678;w();repeat(10)@(posedge clk);
  read_check(`SOC_TIMER_BASE+4,32'hffffffff,0);aw();ack(0);read_check(`SOC_TIMER_BASE+4,32'h12345678,0);
  aa=`SOC_TIMER_BASE+4;wd=32'hab0000cd;st=9;aw();repeat(10)@(posedge clk);
  read_check(`SOC_TIMER_BASE+4,32'h12345678,0);w();ack(0);read_check(`SOC_TIMER_BASE+4,32'hab3456cd,0);
  aa=`SOC_IRQ_BASE+4;wd=7;st=0;w();aw();ack(0);read_check(`SOC_IRQ_BASE+4,0,0);
  aa=`SOC_TIMER_BASE+16;st=15;w();aw();ack(2);
  read_check(`SOC_UART_BASE+20,0,2);read_check(64'h200000,0,3);read_check(`SOC_TIMER_BASE+1,0,2);
  aa=`SOC_TIMER_BASE;aw();rst();read_check(`SOC_TIMER_BASE,0,0);
  w();rst();read_check(`SOC_IRQ_BASE+4,0,0);
  aa=`SOC_TIMER_BASE;aw();w();wait(bv);rst();read_check(`SOC_TIMER_BASE,0,0);
  @(negedge clk);ara=`SOC_IRQ_BASE;arv=1;@(posedge clk);@(negedge clk);arv=0;wait(rv);rst();read_check(`SOC_IRQ_BASE,0,0);
  $display("PASS AXI-Lite %0d checks; W-before-AW, AW-before-W, read/write independence, response stalls, partial strobes, invalid offsets and four reset stages",checks);$finish;
 end
 initial begin #200000;$fatal(1,"Lite timeout");end
endmodule
