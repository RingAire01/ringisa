`timescale 1ns/1ps
module cache_case #(parameter ENTRIES=3)(output reg finished=0);
 reg clk=0;always #200 clk=~clk;
 reg reset=1,invalidate=0,insert=0;reg [115:0] vpn=0,ivpn=0;
 reg [15:0] asid=0,iasid=0;reg [63:0] root=0,iroot=0;reg [51:0] ippn=0;
 reg [8:0] iflags=0;reg idevice=0;wire hit,device;wire [51:0] ppn;wire [8:0] flags;
 ringisa_tlb #(.ENTRIES(ENTRIES)) tlb(clk,reset,invalidate,vpn,asid,root,hit,ppn,flags,device,insert,ivpn,iasid,iroot,ippn,iflags,idevice);
 reg [63:0] address=0;reg [127:0] ipte=0;wire phit;wire [127:0] pte;
 ringisa_page_walk_cache #(.ENTRIES(ENTRIES)) pwc(clk,reset,invalidate,address,root,asid,phit,pte,insert,ipte);
 reg valid[0:ENTRIES-1];reg [115:0] tags[0:ENTRIES-1];
 reg [15:0] asids[0:ENTRIES-1],pasids[0:ENTRIES-1];
 reg [63:0] roots[0:ENTRIES-1],addresses[0:ENTRIES-1],proots[0:ENTRIES-1];
 reg [51:0] ppns[0:ENTRIES-1];reg [8:0] perms[0:ENTRIES-1];reg devices[0:ENTRIES-1];reg [127:0] ptes[0:ENTRIES-1];
 integer slot=0,checks=0;reg [31:0] seed=32'h544c4232+ENTRIES;
 function [31:0] random32;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);random32=seed;end endfunction
 task verify;
  reg eh,ed,eph;reg [51:0] ep;reg [8:0] ef;reg [127:0] ept;
  begin
   eh=0;ed=0;ep=0;ef=0;eph=0;ept=0;
   for(integer i=0;i<ENTRIES;i=i+1)if(valid[i])begin
    if(tags[i]==vpn&&roots[i]==root&&(perms[i][6]||asids[i]==asid))begin eh=1;ed=devices[i];ep=ppns[i];ef=perms[i];end
    if(addresses[i]==address&&proots[i]==root&&pasids[i]==asid)begin eph=1;ept=ptes[i];end
   end
   #1;if(hit!==eh||ppn!==ep||flags!==ef||device!==ed||phit!==eph||pte!==ept)
    $fatal(1,"cache scoreboard entries=%0d seed=%h vpn=%h",ENTRIES,seed,vpn);
   checks=checks+2;
  end
 endtask
 initial begin
  for(integer i=0;i<ENTRIES;i=i+1)valid[i]=0;
  repeat(2)@(negedge clk);reset=0;
  for(integer cycle=0;cycle<1000;cycle=cycle+1)begin
   reset=cycle%233==0;invalidate=cycle%71==0;insert=cycle%4!=0;
   // Small repeated key space exercises collisions, duplicate priority and wrap.
   ivpn={84'hfedcba9876543210abcde,random32()%32'd11};iasid=random32()%4;iroot=64'hffffffff00000000+(random32()%3)*4096;
   ippn={20'habcde,random32()};iflags=random32();idevice=random32();
   address=64'hffff000000000000+(random32()%13)*16;root=iroot;asid=iasid;
   ipte={random32(),random32(),random32(),random32()};
   if(reset||invalidate)begin slot=0;for(integer i=0;i<ENTRIES;i=i+1)valid[i]=0;end
   else if(insert)begin
    valid[slot]=1;tags[slot]=ivpn;asids[slot]=iasid;roots[slot]=iroot;ppns[slot]=ippn;perms[slot]=iflags;devices[slot]=idevice;
    addresses[slot]=address;proots[slot]=root;pasids[slot]=asid;ptes[slot]=ipte;slot=slot==ENTRIES-1?0:slot+1;
   end
   @(posedge clk);
   vpn=ivpn;verify();
   asid=iasid^16'h8000;verify(); // Global entry must ignore the entire ASID.
   root=iroot^64'h8000000000000000;verify(); // Root never ignored, even global.
   root=iroot;asid=iasid;
   for(integer bit_index=0;bit_index<116;bit_index=bit_index+1)begin vpn=ivpn^(116'b1<<bit_index);verify();end
   @(negedge clk);
  end
  $display("PASS cache entries=%0d %0d checks; seed=%h, full116-bit tags/root/ASID/global, duplicate priority, wrap, invalidate/reset",ENTRIES,checks,32'h544c4232+ENTRIES);
  finished=1;
 end
endmodule
module cache_tb;
 wire a,b,c;
 cache_case #(.ENTRIES(1)) one(a);
 cache_case #(.ENTRIES(3)) odd(b);
 cache_case #(.ENTRIES(32)) normal(c);
 initial begin wait(a&&b&&c);$display("PASS TLB/PWC scoreboard");$finish;end
 initial begin #2000000;$fatal(1,"cache timeout");end
endmodule
