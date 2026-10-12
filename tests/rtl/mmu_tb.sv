`timescale 1ns/1ps
module mmu_tb;
 reg clk=0;always #5 clk=~clk;reg reset=1,invalidate=0,start=0;
 reg [127:0] va=0;reg [1:0] kind=1,priv=0;reg [63:0] satp='h10001;reg [15:0] asid=1;
 wire done;wire [4:0] fault;wire [63:0] pa;wire device,request;wire [63:0] address;
 reg response=0,error=0;reg [127:0] pte=0;
 ringisa_mmu dut(clk,reset,invalidate,start,va,kind,priv,satp,asid,done,fault,pa,device,request,address,response,error,pte);
 reg [127:0] memory[0:3839];integer reads=0;integer i;reg [127:0] test_va=128'hffff0123456789abfedcba9876543000;
 function integer idx(input [127:0] x,input integer level);reg [127:0] shifted;begin shifted=x>>(12+8*level);idx=level==14?shifted[3:0]:shifted[7:0];end endfunction
 task map(input [127:0] x,input [51:0] ppn,input [11:0] flags);
  reg [51:0] next_ppn;
  begin for(integer l=14;l>0;l=l-1)begin next_ppn=52'h11+(14-l);memory[(14-l)*256+idx(x,l)]={32'b0,next_ppn,44'h3};end memory[14*256+idx(x,0)]={32'b0,ppn,32'b0,flags};end
 endtask
 always @(posedge clk)begin
  response<=0;if(request&&!response)begin reads<=reads+1;response<=1;error<=address<'h10000||address>='h1f000;
   if(address>='h10000&&address<'h1f000)pte<=memory[(address-'h10000)>>4];else pte<=0;
  end
 end
 task translate(input [127:0] x,input [1:0] access_type,input [4:0] expected_fault,input [63:0] expected_pa);
  begin @(negedge clk);va=x;kind=access_type;start=1;@(negedge clk);start=0;wait(done);#1;
   if(fault!==expected_fault||(expected_fault==0&&pa!==expected_pa))$fatal(1,"translate va=%h fault=%d pa=%h expected=%d/%h",x,fault,pa,expected_fault,expected_pa);
  end
 endtask
 task flush;begin @(negedge clk);invalidate=1;@(negedge clk);invalidate=0;end endtask
 initial begin
  for(i=0;i<3840;i=i+1)memory[i]=0;map(test_va,52'h40,12'h1bd);#22;reset=0;
  translate(test_va,1,0,'h40000);if(reads!=15)$fatal(1,"not exactly 15 walk reads: %d",reads);
  translate(test_va,0,0,'h40000);if(reads!=15)$fatal(1,"TLB missed");
  memory[14*256+idx(test_va,0)]={32'b0,52'h41,32'b0,12'h1bd};translate(test_va,1,0,'h40000);flush();translate(test_va,1,0,'h41000);
  @(negedge clk);asid=2;translate(test_va,1,0,'h41000);if(reads!=45)$fatal(1,"ASID not isolated: %d",reads);
  flush();memory[14*256+idx(test_va,0)][3]=0;translate(test_va,2,9,0);
  flush();memory[14*256+idx(test_va,0)][0]=0;translate(test_va,1,7,0);
  flush();memory[14*256+idx(test_va,0)][127]=1;translate(test_va,1,8,0);
  flush();map(128'hfffffffffffffffffffffffffffff000,52'h40,12'h1fd);translate({128{1'b1}},1,0,'h40fff);
  begin integer old_reads;old_reads=reads;@(negedge clk);asid=3;translate({128{1'b1}},1,0,'h40fff);if(reads!=old_reads)$fatal(1,"global mapping failed");end
  flush();memory[14*256+idx(128'hfffffffffffffffffffffffffffff000,0)]={32'b0,{52{1'b1}},32'b0,12'h1fd};translate({128{1'b1}},1,0,64'hffffffffffffffff);
  flush();satp='hdead0001;translate(test_va,1,10,0);
  $display("PASS MMU: 15 levels, full128 VA, TLB, ASID, permissions, invalid/reserved PTE, highest VA, physical fault");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
