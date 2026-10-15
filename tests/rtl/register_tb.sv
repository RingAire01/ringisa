`timescale 1ns/1ps
module register_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,we=0;reg [5:0] wi=0,a=0,b=0,c=0,d=0;reg [255:0] wd=0;
 wire [255:0] va,vb,vc,vd;
 ringisa_register_file dut(clk,reset,we,wi,a,b,c,wd,va,vb,vc,d,vd);
 reg [255:0] expected[0:63];reg [31:0] seed=32'h52464732;integer checks=0;
 function [31:0] random32;
  begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);random32=seed;end
 endfunction
 task verify;
  begin #1;
   if(va!==expected[a]||vb!==expected[b]||vc!==expected[c]||vd!==expected[d])
    $fatal(1,"register scoreboard seed=%h indices=%0d/%0d/%0d/%0d",seed,a,b,c,d);
   checks=checks+4;
  end
 endtask
 initial begin
  for(integer i=0;i<64;i=i+1)expected[i]=0;
  repeat(2)@(negedge clk);reset=0;
  for(integer cycle=0;cycle<1200;cycle=cycle+1)begin
   reset=cycle%97==0;we=cycle%5!=0;wi=random32();
   // Read-after-write bypass is not added: synchronous write, asynchronous read.
   a=wi;b=random32();c=random32();d=random32();
   for(integer limb=0;limb<8;limb=limb+1)wd[limb*32+:32]=random32();
   if(reset)for(integer i=0;i<64;i=i+1)expected[i]=0;
   else if(we&&wi!=0)expected[wi]=wd;
   @(posedge clk);verify();@(negedge clk);
  end
  we=0;reset=1;@(posedge clk);for(integer i=0;i<64;i=i+1)expected[i]=0;
  @(negedge clk);reset=0;
  for(integer i=0;i<64;i=i+1)begin a=i;b=i;c=i;d=i;verify();@(negedge clk);end
  $display("PASS register file %0d port checks; seed=52464732, R0, four read ports, reset/write priority, stale-data masking",checks);$finish;
 end
 initial begin #100000;$fatal(1,"register timeout");end
endmodule
