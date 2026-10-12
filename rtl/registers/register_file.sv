`timescale 1ns/1ps
module ringisa_register_file(
 input wire clk,reset,write_enable,
 input wire [5:0] write_index,read_a,read_b,read_c,
 input wire [255:0] write_data,
 output wire [255:0] value_a,value_b,value_c,
 input wire [5:0] debug_index,
 output wire [255:0] debug_value
);
 reg [255:0] registers[0:63];integer i;
 assign value_a=read_a==0?256'b0:registers[read_a];
 assign value_b=read_b==0?256'b0:registers[read_b];
 assign value_c=read_c==0?256'b0:registers[read_c];
 assign debug_value=debug_index==0?256'b0:registers[debug_index];
 always @(posedge clk)begin
  if(reset)for(i=0;i<64;i=i+1)registers[i]<=0;
  else if(write_enable&&write_index!=0)registers[write_index]<=write_data;
 end
endmodule
