`timescale 1ns/1ps
module address_tb;
 reg [127:0] base=0;reg signed [127:0] offset=0;
 wire [127:0] address;wire overflow;
 ringisa_address dut(base,offset,address,overflow);
 task check(input [127:0] a,input signed [127:0] delta,input [127:0] expected,input bit fault);
  begin base=a;offset=delta;#1;if(address!==expected||overflow!==fault)$fatal(1,"address=%h delta=%h result=%h overflow=%b expected=%h/%b",a,delta,address,overflow,expected,fault);end
 endtask
 initial begin
  check(0,-128'sd1,{128{1'b1}},1);
  check(1,-128'sd1,0,0);
  check({128{1'b1}},-128'sd1,128'hfffffffffffffffffffffffffffffffe,0);
  check({128{1'b1}},128'sd1,0,1);
  check(128'h10000000000000000,-128'sd1,128'hffffffffffffffff,0);
  check(128'hffffffffffffffff,128'sd1,128'h10000000000000000,0);
  for(integer i=0;i<128;i=i+1)begin check(128'b1<<i,-128'sd1,(128'b1<<i)-1,0);end
  $display("PASS 128-bit address generator: positive/negative offsets, carry, underflow, all128 bit positions");$finish;
 end
endmodule
