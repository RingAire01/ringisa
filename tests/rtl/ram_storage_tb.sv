`timescale 1ns/1ps
module ram_storage_case #(parameter BYTES=67)(output reg finished=0);
 localparam [63:0] BASE=64'hffffffffffffffff-(BYTES-1);
 reg clk=0;always #5 clk=~clk;reg reset=1,request=0,writing=0;
 reg [2047:0] addresses=0;reg [31:0] enables=0;reg [255:0] data=0;
 wire response,error;wire [4:0] fault_index;wire [255:0] read_data;
 reg load=0;reg [63:0] load_address=0;reg [7:0] load_data=0;wire load_ready;
 ringisa_ram_fabric #(.MEMORY_BYTES(BYTES),.BASE(BASE)) dut(clk,reset,request,writing,addresses,enables,data,response,error,fault_index,read_data,load,load_address,load_data,load_ready);
 reg [7:0] expected[0:BYTES-1];reg [31:0] seed=32'h52414d32+BYTES;
 reg [255:0] expected_read;integer checks=0;reg expected_error;reg [4:0] expected_index;
 function [31:0] random32;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);random32=seed;end endfunction
 task transact;
  begin
   expected_read=0;expected_error=0;expected_index=0;
   for(integer i=31;i>=0;i=i-1)if(enables[i]&&addresses[i*64+:64]<BASE)begin expected_error=1;expected_index=i;end
   if(!expected_error)for(integer i=0;i<32;i=i+1)if(enables[i])begin
    if(writing)expected[addresses[i*64+:64]-BASE]=data[i*8+:8];
    else expected_read[i*8+:8]=expected[addresses[i*64+:64]-BASE];
   end
   request=1;load=1;load_address=BASE;load_data=8'hff;
   #1;if(load_ready)$fatal(1,"loader accepted concurrent request");
   // Inputs are not a live scatter list: mutate after the request is captured.
   @(negedge clk);addresses=0;data=0;enables=0;
   wait(response);#1;
   if(error!==expected_error||(error&&fault_index!==expected_index))$fatal(1,"RAM fault bytes=%0d seed=%h",BYTES,seed);
   if(!writing&&!error&&read_data!==expected_read)$fatal(1,"RAM read bytes=%0d seed=%h got=%h expected=%h",BYTES,seed,read_data,expected_read);
   repeat(2)begin @(negedge clk);if(!response)$fatal(1,"RAM response not held");end
   load=0;request=0;wait(!response);@(negedge clk);checks=checks+1;
  end
 endtask
 initial begin
  repeat(2)@(negedge clk);reset=0;
  for(integer i=0;i<BYTES;i=i+1)begin
   load=1;load_address=BASE+i;load_data=i^8'h5a;expected[i]=load_data;
   #1;if(!load_ready)$fatal(1,"loader bytes=%0d",BYTES);@(negedge clk);
  end
  load=0;load_address=0;#1;if(load_ready)$fatal(1,"loader range check");
  for(integer trial=0;trial<240;trial=trial+1)begin
   writing=trial%3!=0;enables=trial%17==0?0:random32();
   for(integer i=0;i<32;i=i+1)begin
    addresses[i*64+:64]=enables[i]?BASE+random32()%BYTES:64'b0;data[i*8+:8]=random32();
   end
   if(trial%13==0)begin enables[31]=1;addresses[31*64+:64]=0;end
   transact();
  end
  // Read reset at the extra synchronous-memory wait phase. Data remains intact.
  writing=0;enables=1;addresses=0;addresses[63:0]=BASE;request=1;
  wait(dut.state==4);@(negedge clk);reset=1;request=0;
  repeat(2)@(negedge clk);if(response||error||read_data!=0)$fatal(1,"RAM reset response");reset=0;
  for(integer i=0;i<BYTES;i=i+1)begin writing=0;enables=1;addresses=0;addresses[63:0]=BASE+i;transact();end
  $display("PASS synchronous RAM bytes=%0d %0d transactions; seed=%h, scatter/duplicates/masks/fault atomicity/source capture/loader exclusion/reset retention",BYTES,checks,32'h52414d32+BYTES);
  finished=1;
 end
endmodule
module ram_storage_tb;
 wire a,b,c;
 ram_storage_case #(.BYTES(1)) one(a);
 ram_storage_case #(.BYTES(67)) odd(b);
 ram_storage_case #(.BYTES(513)) larger(c);
 initial begin wait(a&&b&&c);$display("PASS synchronous RAM scoreboard");$finish;end
 initial begin #2000000;$fatal(1,"RAM storage timeout");end
endmodule
