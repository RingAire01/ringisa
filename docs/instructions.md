# Generated instruction reference

Source: `spec/isa.json`. Do not edit this table manually.

| OP | Mnemonic | Format | Exact behavior |
|---|---|---|---|
| 0x01 | ADD | R | Rd = zero_extend((Rs1 + Rs2) modulo 2^width) |
| 0x02 | SUB | R | Rd = zero_extend((Rs1 - Rs2) modulo 2^width) |
| 0x03 | AND | R | Rd = zero_extend(low_width(Rs1 AND Rs2)) |
| 0x04 | OR | R | Rd = zero_extend(low_width(Rs1 OR Rs2)) |
| 0x05 | XOR | R | Rd = zero_extend(low_width(Rs1 XOR Rs2)) |
| 0x06 | SHL | R | Rd = zero_extend(low_width(Rs1 << (Rs2 modulo width))) |
| 0x07 | SHR | R | Rd = zero_extend(unsigned low_width(Rs1) >> (Rs2 modulo width)) |
| 0x08 | SAR | R | Rd = sign_extend(signed low_width(Rs1) >> (Rs2 modulo width)) |
| 0x09 | SLTU | R | Rd = unsigned low_width(Rs1) < unsigned low_width(Rs2) ? 1 : 0 |
| 0x0a | SLTS | R | Rd = signed low_width(Rs1) < signed low_width(Rs2) ? 1 : 0 |
| 0x0b | MUL | R | Rd = zero_extend((low_width(Rs1) * low_width(Rs2)) modulo 2^width) |
| 0x0c | ADDI | I | Rd = (Rs1 + sign_extend(immediate)) modulo 2^256 |
| 0x0d | MOVI | I | Rd = sign_extend(immediate); B must be zero |
| 0x0e | CHUNK | X | Rd[32*index +: 32] = W1, other bits unchanged; A=Rd, B=0, PAYLOAD=index 0..7, L=1; W1 is unsigned data, not an immediate extension |
| 0x10 | VADD | R | Each lane = (left lane + right lane) modulo 2^lane_width |
| 0x11 | VSUB | R | Each lane = (left lane - right lane) modulo 2^lane_width |
| 0x12 | VAND | R | Each lane = left lane AND right lane |
| 0x13 | VOR | R | Each lane = left lane OR right lane |
| 0x14 | VXOR | R | Each lane = left lane XOR right lane |
| 0x15 | VMUL | R | Each lane = low_lane_width(left lane * right lane) |
| 0x16 | VEQ | R | Each lane = all ones if equal, else zero |
| 0x20 | LD.U8 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x21 | LD.U16 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x22 | LD.U32 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x23 | LD.U64 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x24 | LD.U128 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x25 | LD.S8 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x26 | LD.S16 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x27 | LD.S32 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x28 | LD.S64 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x29 | LD.S128 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x2a | LD.256 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); read width/8 bytes little-endian; replace R[A], sign extend iff signed else zero extend; no register update on any fault |
| 0x30 | ST.8 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x31 | ST.16 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x32 | ST.32 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x33 | ST.64 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x34 | ST.128 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x35 | ST.256 | I | EA = checked_unsigned128(R[B][127:0] + signed byte offset); write low width bits of R[A] little-endian; validate whole transaction before first side effect |
| 0x40 | BEQ | I | If full256 R[A] == R[B], PC = checked(PC + signed immediate*4), else sequential PC |
| 0x41 | BNE | I | If full256 R[A] != R[B], PC = checked(PC + signed immediate*4), else sequential PC |
| 0x42 | BLTU | I | If unsigned256 R[A] < R[B], PC = checked(PC + signed immediate*4), else sequential PC |
| 0x43 | BLTS | I | If signed256 R[A] < R[B], PC = checked(PC + signed immediate*4), else sequential PC |
| 0x44 | JAL | I | Base = PC if B=0, otherwise R[B][127:0]; checked target = base + signed immediate*4; R[A] = zero_extend(sequential PC); PC = target; unaligned target faults before link write |
| 0x50 | SVC | I | A=B=0; nonnegative immediate becomes TVAL; synchronous cause 11 trap to M |
| 0x51 | BRK | I | A=B=0; nonnegative immediate becomes TVAL; synchronous cause 12 trap to M |
| 0x52 | ERET | I | 32-bit, A=B=PAYLOAD=0; M with active trap only; PC=EPC; privilege=STATUS[2:1]; IE=STATUS[3]; clear STATUS[4:1] |
| 0x53 | WFI | I | 32-bit, A=B=PAYLOAD=0; S/M only; retire then wait for enabled interrupt |
| 0x54 | FENCE | I | 32-bit, A=B=PAYLOAD=0; all privileges; serialize preceding and succeeding data/device transactions |
| 0x55 | CSRR | I | 32-bit; A=destination, B=0, PAYLOAD=CSR index 0..8; M only; copy CSR to register |
| 0x56 | CSRW | I | 32-bit; A=0, B=source, PAYLOAD=CSR index 0..8; M only; validate reserved bits then write atomically |
| 0x57 | TLBI | I | 32-bit, A=B=PAYLOAD=0; S/M only; invalidate local ITLB, DTLB, L2 and walk cache; serialized |
