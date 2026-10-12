`timescale 1ns/1ps
`include "map.svh"
// Single-master address-decoding AXI4 endpoint/router. No IDs/reordering.
// Accepts independent AW/W and AR into one-entry buffers. One backend owner.
module ringisa_axi_interconnect #(parameter ROM_IMAGE="")(
 input wire clk,reset,
 input wire awvalid,output wire awready,input wire [63:0] awaddr,
 input wire [7:0] awlen,input wire [2:0] awsize,input wire [1:0] awburst,
 input wire wvalid,output wire wready,input wire [31:0] wdata,input wire [3:0] wstrb,input wire wlast,
 output reg bvalid,input wire bready,output reg [1:0] bresp,
 input wire arvalid,output wire arready,input wire [63:0] araddr,
 input wire [7:0] arlen,input wire [2:0] arsize,input wire [1:0] arburst,
 output reg rvalid,input wire rready,output reg [31:0] rdata,output reg [1:0] rresp,output wire rlast,
 output wire device_request,output wire device_write,output wire [63:0] device_address,
 output wire [31:0] device_data,output wire [3:0] device_strobes,
 input wire device_response,input wire [1:0] device_resp,input wire [31:0] device_read_data
);
 reg have_aw,have_w,have_ar;reg [63:0] wa,ra;
 reg [7:0] wl,rl;reg [2:0] ws,rs;reg [1:0] wb,rb;reg [31:0] wd;reg [3:0] st;reg last;
 localparam IDLE=0,EXEC=1,RAM=2,DEVICE=3,DRAIN=4,REJECT_W=5;
 reg [7:0] reject_left,read_left;
 reg [2:0] state;reg writing;reg [63:0] address;reg [2:0] size;reg [31:0] data;reg [3:0] strobes;reg invalid;
 assign awready=!reset&&!have_aw&&!bvalid;assign wready=!reset&&!have_w&&!bvalid;
 assign arready=!reset&&!have_ar&&!rvalid;assign rlast=read_left==0;
 wire rom=address>=`SOC_ROM_BASE&&address-`SOC_ROM_BASE<`SOC_ROM_BYTES;
 wire ram=address>=`SOC_RAM_BASE&&address-`SOC_RAM_BASE<`SOC_RAM_BYTES;
 wire device=(address>=`SOC_UART_BASE&&address-`SOC_UART_BASE<`SOC_UART_BYTES)||(address>=`SOC_TIMER_BASE&&address-`SOC_TIMER_BASE<`SOC_TIMER_BYTES)||(address>=`SOC_IRQ_BASE&&address-`SOC_IRQ_BASE<`SOC_IRQ_BYTES);
 wire [31:0] rom_data;
 ringisa_boot_rom #(.IMAGE(ROM_IMAGE)) boot_rom(address,rom_data);
 reg [2047:0] ram_addresses;reg [255:0] ram_data;reg [31:0] ram_enables;
 always @*begin
  ram_addresses=0;ram_data=0;ram_enables=0;
  for(integer i=0;i<4;i=i+1)begin
   ram_addresses[i*64+:64]=(address&~64'd3)+i;ram_data[i*8+:8]=data[i*8+:8];
   if(writing)ram_enables[i]=strobes[i];else ram_enables[i]=(i>=address[1:0]&&i<address[1:0]+(1<<size));
  end
 end
 wire ram_response,ram_error;wire [4:0] ram_fault;wire [255:0] ram_read;wire loader_ready;
 ringisa_ram_fabric #(.BASE(`SOC_RAM_BASE),.MEMORY_BYTES(`SOC_RAM_BYTES)) memory(clk,reset,state==RAM,writing,ram_addresses,ram_enables,ram_data,ram_response,ram_error,ram_fault,ram_read,1'b0,64'b0,8'b0,loader_ready);
 assign device_request=state==DEVICE;assign device_write=writing;assign device_address=address;assign device_data=data;assign device_strobes=strobes;
 task finish(input [1:0] code,input [31:0] value);
  begin if(writing)begin bvalid<=1;bresp<=code;end else begin rvalid<=1;rresp<=code;rdata<=value;end state<=DRAIN;end
 endtask
 always @(posedge clk)begin
  if(reset)begin have_aw<=0;have_w<=0;have_ar<=0;wa<=0;ra<=0;wl<=0;rl<=0;ws<=0;rs<=0;wb<=0;rb<=0;wd<=0;st<=0;last<=0;state<=IDLE;writing<=0;address<=0;size<=0;data<=0;strobes<=0;invalid<=0;bvalid<=0;bresp<=0;rvalid<=0;rdata<=0;rresp<=0;reject_left<=0;read_left<=0;end
  else begin
   if(awvalid&&awready)begin have_aw<=1;wa<=awaddr;wl<=awlen;ws<=awsize;wb<=awburst;end
   if(wvalid&&wready)begin have_w<=1;wd<=wdata;st<=wstrb;last<=wlast;end
   if(arvalid&&arready)begin have_ar<=1;ra<=araddr;rl<=arlen;rs<=arsize;rb<=arburst;end
   if(bvalid&&bready)bvalid<=0;
   if(rvalid&&rready)begin if(read_left!=0)read_left<=read_left-1;else rvalid<=0;end
   case(state)
    IDLE:if(have_aw&&have_w&&!bvalid)begin
     writing<=1;address<=wa;size<=ws;data<=wd;strobes<=st;have_aw<=0;have_w<=0;
     invalid<=wl!=0||ws>2||wb!=1||!last||(wa[1:0]&( (1<<ws)-1))!=0||((st&~(((1<<(1<<ws))-1)<<wa[1:0]))!=0);
     reject_left<=wl;state<=wl==0?EXEC:REJECT_W;
    end else if(have_ar&&!rvalid)begin writing<=0;address<=ra;size<=rs;have_ar<=0;strobes<=0;data<=0;read_left<=rl;
     invalid<=rl!=0||rs>2||rb!=1||(ra[1:0]&((1<<rs)-1))!=0;state<=EXEC;
    end
    EXEC:if(invalid)finish(2,0);
     else if(rom)begin if(writing)finish(2,0);else finish(0,rom_data);end
     else if(ram)state<=RAM;
     else if(device)begin if(size!=2)finish(2,0);else state<=DEVICE;end
     else finish(3,0);
    RAM:if(ram_response)finish(ram_error?2'd2:2'd0,ram_read[31:0]);
    DEVICE:if(device_response)finish(device_resp,device_read_data);
    REJECT_W:if(have_w)begin have_w<=0;if(reject_left==1)finish(2,0);else reject_left<=reject_left-1;end
    DRAIN:if(!bvalid&&!rvalid)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
