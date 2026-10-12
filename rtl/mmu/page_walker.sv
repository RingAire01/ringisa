`timescale 1ns/1ps
module ringisa_page_walker(
 input wire clk,reset,start,invalidate,
 input wire [127:0] virtual_address,input wire [63:0] root,input wire [15:0] asid,
 output reg done,output reg [4:0] fault,output reg [51:0] ppn,
 output reg [8:0] flags,output reg device,
 output wire request,output wire [63:0] physical_address,
 input wire response,input wire response_error,input wire [127:0] response_pte
);
 localparam IDLE=0,LOOKUP=1,READ=2,CHECK=3;
 reg [2:0] state;reg [127:0] va,pte;reg [63:0] table_base,saved_root;reg [15:0] saved_asid;
 reg [3:0] level;reg global_seen;wire [127:0] shifted=va>>(12+8*level);
 wire [7:0] index=level==14?{4'b0,shifted[3:0]}:shifted[7:0];
 assign physical_address=table_base+{52'b0,index,4'b0};assign request=state==READ;
 wire cache_hit;wire [127:0] cache_pte;
 wire cache_insert=state==CHECK&&pte[1]&&pte[0]&&pte[127:96]==0&&pte[27:12]==0&&pte[11:9]==0&&pte[8:7]==0&&pte[5:2]==0&&level!=0;
 ringisa_page_walk_cache cache(clk,reset,invalidate,physical_address,saved_root,saved_asid,cache_hit,cache_pte,cache_insert,pte);
 always @(posedge clk)begin
  done<=0;
  if(reset)begin state<=IDLE;fault<=0;ppn<=0;flags<=0;device<=0;level<=0;global_seen<=0;va<=0;table_base<=0;saved_root<=0;saved_asid<=0;pte<=0;end
  else case(state)
   IDLE:if(start)begin va<=virtual_address;table_base<=root;saved_root<=root;saved_asid<=asid;level<=14;global_seen<=0;fault<=0;state<=LOOKUP;end
   LOOKUP:if(cache_hit)begin pte<=cache_pte;state<=CHECK;end else state<=READ;
   READ:if(response)begin if(response_error)begin fault<=10;done<=1;state<=IDLE;end else begin pte<=response_pte;state<=CHECK;end end
   CHECK:begin
    if(pte[127:96]!=0)begin fault<=8;done<=1;state<=IDLE;end
    else if(!pte[0])begin fault<=7;done<=1;state<=IDLE;end
    else if(pte[11:9]!=0||pte[27:12]>1||(pte[3]&&!pte[2]))begin fault<=8;done<=1;state<=IDLE;end
    else if(pte[1])begin
     if(level==0||pte[8:7]!=0||pte[5:2]!=0||pte[27:12]!=0)begin fault<=8;done<=1;state<=IDLE;end
     else begin table_base<={pte[95:44],12'b0};level<=level-1;global_seen<=global_seen||pte[6];state<=LOOKUP;end
    end else if(level!=0)begin fault<=8;done<=1;state<=IDLE;end
    else begin ppn<=pte[95:44];flags<=pte[8:0]|(global_seen?9'd64:9'd0);device<=pte[27:12]==1;done<=1;state<=IDLE;end
   end
   default:state<=IDLE;
  endcase
 end
endmodule
