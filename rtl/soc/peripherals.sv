`timescale 1ns/1ps
`include "map.svh"
module ringisa_peripherals #(parameter CLOCK_HZ=50000000)(
 input wire clk,reset,
 input wire awvalid,output wire awready,input wire [63:0] awaddr,
 input wire wvalid,output wire wready,input wire [31:0] wdata,input wire [3:0] wstrb,
 output reg bvalid,input wire bready,output reg [1:0] bresp,
 input wire arvalid,output wire arready,input wire [63:0] araddr,
 output reg rvalid,input wire rready,output reg [31:0] rdata,output reg [1:0] rresp,
 input wire uart_rx,output wire uart_tx,input wire external_irq,
 output wire [63:0] interrupts,output wire tx_event,output wire [7:0] tx_byte
);
 reg have_aw,have_w;reg [63:0] address;reg [31:0] data;reg [3:0] strobes;
 assign awready=!reset&&!have_aw&&!bvalid;assign wready=!reset&&!have_w&&!bvalid;
 // Writes own register access when complete. Reads may be accepted independently.
 wire do_write=have_aw&&have_w&&!bvalid;
 assign arready=!reset&&!rvalid&&!do_write;
 wire do_read=arvalid&&arready;wire access=do_write||do_read;
 wire [63:0] current=do_write?address:araddr;
 wire sel_uart=current>=`SOC_UART_BASE&&current-`SOC_UART_BASE<`SOC_UART_BYTES;
 wire sel_timer=current>=`SOC_TIMER_BASE&&current-`SOC_TIMER_BASE<`SOC_TIMER_BYTES;
 wire sel_irq=current>=`SOC_IRQ_BASE&&current-`SOC_IRQ_BASE<`SOC_IRQ_BYTES;
 wire aligned=current[1:0]==0;
 wire [31:0] ud,td,id;wire ue,te,ie,ui,ti;reg ext_meta,ext_sync;
 ringisa_uart #(.CLOCK_HZ(CLOCK_HZ)) uart(clk,reset,access&&sel_uart&&aligned,do_write,current[11:0],data,strobes,ud,ue,uart_rx,uart_tx,ui,tx_event,tx_byte);
 ringisa_timer timer(clk,reset,access&&sel_timer&&aligned,do_write,current[11:0],data,strobes,td,te,ti);
 ringisa_interrupt_controller irq_controller(clk,reset,{ext_sync,ui,ti},access&&sel_irq&&aligned,do_write,current[11:0],data,strobes,id,ie,interrupts);
 wire [31:0] result=sel_uart?ud:sel_timer?td:id;
 wire [1:0] code=!(sel_uart||sel_timer||sel_irq)?2'd3:!aligned||(sel_uart?ue:sel_timer?te:ie)?2'd2:2'd0;
 always @(posedge clk)begin
  if(reset)begin have_aw<=0;have_w<=0;address<=0;data<=0;strobes<=0;bvalid<=0;bresp<=0;rvalid<=0;rresp<=0;rdata<=0;ext_meta<=0;ext_sync<=0;end
  else begin
   ext_meta<=external_irq;ext_sync<=ext_meta;
   if(awvalid&&awready)begin address<=awaddr;have_aw<=1;end
   if(wvalid&&wready)begin data<=wdata;strobes<=wstrb;have_w<=1;end
   if(bvalid&&bready)bvalid<=0;if(rvalid&&rready)rvalid<=0;
   if(do_write)begin bvalid<=1;bresp<=code;have_aw<=0;have_w<=0;end
   if(do_read)begin rvalid<=1;rresp<=code;rdata<=result;end
  end
 end
endmodule
