`timescale 1ns/1ps
module core_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1;reg [127:0] reset_pc=0;reg [63:0] interrupts=0;
 wire request,write;wire [2047:0] addresses;wire [31:0] enables;wire [255:0] write_data;
 reg response=0,error=0;reg [4:0] fault_index=0;reg [255:0] read_data=0;
 reg [5:0] debug_index=0;wire [255:0] debug_value;wire [127:0] pc;wire [1:0] privilege;
 wire waiting,retired,trapped;wire [4:0] cause;
 ringisa_core dut(clk,reset,reset_pc,interrupts,request,write,addresses,enables,write_data,response,error,fault_index,read_data,debug_index,debug_value,pc,privilege,waiting,retired,trapped,cause);
 localparam MEMORY_SIZE=1048576;
 reg [7:0] memory[0:MEMORY_SIZE-1];string image;integer image_size,cycles=0,traps=0,limit=1000000;
 integer i;reg bad;reg [63:0] address;reg pending=0;integer delay_cycles=0;
 reg saved_write;reg [2047:0] saved_addresses;reg [31:0] saved_enables;reg [255:0] saved_data;
 initial begin
  if(!$value$plusargs("image=%s",image))$fatal(1,"missing image");
  if(!$value$plusargs("size=%d",image_size))$fatal(1,"missing size");
  if(image_size<1||image_size>MEMORY_SIZE)$fatal(1,"invalid image size");
  for(i=0;i<MEMORY_SIZE;i=i+1)memory[i]=0;
  $readmemh(image,memory,0,image_size-1);
  if($value$plusargs("pc=%h",reset_pc))begin end
  if($value$plusargs("limit=%d",limit))begin end
  #22;reset=0;
 end
 // Transactional RAM bus: preflight every byte before any write.
 always @(posedge clk)begin
  response<=0;
  if(reset)pending<=0;
  else if(!pending&&request&&!response)begin
   pending<=1;delay_cycles<=cycles%7;saved_write<=write;saved_addresses<=addresses;saved_enables<=enables;saved_data<=write_data;
  end
  else if(pending)begin
   if(!request||write!==saved_write||addresses!==saved_addresses||enables!==saved_enables||write_data!==saved_data)$fatal(1,"request changed while stalled");
   if(delay_cycles>0)delay_cycles<=delay_cycles-1;
   else begin
   pending<=0;
   bad=0;fault_index<=0;error<=0;read_data<=0;
   for(integer j=0;j<32;j=j+1)if(enables[j])begin
    address=addresses[j*64+:64];if(address>=MEMORY_SIZE&&!bad)begin bad=1;fault_index<=j;end
   end
   error<=bad;
   if(!bad)for(integer j=0;j<32;j=j+1)if(enables[j])begin
    address=addresses[j*64+:64];if(write)memory[address]<=write_data[j*8+:8];else read_data[j*8+:8]<=memory[address];
   end
   response<=1;
   end
  end
  if(!reset)begin cycles<=cycles+1;if(trapped)traps<=traps+1;if(cycles>limit)$fatal(1,"cycle limit pc=%h state=%d",pc,dut.state);end
 end
 initial begin
  wait(!reset);wait(waiting);#2;
  $display("FINAL pc=%032h privilege=%d traps=%0d cycles=%0d",pc,privilege,traps,cycles);
  for(integer r=0;r<64;r=r+1)begin debug_index=r;#1;$display("R%0d=0x%064h",r,debug_value);end
  for(integer r=0;r<9;r=r+1)$display("CSR%0d=0x%064h",r,dut.csrs.registers[r]);
  $write("MEM=");for(integer n=0;n<32;n=n+1)$write("%02h",memory['h80000+n]);$display("");
  $display("PASS core completed");$finish;
 end
endmodule
