`timescale 1ns/1ps
`include "map.svh"
module adapter_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1,request=0,writing=0;
 reg [2047:0] addresses=0;reg [31:0] enables=0;reg [255:0] write_data=0;
 wire response,error;wire [4:0] fault_index;wire [255:0] read_data;
 wire av,ar,wv,wr,bv,br,rv,rr,arv,arr,last,rlast;wire [63:0] aa,ara;
 wire [7:0] al,arl;wire [2:0] az,arz;wire [1:0] ab,arb,bc,rc;wire [31:0] wd,rd;wire [3:0] st;
 ringisa_cpu_axi dut(clk,reset,request,writing,addresses,enables,write_data,response,error,fault_index,read_data,av,ar,aa,al,az,ab,wv,wr,wd,st,last,bv,br,bc,arv,arr,ara,arl,arz,arb,rv,rr,rd,rc,rlast);
 reg [31:0] seed=32'h41584932;wire ga=seed[0],gw=seed[1],gb=seed[2],gra=seed[3],gr=seed[4];
 always @(posedge clk)seed<={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
 wire sar,swr,sbv,sarr,srv;wire [1:0] sbc,src;wire [31:0] srd;wire slast;
 assign ar=sar&&ga;assign wr=swr&&gw;assign bv=sbv&&gb;assign bc=sbc;
 assign arr=sarr&&gra;assign rv=srv&&gr;assign rd=srd;assign rc=src;assign rlast=slast;
 wire dq,dwrite;wire [63:0] da;wire [31:0] dd;wire [3:0] ds;
 ringisa_axi_interconnect bus(clk,reset,av&&ga,sar,aa,al,az,ab,wv&&gw,swr,wd,st,last,sbv,br&&gb,sbc,arv&&gra,sarr,ara,arl,arz,arb,srv,rr&&gr,srd,src,slast,dq,dwrite,da,dd,ds,dq,2'd3,32'b0);
 reg held_aw=0,held_w=0,held_ar=0;reg [63:0] saved_aw,saved_ar;reg [31:0] saved_w;reg [3:0] saved_st;
 always @(posedge clk)begin
  if(reset)begin held_aw<=0;held_w<=0;held_ar<=0;end
  else begin
   if(held_aw&&(!av||aa!==saved_aw))$fatal(1,"AW instability");
   if(held_w&&(!wv||wd!==saved_w||st!==saved_st))$fatal(1,"W instability");
   if(held_ar&&(!arv||ara!==saved_ar))$fatal(1,"AR instability");
   held_aw<=av&&!ar;held_w<=wv&&!wr;held_ar<=arv&&!arr;saved_aw<=aa;saved_w<=wd;saved_st<=st;saved_ar<=ara;
  end
 end
 task access(input bit wrt,input bit fail_expected,input [4:0] failed_byte);
  begin @(negedge clk);writing=wrt;request=1;wait(response);#1;
   if(error!==fail_expected||(fail_expected&&fault_index!==failed_byte))$fatal(1,"adapter response error=%b byte=%d expected=%b/%d",error,fault_index,fail_expected,failed_byte);
   repeat(3)begin @(negedge clk);if(!response)$fatal(1,"CPU response not held");end
   request=0;wait(!response);@(negedge clk);
  end
 endtask
 reg [255:0] expected;integer count=0;
 initial begin
  #32;reset=0;
  // Entire256-bit stores through byte-sized AXI beats, crossing4KiB and beat boundaries.
  for(integer trial=0;trial<8;trial=trial+1)begin
   enables=32'hffffffff;
   for(integer i=0;i<32;i=i+1)begin addresses[i*64+:64]=`SOC_RAM_BASE+4090+trial*64+i;write_data[i*8+:8]=(trial*32+i)^8'ha5;end
   expected=write_data;access(1,0,0);access(0,0,0);if(read_data!==expected)$fatal(1,"wide oracle");count=count+2;
   addresses[31*64+:64]=64'hffffffffffffffff;write_data=0;access(1,1,31);count=count+1;
   addresses[31*64+:64]=`SOC_RAM_BASE+4090+trial*64+31;access(0,0,0);if(read_data!==expected)$fatal(1,"partial architectural store");count=count+1;
  end
  enables=1;addresses=0;write_data=0;access(1,1,0);access(0,0,0);count=count+2;
  enables=32'h1f;for(integer i=0;i<5;i=i+1)addresses[i*64+:64]=`SOC_UART_BASE+i;access(1,1,0);count=count+1;
  // Reset every adapter phase, with shared fabric reset; no stale completion.
  for(integer phase=1;phase<=6;phase=phase+1)begin
   enables=1;addresses[63:0]=`SOC_RAM_BASE;
   @(negedge clk);writing=phase<=4;request=1;
   if(phase==4)wait(dut.state==4);else if(phase==5)begin writing=0;wait(dut.state==5);end
   else if(phase==6)begin writing=0;wait(dut.state==6);end else wait(dut.state==phase);
   @(negedge clk);reset=1;request=0;repeat(3)@(negedge clk);reset=0;
   repeat(2)@(negedge clk);if(response)$fatal(1,"reset completion");access(0,0,0);count=count+1;
  end
  $display("PASS CPU AXI adapter %0d logical transactions; seed=41584932; wide cross-page, no partial fault stores, all five channel stalls, held VALID/data, phase resets",count);$finish;
 end
 initial begin #5000000;$fatal(1,"adapter timeout state%0d",dut.state);end
endmodule
