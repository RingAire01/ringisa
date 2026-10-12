`timescale 1ns/1ps
module ringisa_address(
 input wire [127:0] base,input wire signed [127:0] offset,
 output wire [127:0] address,output wire overflow
);
 wire [128:0] sum={1'b0,base}+{offset[127],offset};
 // The 129-bit sign extension represents a negative delta modulo 2^129.
 // A valid subtraction wraps that 129th bit away; underflow leaves it set.
 assign address=sum[127:0];assign overflow=sum[128];
endmodule
