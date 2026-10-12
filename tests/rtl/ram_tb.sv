`timescale 1ns/1ps
module ram_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1,request=0,write=0;
 reg [2047:0] addresses=0;reg [31:0] enables=0;reg [255:0] write_data=0;
 wire response,error;wire [4:0] index;wire [255:0] read_data;
 reg loader_write=0;reg [63:0] loader_address=0;reg [7:0] loader_data=0;wire ready;
 ringisa_ram_fabric #(.MEMORY_BYTES(4096),.BASE(64'hfffffffffffff000)) dut(clk,reset,request,write,addresses,enables,write_data,response,error,index,read_data,loader_write,loader_address,loader_data,ready);
 task transact(input bit writing,input bit bad);
  begin
   @(negedge clk);write=writing;enables=32'hffffffff;write_data={32{8'h5a}};
   for(integer i=0;i<32;i=i+1)addresses[i*64+:64]=64'hfffffffffffff000+i;
   if(bad)addresses[31*64+:64]=0;request=1;wait(response);#1;
   if(error!==bad||(bad&&index!=31))$fatal(1,"fabric error handling");
   @(negedge clk);request=0;wait(!response);@(negedge clk);
  end
 endtask
 initial begin
  #22;reset=0;
  for(integer i=0;i<32;i=i+1)begin @(negedge clk);loader_write=1;loader_address=64'hfffffffffffff000+i;loader_data=8'h11;if(!ready)begin #1;if(!ready)$fatal(1,"loader not ready");end end
  @(negedge clk);loader_write=0;
  transact(1,1);transact(0,0);if(read_data!=={32{8'h11}})$fatal(1,"partial failed store");
  transact(1,0);transact(0,0);if(read_data!=={32{8'h5a}})$fatal(1,"store/read mismatch");
  $display("PASS concrete RAM fabric: full64 physical base, loader, atomic fault, 256-bit transaction");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
