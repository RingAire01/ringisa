`timescale 1ns/1ps
// Board independent wrapper: asynchronous reset request, synchronous release.
// Active-high reset must be held for at least two clock edges. No pin assignment.
module ringisa_soc_fpga #(parameter ROM_IMAGE="target/soc/combined.hex",parameter CLOCK_HZ=25000000)(
 input wire clk,reset_request,uart_rx,external_irq,
 output wire uart_tx,output wire sleeping,output wire trap_status
);
 reg reset_meta=1,reset_sync=1;
 always @(posedge clk)begin reset_meta<=reset_request;reset_sync<=reset_meta;end
 wire [255:0] debug_value;wire [127:0] pc;wire [1:0] privilege;
 wire retired;wire [4:0] cause;wire event_tx;wire [7:0] byte_tx;
 ringisa_soc #(.ROM_IMAGE(ROM_IMAGE),.CLOCK_HZ(CLOCK_HZ)) soc(clk,reset_sync,uart_rx,uart_tx,external_irq,6'b0,debug_value,pc,privilege,sleeping,retired,trap_status,cause,event_tx,byte_tx);
endmodule
