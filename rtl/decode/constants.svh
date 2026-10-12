// Generated opcode constants.
`default_nettype none
`ifndef RINGISA_OPCODES_CONSTANTS
`define RINGISA_OPCODES_CONSTANTS
`define RINGISA_ADD 8'd1
`define RINGISA_SUB 8'd2
`define RINGISA_AND 8'd3
`define RINGISA_OR 8'd4
`define RINGISA_XOR 8'd5
`define RINGISA_SHL 8'd6
`define RINGISA_SHR 8'd7
`define RINGISA_SAR 8'd8
`define RINGISA_SLTU 8'd9
`define RINGISA_SLTS 8'd10
`define RINGISA_MUL 8'd11
`define RINGISA_ADDI 8'd12
`define RINGISA_MOVI 8'd13
`define RINGISA_CHUNK 8'd14
`define RINGISA_VADD 8'd16
`define RINGISA_VSUB 8'd17
`define RINGISA_VAND 8'd18
`define RINGISA_VOR 8'd19
`define RINGISA_VXOR 8'd20
`define RINGISA_VMUL 8'd21
`define RINGISA_VEQ 8'd22
`define RINGISA_LD_U8 8'd32
`define RINGISA_LD_U16 8'd33
`define RINGISA_LD_U32 8'd34
`define RINGISA_LD_U64 8'd35
`define RINGISA_LD_U128 8'd36
`define RINGISA_LD_S8 8'd37
`define RINGISA_LD_S16 8'd38
`define RINGISA_LD_S32 8'd39
`define RINGISA_LD_S64 8'd40
`define RINGISA_LD_S128 8'd41
`define RINGISA_LD_256 8'd42
`define RINGISA_ST_8 8'd48
`define RINGISA_ST_16 8'd49
`define RINGISA_ST_32 8'd50
`define RINGISA_ST_64 8'd51
`define RINGISA_ST_128 8'd52
`define RINGISA_ST_256 8'd53
`define RINGISA_BEQ 8'd64
`define RINGISA_BNE 8'd65
`define RINGISA_BLTU 8'd66
`define RINGISA_BLTS 8'd67
`define RINGISA_JAL 8'd68
`define RINGISA_SVC 8'd80
`define RINGISA_BRK 8'd81
`define RINGISA_ERET 8'd82
`define RINGISA_WFI 8'd83
`define RINGISA_FENCE 8'd84
`define RINGISA_CSRR 8'd85
`define RINGISA_CSRW 8'd86
`define RINGISA_TLBI 8'd87
`endif
