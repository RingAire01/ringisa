`timescale 1ns/1ps
// Serialized AXI backend transaction -> independent AXI-Lite AW/W/AR channels.
module ringisa_axi_lite_bridge(
 input wire clk,reset,request,write,input wire [63:0] address,
 input wire [31:0] write_data,input wire [3:0] strobes,
 output wire response,output wire [1:0] resp,output wire [31:0] read_data,
 output wire awvalid,input wire awready,output wire [63:0] awaddr,
 output wire wvalid,input wire wready,output wire [31:0] wdata,output wire [3:0] wstrb,
 input wire bvalid,output wire bready,input wire [1:0] bresp,
 output wire arvalid,input wire arready,output wire [63:0] araddr,
 input wire rvalid,output wire rready,input wire [31:0] rdata,input wire [1:0] rresp
);
 reg active,aw_sent,w_sent,ar_sent;
 assign awvalid=active&&write&&!aw_sent;assign awaddr=address;
 assign wvalid=active&&write&&!w_sent;assign wdata=write_data;assign wstrb=strobes;
 assign bready=active&&write&&aw_sent&&w_sent;
 assign arvalid=active&&!write&&!ar_sent;assign araddr=address;
 assign rready=active&&!write&&ar_sent;
 assign response=(bready&&bvalid)||(rready&&rvalid);assign resp=write?bresp:rresp;assign read_data=rdata;
 always @(posedge clk)begin
  if(reset)begin active<=0;aw_sent<=0;w_sent<=0;ar_sent<=0;end
  else begin
   if(!request)begin active<=0;aw_sent<=0;w_sent<=0;ar_sent<=0;end
   else if(!active)active<=1;
   if(awvalid&&awready)aw_sent<=1;if(wvalid&&wready)w_sent<=1;if(arvalid&&arready)ar_sent<=1;
  end
 end
endmodule
