`timescale 1ns/1ps
// Concrete single-port byte RAM fabric. All addresses are validated before
// execution; after validation on-chip RAM cannot report a later access fault.
// Loader is permitted only before CPU release / while idle, never concurrently
// with a transaction. No other agent can observe an in-progress store.
module ringisa_ram_fabric #(parameter MEMORY_BYTES=65536,parameter [63:0] BASE=0)(
 input wire clk,reset,
 input wire request,write,input wire [2047:0] addresses,
 input wire [31:0] enables,input wire [255:0] write_data,
 output reg response,response_error,output reg [4:0] fault_index,
 output reg [255:0] read_data,
 input wire loader_write,input wire [63:0] loader_address,input wire [7:0] loader_data,
 output wire loader_ready
);
 localparam IDLE=0,VALIDATE=1,TRANSFER=2,RESPOND=3;
 reg [1:0] state;reg [5:0] index;reg saved_write;
 reg [2047:0] saved_addresses;reg [31:0] saved_enables;reg [255:0] saved_data;
 reg [7:0] ram[0:MEMORY_BYTES-1];
 wire [63:0] current=saved_addresses[index*64+:64];
 wire in_range=current>=BASE&&(current-BASE)<MEMORY_BYTES;
 assign loader_ready=state==IDLE&&!request&&!reset&&loader_address>=BASE&&(loader_address-BASE)<MEMORY_BYTES;
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;response<=0;response_error<=0;fault_index<=0;read_data<=0;index<=0;saved_write<=0;saved_addresses<=0;saved_enables<=0;saved_data<=0;end
  else begin
   if(loader_write&&loader_ready)ram[loader_address-BASE]<=loader_data;
   case(state)
    IDLE:if(request)begin saved_addresses<=addresses;saved_enables<=enables;saved_data<=write_data;saved_write<=write;index<=0;response_error<=0;fault_index<=0;read_data<=0;state<=VALIDATE;end
    VALIDATE:begin
     if(saved_enables[index]&&!in_range)begin response_error<=1;fault_index<=index[4:0];response<=1;state<=RESPOND;end
     else if(index==31)begin index<=0;state<=TRANSFER;end
     else index<=index+1;
    end
    TRANSFER:begin
     if(saved_enables[index])begin
      if(saved_write)ram[current-BASE]<=saved_data[index*8+:8];
      else read_data[index*8+:8]<=ram[current-BASE];
     end
     if(index==31)begin response<=1;state<=RESPOND;end else index<=index+1;
    end
    RESPOND:if(!request)begin response<=0;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
