`timescale 1ns/1ps
module ringisa_csr(
 input wire clk,reset,
 input wire trap,input wire [4:0] trap_cause,input wire [127:0] trap_pc,trap_value,
 input wire eret,
 input wire write_enable,input wire [3:0] index,input wire [255:0] write_data,
 output wire [255:0] read_data,output reg write_valid,
 input wire [63:0] interrupts,
 output reg [1:0] privilege,
 output wire [127:0] epc,tvec,output wire [63:0] satp,output wire [15:0] asid,
 output wire interrupt_pending,output wire return_valid
);
 reg [255:0] registers[0:8];integer i;
 assign read_data=index<9?(index==8?{192'b0,interrupts|registers[8][63:0]}:registers[index]):256'b0;
 assign epc=registers[0][127:0];assign tvec=registers[3][127:0];assign satp=registers[5][63:0];assign asid=registers[6][15:0];
 assign interrupt_pending=registers[4][0]&&|(registers[7][63:0]&(interrupts|registers[8][63:0]));
 assign return_valid=privilege==2&&registers[4][4]&&registers[4][2:1]!=3&&epc[1:0]==0;
 always @*begin
  write_valid=index<9&&privilege==2;
  if(index==0||index==2||index==3)begin if(write_data[255:128]!=0||(index!=2&&write_data[1:0]!=0))write_valid=0;end
  else begin
   if(write_data[255:64]!=0)write_valid=0;
   if(index==5&&write_data[11:1]!=0)write_valid=0;
   if(index==6&&write_data[63:16]!=0)write_valid=0;
   if(index==4&&(write_data[63:5]!=0||write_data[2:1]==3))write_valid=0;
  end
 end
 always @(posedge clk)begin
  if(reset)begin privilege<=2;for(i=0;i<9;i=i+1)registers[i]<=0;end
  else if(trap)begin
   registers[0]<={128'b0,trap_pc};registers[1]<={251'b0,trap_cause};registers[2]<={128'b0,trap_value};
   registers[4][4:0]<={1'b1,registers[4][0],privilege,1'b0};privilege<=2;
  end
  else if(eret&&return_valid)begin privilege<=registers[4][2:1];registers[4][4:0]<={4'b0,registers[4][3]};end
  else if(write_enable&&write_valid)registers[index]<=write_data;
 end
endmodule
