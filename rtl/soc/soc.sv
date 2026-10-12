`timescale 1ns/1ps
`include "map.svh"
module ringisa_soc #(parameter ROM_IMAGE="",parameter CLOCK_HZ=50000000)(
 input wire clk,reset,input wire uart_rx,output wire uart_tx,input wire external_irq,
 input wire [5:0] debug_index,output wire [255:0] debug_value,
 output wire [127:0] pc,output wire [1:0] privilege,
 output wire waiting,retired,trapped,output wire [4:0] trap_cause,
 output wire tx_event,output wire [7:0] tx_byte
);
 wire request,writing,response,error;wire [2047:0] addresses;wire [31:0] enables;
 wire [255:0] write_data,read_data;wire [4:0] fault_index;wire [63:0] interrupts;
 ringisa_core cpu(clk,reset,128'b0,interrupts,request,writing,addresses,enables,write_data,response,error,fault_index,read_data,debug_index,debug_value,pc,privilege,waiting,retired,trapped,trap_cause);
 wire awv,awr,wv,wr,bv,br,arv,arr,rv,rr,last,rlast;
 wire [63:0] awa,ara;wire [31:0] wd,rd;wire [3:0] st;
 wire [7:0] awl,arl;wire [2:0] aws,ars;wire [1:0] awb,arb,bcode,rcode;
 ringisa_cpu_axi adapter(clk,reset,request,writing,addresses,enables,write_data,response,error,fault_index,read_data,awv,awr,awa,awl,aws,awb,wv,wr,wd,st,last,bv,br,bcode,arv,arr,ara,arl,ars,arb,rv,rr,rd,rcode,rlast);
 wire device_req,device_write,device_response;wire [63:0] device_address;wire [31:0] device_data,device_read;wire [3:0] device_strobes;wire [1:0] device_resp;
 ringisa_axi_interconnect #(.ROM_IMAGE(ROM_IMAGE)) bus(clk,reset,awv,awr,awa,awl,aws,awb,wv,wr,wd,st,last,bv,br,bcode,arv,arr,ara,arl,ars,arb,rv,rr,rd,rcode,rlast,device_req,device_write,device_address,device_data,device_strobes,device_response,device_resp,device_read);
 wire lav,lar,lv,lr,lbv,lbr,lrv,lrr,lrav,lrar;wire [63:0] la,lra;wire [31:0] ld,lrd;wire [3:0] ls;wire [1:0] lbc,lrc;
 ringisa_axi_lite_bridge bridge(clk,reset,device_req,device_write,device_address,device_data,device_strobes,device_response,device_resp,device_read,lav,lar,la,lv,lr,ld,ls,lbv,lbr,lbc,lrav,lrar,lra,lrv,lrr,lrd,lrc);
 ringisa_peripherals #(.CLOCK_HZ(CLOCK_HZ)) peripherals(clk,reset,lav,lar,la,lv,lr,ld,ls,lbv,lbr,lbc,lrav,lrar,lra,lrv,lrr,lrd,lrc,uart_rx,uart_tx,external_irq,interrupts,tx_event,tx_byte);
endmodule
