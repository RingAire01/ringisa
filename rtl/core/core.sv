`timescale 1ns/1ps
`include "constants.svh"
module ringisa_core(
 input wire clk,reset,input wire [127:0] reset_pc,input wire [63:0] interrupts,
 output wire memory_request,memory_write,output wire [2047:0] memory_addresses,
 output wire [31:0] memory_enables,output wire [255:0] memory_write_data,
 input wire memory_response,memory_error,input wire [4:0] memory_fault_index,input wire [255:0] memory_read_data,
 input wire [5:0] debug_index,output wire [255:0] debug_value,
 output reg [127:0] pc,output wire [1:0] privilege,
 output wire waiting,output reg retired,output wire trapped,output wire [4:0] trap_cause
);
 localparam FETCH_START=0,FETCH_WAIT=1,EXECUTE=2,DATA_START=3,DATA_WAIT=4,SLEEP=5;
 reg [2:0] state;
 wire irq,exception_trap;wire [4:0] exception_cause;wire [127:0] exception_value;
 wire fetch_done;wire [4:0] fetch_fault;wire [127:0] fetch_fault_address;wire [31:0] w0,w1;
 wire fetch_memory_start;wire [127:0] fetch_memory_address;
 wire lsu_done;wire [4:0] lsu_fault;wire [127:0] lsu_fault_address;wire [255:0] lsu_data;
 ringisa_fetch fetch(clk,reset,state==FETCH_START&&!irq,pc,fetch_done,fetch_fault,fetch_fault_address,w0,w1,fetch_memory_start,fetch_memory_address,lsu_done,lsu_fault,lsu_fault_address,lsu_data);
 wire valid,extended;wire [7:0] op;wire [5:0] a,b,c;wire [3:0] func;wire signed [41:0] immediate;
 ringisa_decoder decoder(w0,w1,valid,op,a,b,c,func,extended,immediate);
 wire [255:0] ra,rb,rc;reg write_enable;reg [255:0] write_value;
 ringisa_register_file registers(clk,reset,write_enable,a,a,b,c,write_value,ra,rb,rc,debug_index,debug_value);
 wire [255:0] scalar_result,simd_result;
 ringisa_scalar scalar(op,func,rb,rc,scalar_result);
 ringisa_simd simd(op,func,rb,rc,simd_result);
 wire [127:0] sequential_pc;wire sequential_overflow;
 ringisa_address advance(pc,extended?128'sd8:128'sd4,sequential_pc,sequential_overflow);
 wire branch_taken,branch_overflow;wire [127:0] branch_target;
 ringisa_branch branch(op,b,ra,rb,pc,immediate,branch_taken,branch_target,branch_overflow);
 wire [127:0] effective;wire address_overflow;
 ringisa_address address_generator(rb[127:0],{{86{immediate[41]}},immediate},effective,address_overflow);
 wire is_load=op>=`RINGISA_LD_U8&&op<=`RINGISA_LD_256,is_store=op>=`RINGISA_ST_8&&op<=`RINGISA_ST_256,is_branch=op>=`RINGISA_BEQ&&op<=`RINGISA_JAL;
 reg [5:0] byte_count;reg signed_load;
 always @*begin
  byte_count=1;signed_load=0;
  case(op)
   `include "memory.svh"
   default:byte_count=1;
  endcase
 end
 wire [63:0] satp;wire [15:0] asid;wire [127:0] epc,tvec;wire return_valid,csr_valid;
 wire [255:0] csr_data;
 wire tlbi=state==EXECUTE&&valid&&op==`RINGISA_TLBI&&privilege!=0&&!sequential_overflow;
 wire csr_write=state==EXECUTE&&valid&&op==`RINGISA_CSRW&&!exception_trap;
 wire eret=state==EXECUTE&&valid&&op==`RINGISA_ERET&&!exception_trap;
 ringisa_csr csrs(clk,reset,exception_trap,exception_cause,pc,exception_value,eret,csr_write,immediate[3:0],rb,csr_data,csr_valid,interrupts,privilege,epc,tvec,satp,asid,irq,return_valid);
 wire data_phase=state==DATA_START||state==DATA_WAIT;
 wire start_lsu=data_phase?(state==DATA_START):fetch_memory_start;
 wire [127:0] lsu_address=data_phase?effective:fetch_memory_address;
 wire [1:0] access_kind=data_phase?(is_store?2'd2:2'd1):2'd0;
 wire bus_data_request,bus_data_write,walk_request;wire [2047:0] bus_data_addresses;
 wire [31:0] bus_data_enables;wire [255:0] bus_data_write_value;wire [63:0] walk_address;
 wire walk_response,walk_error,data_response,data_error;wire [127:0] walk_pte;wire [255:0] data_read_value;
 ringisa_load_store lsu(clk,reset,start_lsu,lsu_address,data_phase?byte_count:6'd4,access_kind,privilege,ra,satp,asid,tlbi,lsu_done,lsu_fault,lsu_fault_address,lsu_data,bus_data_request,bus_data_write,bus_data_addresses,bus_data_enables,bus_data_write_value,data_response,data_error,memory_fault_index,data_read_value,walk_request,walk_address,walk_response,walk_error,walk_pte);
 ringisa_memory_interface fabric(walk_request,walk_address,bus_data_request,bus_data_write,bus_data_addresses,bus_data_enables,bus_data_write_value,memory_request,memory_write,memory_addresses,memory_enables,memory_write_data,memory_response,memory_error,memory_read_data,walk_response,walk_error,walk_pte,data_response,data_error,data_read_value);
 wire illegal=state==EXECUTE&&!valid;
 wire overflow=state==EXECUTE&&valid&&(sequential_overflow||((is_load||is_store)&&address_overflow)||(is_branch&&branch_taken&&branch_overflow));
 wire privilege_fault=state==EXECUTE&&valid&&((op==`RINGISA_ERET&&!return_valid)||((op==`RINGISA_WFI||op==`RINGISA_TLBI)&&privilege==0)||((op==`RINGISA_CSRR||op==`RINGISA_CSRW)&&privilege!=2));
 wire csr_bad=state==EXECUTE&&valid&&op==`RINGISA_CSRW&&privilege==2&&!csr_valid;
 wire alignment_fault=state==EXECUTE&&valid&&is_branch&&branch_taken&&branch_target[1:0]!=0;
 wire [4:0] memory_fault=(state==FETCH_WAIT&&fetch_done)?fetch_fault:(state==DATA_WAIT&&lsu_done)?lsu_fault:alignment_fault?5'd6:5'd0;
 wire [127:0] fault_value=(state==FETCH_WAIT)?fetch_fault_address:(state==DATA_WAIT)?lsu_fault_address:branch_target;
 wire irq_boundary=(state==FETCH_START||state==SLEEP)&&irq;
 wire [127:0] default_fault_value=illegal||csr_bad?{96'b0,w0}:overflow&&!sequential_overflow?((is_load||is_store)?rb[127:0]:(op==`RINGISA_JAL&&b!=0?rb[127:0]:pc)):pc;
 ringisa_exception exceptions(illegal||csr_bad,overflow,privilege_fault,state==EXECUTE&&valid&&op==`RINGISA_BRK,state==EXECUTE&&valid&&op==`RINGISA_SVC,irq_boundary,memory_fault,default_fault_value,fault_value,immediate,exception_trap,exception_cause,exception_value);
 assign trapped=exception_trap;assign trap_cause=exception_cause;assign waiting=state==SLEEP;
 reg [127:0] next_pc;integer chunk_shift;reg [255:0] mask,loaded;
 always @*begin
  next_pc=sequential_pc;write_enable=0;write_value=0;chunk_shift=w0[4:2]*32;mask=0;loaded=0;
  if(state==EXECUTE&&valid&&!exception_trap)begin
   if(op>=`RINGISA_ADD&&op<=`RINGISA_MUL)begin write_enable=1;write_value=scalar_result;end
   else if(op>=`RINGISA_VADD&&op<=`RINGISA_VEQ)begin write_enable=1;write_value=simd_result;end
   else case(op)
    `RINGISA_ADDI:begin write_enable=1;write_value=rb+{{214{immediate[41]}},immediate};end
    `RINGISA_MOVI:begin write_enable=1;write_value={{214{immediate[41]}},immediate};end
    `RINGISA_CHUNK:begin write_enable=1;mask=256'hffffffff<<chunk_shift;write_value=(ra&~mask)|({224'b0,w1}<<chunk_shift);end
    `RINGISA_JAL:begin write_enable=1;write_value={128'b0,sequential_pc};end
    `RINGISA_ERET:next_pc=epc;
    `RINGISA_CSRR:begin write_enable=1;write_value=csr_data;end
    default:begin end
   endcase
   if(is_branch&&branch_taken)next_pc=branch_target;
  end
  if(state==DATA_WAIT&&lsu_done&&lsu_fault==0&&is_load)begin
   mask={256{1'b1}}>>(256-byte_count*8);loaded=lsu_data&mask;
   if(signed_load&&loaded[byte_count*8-1])loaded=loaded|~mask;
   write_enable=1;write_value=loaded;
  end
 end
 always @(posedge clk)begin
  retired<=0;
  if(reset)begin pc<=reset_pc;state<=FETCH_START;end
  else if(exception_trap)begin pc<=tvec;state<=FETCH_START;end
  else case(state)
   FETCH_START:state<=FETCH_WAIT;
   FETCH_WAIT:if(fetch_done)state<=EXECUTE;
   EXECUTE:if(is_load||is_store)state<=DATA_START;else begin pc<=next_pc;retired<=1;state<=op==`RINGISA_WFI ? SLEEP : FETCH_START;end
   DATA_START:state<=DATA_WAIT;
   DATA_WAIT:if(lsu_done)begin pc<=sequential_pc;retired<=1;state<=FETCH_START;end
   SLEEP:begin end
   default:state<=FETCH_START;
  endcase
 end
endmodule
