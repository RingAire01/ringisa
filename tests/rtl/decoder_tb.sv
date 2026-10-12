`timescale 1ns/1ps
module decoder_tb;
 reg [31:0] w0=0,w1=0;wire valid;wire [7:0] op;wire [5:0] a,b,c;wire [3:0] func;wire extended;wire signed [41:0] immediate;
 ringisa_decoder dut(w0,w1,valid,op,a,b,c,func,extended,immediate);
 reg [64:0] vectors[0:65535];string file_name;integer count;
 initial begin
  if(!$value$plusargs("vectors=%s",file_name)||!$value$plusargs("count=%d",count))$fatal(1,"missing vectors");
  if(count>65536)$fatal(1,"too many vectors");$readmemh(file_name,vectors,0,count-1);
  for(integer i=0;i<count;i=i+1)begin w0=vectors[i][31:0];w1=vectors[i][63:32];#1;if(valid!==vectors[i][64])$fatal(1,"decoder mismatch word=%h/%h valid=%b expected=%b",w0,w1,valid,vectors[i][64]);end
  $display("PASS decoder %0d vectors",count);$finish;
 end
endmodule
