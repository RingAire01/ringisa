`timescale 1ns/1ps
module ringisa_mmu #(parameter ITLB_ENTRIES=32,DTLB_ENTRIES=64,L2_ENTRIES=512)(
 input wire clk,reset,invalidate,start,
 input wire [127:0] virtual_address,input wire [1:0] access_kind,privilege,
 input wire [63:0] satp,input wire [15:0] asid,
 output reg done,output reg [4:0] fault,output reg [63:0] physical_address,output reg device,
 output wire walk_request,output wire [63:0] walk_address,
 input wire walk_response,walk_error,input wire [127:0] walk_pte
);
 localparam IDLE=0,LOOKUP=1,WALK=2;
 reg [1:0] state;reg [127:0] va;reg [1:0] kind,priv;reg [63:0] root;reg [15:0] saved_asid;
 wire ih,dh,lh;wire [51:0] ip,dp,lp;wire [8:0] iflags,dflags,lflags;wire idev,ddev,ldev;
 wire walk_done;wire [4:0] walk_fault;wire [51:0] walk_ppn;wire [8:0] walk_flags;wire walk_device;
 wire insert=state==WALK&&walk_done&&walk_fault==0&&walk_flags[7]&&(kind!=2||walk_flags[8]);
 ringisa_tlb #(.ENTRIES(ITLB_ENTRIES)) itlb(clk,reset,invalidate,va[127:12],saved_asid,root,ih,ip,iflags,idev,insert&&kind==0,va[127:12],saved_asid,root,walk_ppn,walk_flags,walk_device);
 ringisa_tlb #(.ENTRIES(DTLB_ENTRIES)) dtlb(clk,reset,invalidate,va[127:12],saved_asid,root,dh,dp,dflags,ddev,insert&&kind!=0,va[127:12],saved_asid,root,walk_ppn,walk_flags,walk_device);
 ringisa_tlb #(.ENTRIES(L2_ENTRIES)) l2(clk,reset,invalidate,va[127:12],saved_asid,root,lh,lp,lflags,ldev,insert,va[127:12],saved_asid,root,walk_ppn,walk_flags,walk_device);
 wire local_hit=kind==0?ih:dh;wire hit=local_hit||lh;
 wire [51:0] hit_ppn=local_hit?(kind==0?ip:dp):lp;
 wire [8:0] hit_flags=local_hit?(kind==0?iflags:dflags):lflags;
 wire hit_device=local_hit?(kind==0?idev:ddev):ldev;
 wire walker_start=state==LOOKUP&&!hit;
 ringisa_page_walker walker(clk,reset,walker_start,invalidate,va,root,saved_asid,walk_done,walk_fault,walk_ppn,walk_flags,walk_device,walk_request,walk_address,walk_response,walk_error,walk_pte);
 function permission;
  input [8:0] f;input [1:0] p,k;
  begin permission=(p==0?f[5]:!f[5])&&(k==0?f[4]:k==1?f[2]:f[3])&&f[7]&&(k!=2||f[8]);end
 endfunction
 always @(posedge clk)begin
  done<=0;
  if(reset)begin state<=IDLE;fault<=0;physical_address<=0;device<=0;va<=0;kind<=0;priv<=0;root<=0;saved_asid<=0;end
  else case(state)
   IDLE:if(start)begin fault<=0;
    if(privilege==2||!satp[0])begin physical_address<=virtual_address[63:0];device<=0;fault<=virtual_address[127:64]!=0?5'd10:5'd0;done<=1;end
    else begin va<=virtual_address;kind<=access_kind;priv<=privilege;root<={satp[63:12],12'b0};saved_asid<=asid;state<=LOOKUP;end
   end
   LOOKUP:if(hit)begin physical_address<={hit_ppn,va[11:0]};device<=hit_device;fault<=permission(hit_flags,priv,kind)?5'd0:5'd9;done<=1;state<=IDLE;end else state<=WALK;
   WALK:if(walk_done)begin physical_address<={walk_ppn,va[11:0]};device<=walk_device;fault<=walk_fault!=0?walk_fault:permission(walk_flags,priv,kind)?5'd0:5'd9;done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
endmodule
