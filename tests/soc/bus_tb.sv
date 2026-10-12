`timescale 1ns/1ps
`include "map.svh"
module bus_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
 wire awready,wready,bvalid,arready,rvalid,rlast;
 reg [63:0] awaddr=0,araddr=0;reg [7:0] awlen=0,arlen=0;
 reg [2:0] awsize=2,arsize=2;reg [1:0] awburst=1,arburst=1;
 reg [31:0] wdata=0;reg [3:0] wstrb=0;reg wlast=1;
 wire [31:0] rdata;wire [1:0] bresp,rresp;
 wire dq,dw,dr;wire [63:0] da;wire [31:0] dd,dread;wire [3:0] ds;wire [1:0] dc;
 ringisa_axi_interconnect #(.ROM_IMAGE("target/soc/rom_boot.hex")) bus(clk,reset,awvalid,awready,awaddr,awlen,awsize,awburst,wvalid,wready,wdata,wstrb,wlast,bvalid,bready,bresp,arvalid,arready,araddr,arlen,arsize,arburst,rvalid,rready,rdata,rresp,rlast,dq,dw,da,dd,ds,dr,dc,dread);
 wire lav,lar,lv,lr,lbv,lbr,lrav,lrar,lrv,lrr;wire [63:0] la,lra;wire [31:0] ld,lrd;wire [3:0] ls;wire [1:0] lbc,lrc;
 ringisa_axi_lite_bridge bridge(clk,reset,dq,dw,da,dd,ds,dr,dc,dread,lav,lar,la,lv,lr,ld,ls,lbv,lbr,lbc,lrav,lrar,lra,lrv,lrr,lrd,lrc);
 reg rx=1,external_irq=0;wire tx;wire [63:0] interrupts;wire event_tx;wire [7:0] byte_tx;
 ringisa_peripherals peripherals(clk,reset,lav,lar,la,lv,lr,ld,ls,lbv,lbr,lbc,lrav,lrar,lra,lrv,lrr,lrd,lrc,rx,tx,external_irq,interrupts,event_tx,byte_tx);
 integer checks=0;reg [31:0] random_seed=32'h52415849;reg [31:0] expected[0:15];reg [31:0] value;
 function [31:0] random32;begin random_seed=random_seed^(random_seed<<13);random_seed=random_seed^(random_seed>>17);random_seed=random_seed^(random_seed<<5);random32=random_seed;end endfunction
 task send_aw;begin @(negedge clk);awvalid=1;do @(posedge clk);while(!awready);@(negedge clk);awvalid=0;end endtask
 task send_w;begin @(negedge clk);wvalid=1;do @(posedge clk);while(!wready);@(negedge clk);wvalid=0;end endtask
 task put(input [63:0] a,input [31:0] d,input [3:0] s,input [1:0] code);
  reg [1:0] held;
  begin awaddr=a;wdata=d;wstrb=s;
   if(random32()&1)begin send_aw();repeat(3)@(posedge clk);send_w();end
   else begin send_w();repeat(5)@(posedge clk);send_aw();end
   for(integer beat=0;beat<awlen;beat=beat+1)send_w();
   wait(bvalid);#1;held=bresp;if(held!==code)$fatal(1,"AXI write %h resp%0d expected%0d seed%h",a,held,code,random_seed);
   repeat(4)begin @(posedge clk);#1;if(!bvalid||bresp!==held)$fatal(1,"B response not held");end
   @(negedge clk);bready=1;@(posedge clk);@(negedge clk);bready=0;checks=checks+1;
  end
 endtask
 task get(input [63:0] a,input [1:0] code,output [31:0] d);
  reg [31:0] held;reg [1:0] held_resp;
  begin @(negedge clk);araddr=a;arvalid=1;do @(posedge clk);while(!arready);@(negedge clk);arvalid=0;
   wait(rvalid);#1;held=rdata;held_resp=rresp;
   if(held_resp!==code||rlast!==(arlen==0))$fatal(1,"AXI read %h resp%0d expected%0d",a,held_resp,code);
   repeat(4)begin @(posedge clk);#1;if(!rvalid||rdata!==held||rresp!==held_resp)$fatal(1,"R response not held");end
   d=held;@(negedge clk);rready=1;
   for(integer beat=0;beat<=arlen;beat=beat+1)begin @(posedge clk);if(!rvalid||rresp!==code||rlast!==(beat==arlen))$fatal(1,"rejected burst beat accounting");end
   @(negedge clk);rready=0;checks=checks+1;
  end
 endtask
 task pulse_reset;begin @(negedge clk);reset=1;awvalid=0;wvalid=0;arvalid=0;bready=0;rready=0;repeat(3)@(negedge clk);reset=0;repeat(2)@(negedge clk);if(bvalid||rvalid)$fatal(1,"stale reset response");end endtask
 initial begin
  #32;reset=0;
  for(integer i=0;i<16;i=i+1)begin expected[i]=0;put(`SOC_RAM_BASE+i*4,0,15,0);end
  for(integer n=0;n<80;n=n+1)begin
   integer i;reg [31:0] data_value;reg [3:0] strobe_value;
   i=random32()%16;data_value=random32();strobe_value=random32();put(`SOC_RAM_BASE+i*4,data_value,strobe_value,0);
   for(integer b=0;b<4;b=b+1)if(strobe_value[b])expected[i][b*8+:8]=data_value[b*8+:8];
   get(`SOC_RAM_BASE+i*4,0,value);if(value!==expected[i])$fatal(1,"strobe oracle seed%h",random_seed);
  end
  put(`SOC_ROM_BASE,32'hffffffff,15,2);get(0,0,value);if(value==32'hffffffff)$fatal(1,"ROM changed");
  get(`SOC_RAM_BASE+`SOC_RAM_BYTES-4,0,value);
  get(`SOC_RAM_BASE+`SOC_RAM_BYTES,3,value);get(64'h1000000000000000,3,value);
  arsize=2;get(`SOC_RAM_BASE+1,2,value);arsize=3;get(`SOC_RAM_BASE,2,value);arsize=2;
  arlen=1;get(`SOC_RAM_BASE,2,value);arlen=0;arburst=2;get(`SOC_RAM_BASE,2,value);arburst=1;
  arlen=15;get(`SOC_RAM_BASE,2,value);arlen=255;get(`SOC_RAM_BASE,2,value);arlen=0;
  awlen=1;put(`SOC_RAM_BASE,0,15,2);awlen=0;wlast=0;put(`SOC_RAM_BASE,0,15,2);wlast=1;
  awlen=15;put(`SOC_RAM_BASE,0,15,2);awlen=255;put(`SOC_RAM_BASE,0,15,2);awlen=0;
  awsize=0;put(`SOC_RAM_BASE+1,32'h00007700,2,0);awsize=2;arsize=0;get(`SOC_RAM_BASE+1,0,value);if(value[15:8]!=8'h77)$fatal(1,"byte lane");arsize=2;
  put(`SOC_UART_BASE+16,4,15,0);put(`SOC_UART_BASE,8'h52,1,0);wait(event_tx);if(byte_tx!=8'h52)$fatal(1,"TX side effect");
  put(`SOC_UART_BASE+16,3,15,2);get(`SOC_UART_BASE+24,2,value);put(`SOC_UART_BASE+8,1,15,2);
  // Independent serial input exercises RX synchronizer, framing and read-clear.
  @(negedge clk);rx=0;repeat(4)@(negedge clk);
  for(integer b=0;b<8;b=b+1)begin rx=(8'ha5>>b)&1;repeat(4)@(negedge clk);end
  rx=1;repeat(12)@(negedge clk);get(`SOC_UART_BASE+8,0,value);if(!value[1])$fatal(1,"RX ready");
  get(`SOC_UART_BASE+4,0,value);if(value[7:0]!=8'ha5)$fatal(1,"RX byte %h",value);get(`SOC_UART_BASE+8,0,value);if(value[1])$fatal(1,"RX read clear");
  put(`SOC_TIMER_BASE,0,15,0);put(`SOC_TIMER_BASE+4,32,15,0);put(`SOC_TIMER_BASE+8,1,15,0);repeat(64)@(posedge clk);
  get(`SOC_TIMER_BASE+12,0,value);if(value!=1)$fatal(1,"timer pending");
  put(`SOC_IRQ_BASE+4,1,1,0);if(!interrupts[0])$fatal(1,"IRQ mask/delivery");
  put(`SOC_TIMER_BASE+8,0,15,0);put(`SOC_TIMER_BASE+12,1,1,0);put(`SOC_IRQ_BASE+8,1,1,0);if(interrupts!=0)$fatal(1,"IRQ ACK");
  external_irq=1;repeat(8)@(posedge clk);external_irq=0;put(`SOC_IRQ_BASE+4,4,1,0);if(!interrupts[2])$fatal(1,"external IRQ sync");put(`SOC_IRQ_BASE+8,4,1,0);
  get(`SOC_IRQ_BASE+20,2,value);get(`SOC_TIMER_BASE+16,2,value);
  // Reset with only AW accepted, only W accepted, pending R and active RAM.
  awaddr=`SOC_RAM_BASE;send_aw();pulse_reset();get(0,0,value);
  send_w();pulse_reset();get(0,0,value);
  @(negedge clk);araddr=0;arvalid=1;@(posedge clk);@(negedge clk);arvalid=0;wait(rvalid);pulse_reset();get(0,0,value);
  awaddr=`SOC_RAM_BASE;send_aw();send_w();wait(bus.state==2);pulse_reset();get(0,0,value);
  $display("PASS AXI/AXI-Lite bus %0d transactions; seed=52415849, independent AW/W, strobes, stalls, ROM/RAM bounds, UART RX/TX, timer IRQ, invalid registers and active reset",checks);$finish;
 end
 initial begin #5000000;$fatal(1,"bus test timeout");end
endmodule
