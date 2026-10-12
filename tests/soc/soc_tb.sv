`timescale 1ns/1ps
module soc_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1;
 wire tx;reg rx=1;wire [255:0] debug_value;wire [127:0] pc;wire [1:0] privilege;
 wire waiting,retired,trapped;wire [4:0] cause;wire tx_event;wire [7:0] tx_byte;
 reg [5:0] debug_index=60;
 ringisa_soc #(.ROM_IMAGE("target/soc/current.hex")) dut(clk,reset,rx,tx,1'b0,debug_index,debug_value,pc,privilege,waiting,retired,trapped,cause,tx_event,tx_byte);
 integer cycles=0,retire_count=0,irq_entries=0,uart_count=0;integer expect_uart=0,expect_irq=0,expect_memory=0,expect_privilege=2,signature=32,expect_fault=0;
 reg [7:0] received[0:63];reg [7:0] byte_value;string expected="RingISA SoC boot OK\n";
 initial begin
  if($value$plusargs("uart=%d",expect_uart))begin end
  if($value$plusargs("irq=%d",expect_irq))begin end
  if($value$plusargs("memory=%d",expect_memory))begin end
  if($value$plusargs("privilege=%d",expect_privilege))begin end
  if($value$plusargs("signature=%d",signature))begin end
  if($value$plusargs("fault=%d",expect_fault))begin end
  #32;reset=0;
 end
 // Replay boundary events for the independent C architectural model. Device
 // read inputs and interrupt arrival are observations, not a duplicate timer.
 always @(negedge clk)if(!reset)begin
  if(dut.device_req&&dut.device_response&&!dut.device_write&&dut.device_resp==0)
   $display("INPUT %016h %08h",dut.device_address,dut.device_read);
  if(trapped)$display("TRAP %0d",cause);
  if(retired)$display("STEP");
 end
 always @(posedge clk)if(!reset&&dut.bus.state==2&&dut.bus.ram_response&&!dut.bus.ram_error&&dut.bus.writing)begin
  for(integer b=0;b<4;b=b+1)if(dut.bus.strobes[b])
   $display("WRITE %016h %02h",(dut.bus.address&~64'd3)+b,dut.bus.data[b*8+:8]);
 end
 // Independent wire-level 8N1 monitor, not the UART's instrumentation event.
 initial forever begin
  @(negedge tx);if(!reset)begin
   repeat(6)@(posedge clk);#1;
   for(integer b=0;b<8;b=b+1)begin byte_value[b]=tx;repeat(4)@(posedge clk);#1;end
   if(tx!==1)$fatal(1,"UART stop bit");
   if(uart_count>=64)$fatal(1,"UART overflow");received[uart_count]=byte_value;uart_count=uart_count+1;
  end
 end
 always @(posedge clk)if(!reset)begin
  cycles<=cycles+1;if(retired)retire_count<=retire_count+1;
  if(trapped)begin if(cause!=(expect_fault!=0?expect_fault:14))$fatal(1,"unexpected trap %0d pc=%h",cause,pc);irq_entries<=irq_entries+1;end
  if(cycles>1000000)$fatal(1,"SoC timeout pc=%h",pc);
 end
 initial begin
  wait(!reset);wait(waiting);#2;
  if(debug_value!==256'd24589)$fatal(1,"execution failure signature %h pc=%h",debug_value,pc);
  if(dut.bus.memory.ram[signature]!==8'h0d||dut.bus.memory.ram[signature+1]!==8'h60)$fatal(1,"RAM success signature missing");
  if(retire_count<5||privilege!=expect_privilege)$fatal(1,"CPU execution/privilege failure");
  if(expect_memory)begin
   if({dut.bus.memory.ram[3],dut.bus.memory.ram[2],dut.bus.memory.ram[1],dut.bus.memory.ram[0]}!==32'h12345678)$fatal(1,"RAM read/write test");
   debug_index=24;#1;if(debug_value!==256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef)$fatal(1,"cross-page memory compare");
  end
  if(expect_uart)begin
   if(uart_count!=expected.len())$fatal(1,"UART count %0d expected%0d",uart_count,expected.len());
   for(integer i=0;i<expected.len();i=i+1)if(received[i]!==expected[i])$fatal(1,"UART character %0d",i);
  end else if(uart_count!=0)$fatal(1,"unexpected UART output");
  if(expect_irq)begin
   debug_index=30;#1;if(debug_value!=1||irq_entries!=1)$fatal(1,"interrupt count %0d R30=%h",irq_entries,debug_value);
   if(dut.cpu.csrs.registers[1]!=14||dut.cpu.csrs.registers[4][4]!=0||dut.peripherals.timer.pending||dut.interrupts!=0)$fatal(1,"interrupt ack/return failed");
  end else if(irq_entries!=(expect_fault!=0?1:0))$fatal(1,"unexpected interrupt/fault count");
  for(integer i=0;i<64;i=i+1)begin debug_index=i;#1;$display("R%0d=0x%064h",i,debug_value);end
  for(integer i=0;i<9;i=i+1)$display("CSR%0d=0x%064h",i,dut.cpu.csrs.registers[i]);
  $display("FINAL pc=%032h",pc);
  $display("PASS SoC ROM execution cycles=%0d retired=%0d UART bytes=%0d interrupts=%0d",cycles,retire_count,uart_count,irq_entries);$finish;
 end
endmodule
