`timescale 1ns/1ps
`include "map.svh"
// Sole master, single-beat AXI4, 64-bit PA / 32-bit data. Preflight the
// complete guest transaction before issuing ANY side-effecting request.
module ringisa_cpu_axi(
 input wire clk,reset,request,write,input wire [2047:0] addresses,
 input wire [31:0] enables,input wire [255:0] write_data,
 output reg response,response_error,output reg [4:0] fault_index,
 output reg [255:0] read_data,
 output wire awvalid,input wire awready,output wire [63:0] awaddr,
 output wire [7:0] awlen,output wire [2:0] awsize,output wire [1:0] awburst,
 output wire wvalid,input wire wready,output wire [31:0] wdata,
 output wire [3:0] wstrb,output wire wlast,
 input wire bvalid,output wire bready,input wire [1:0] bresp,
 output wire arvalid,input wire arready,output wire [63:0] araddr,
 output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
 input wire rvalid,output wire rready,input wire [31:0] rdata,
 input wire [1:0] rresp,input wire rlast
);
 localparam IDLE=0,CHECK=1,NEXT=2,SEND_W=3,WAIT_B=4,SEND_R=5,WAIT_R=6,END=7;
 reg [3:0] state;reg [2047:0] saved_addresses;reg [31:0] mask;
 reg [255:0] data;reg writing,peripheral;reg [5:0] index;
 reg aw_sent,w_sent;
 wire [63:0] address=saved_addresses[index*64+:64];
 function in_rom(input [63:0] a);begin in_rom=a>=`SOC_ROM_BASE&&a-`SOC_ROM_BASE<`SOC_ROM_BYTES;end endfunction
 function in_ram(input [63:0] a);begin in_ram=a>=`SOC_RAM_BASE&&a-`SOC_RAM_BASE<`SOC_RAM_BYTES;end endfunction
 function in_device(input [63:0] a);begin in_device=(a>=`SOC_UART_BASE&&a-`SOC_UART_BASE<`SOC_UART_BYTES)||(a>=`SOC_TIMER_BASE&&a-`SOC_TIMER_BASE<`SOC_TIMER_BYTES)||(a>=`SOC_IRQ_BASE&&a-`SOC_IRQ_BASE<`SOC_IRQ_BYTES);end endfunction
 wire [63:0] first=saved_addresses[63:0];
 wire device_shape=mask==32'hf&&first[1:0]==0&&
    saved_addresses[127:64]==first+1&&saved_addresses[191:128]==first+2&&saved_addresses[255:192]==first+3;
 assign awvalid=state==SEND_W&&!aw_sent;assign awaddr=address;assign awlen=0;assign awsize=peripheral?3'd2:3'd0;assign awburst=1;
 assign wvalid=state==SEND_W&&!w_sent;assign wdata=peripheral?data[31:0]:({24'b0,data[index*8+:8]}<<(address[1:0]*8));
 assign wstrb=peripheral?4'hf:(4'b1<<address[1:0]);assign wlast=1;assign bready=state==WAIT_B;
 assign arvalid=state==SEND_R;assign araddr=address;assign arlen=0;assign arsize=peripheral?3'd2:3'd0;assign arburst=1;
 assign rready=state==WAIT_R;
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;response<=0;response_error<=0;fault_index<=0;read_data<=0;saved_addresses<=0;mask<=0;data<=0;writing<=0;peripheral<=0;index<=0;aw_sent<=0;w_sent<=0;end
  else case(state)
   IDLE:if(request)begin saved_addresses<=addresses;mask<=enables;data<=write_data;writing<=write;index<=0;response_error<=0;read_data<=0;fault_index<=0;peripheral<=0;state<=CHECK;end
   CHECK:begin
    if(mask[index]&&(!(in_rom(address)||in_ram(address)||in_device(address))||(writing&&in_rom(address))||
       (in_device(address)&&(!device_shape||!in_device(first)))||
       (device_shape&&in_device(first)&&!in_device(address))))begin
      response_error<=1;fault_index<=index[4:0];response<=1;state<=END;
    end else if(index==31)begin peripheral<=device_shape&&in_device(first);index<=0;state<=NEXT;end else index<=index+1;
   end
   NEXT:if(mask[index])begin aw_sent<=0;w_sent<=0;state<=writing?SEND_W:SEND_R;end
        else if(index==31)begin response<=1;state<=END;end else index<=index+1;
   SEND_W:begin
    if(awvalid&&awready)aw_sent<=1;if(wvalid&&wready)w_sent<=1;
    if((aw_sent||awready)&&(w_sent||wready))state<=WAIT_B;
   end
   WAIT_B:if(bvalid)begin
    if(bresp!=0)begin response_error<=1;fault_index<=index[4:0];response<=1;state<=END;end
    else if(peripheral||index==31)begin response<=1;state<=END;end else begin index<=index+1;state<=NEXT;end
   end
   SEND_R:if(arready)state<=WAIT_R;
   WAIT_R:if(rvalid)begin
    if(rresp!=0||!rlast)begin response_error<=1;fault_index<=index[4:0];response<=1;state<=END;end
    else begin
     if(peripheral)read_data[31:0]<=rdata;else read_data[index*8+:8]<=rdata>>(address[1:0]*8);
     if(peripheral||index==31)begin response<=1;state<=END;end else begin index<=index+1;state<=NEXT;end
    end
   end
   END:if(!request)begin response<=0;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
endmodule
