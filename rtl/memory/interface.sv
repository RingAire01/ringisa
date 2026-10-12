// Fixed-priority arbiter. Walker and ordinary transaction requests cannot
// overlap: LSU finishes translating before it submits the ordinary access.
`timescale 1ns/1ps
module ringisa_memory_interface(
 input wire walk_request,input wire [63:0] walk_address,
 input wire data_request,data_write,input wire [2047:0] data_addresses,
 input wire [31:0] data_enables,input wire [255:0] data_write_value,
 output wire bus_request,bus_write,output reg [2047:0] bus_addresses,
 output wire [31:0] bus_enables,output wire [255:0] bus_write_value,
 input wire bus_response,bus_error,input wire [255:0] bus_read_value,
 output wire walk_response,walk_error,output wire [127:0] walk_pte,
 output wire data_response,data_error,output wire [255:0] data_read_value
);
 assign bus_request=walk_request||data_request;
 assign bus_write=!walk_request&&data_write;
 assign bus_enables=walk_request?32'h0000ffff:data_enables;
 assign bus_write_value=walk_request?256'b0:data_write_value;
 always @*begin
  bus_addresses=walk_request?2048'b0:data_addresses;
  for(integer i=0;i<16;i=i+1)if(walk_request)bus_addresses[i*64+:64]=walk_address+i;
 end
 assign walk_response=walk_request&&bus_response;assign walk_error=bus_error;assign walk_pte=bus_read_value[127:0];
 assign data_response=!walk_request&&bus_response;assign data_error=bus_error;assign data_read_value=bus_read_value;
endmodule
