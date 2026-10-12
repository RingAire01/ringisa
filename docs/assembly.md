# Assembly syntax

Case-sensitive uppercase mnemonics. Registers R0–R63 (lowercase r accepted).
Comma/space separators; `;` or `#` starts a comment. Labels are alphanumeric
or underscore names followed by `:`, may precede an instruction on the line.
No macros, expressions, implicit data relocation or external symbol linker yet.

```
ADD.256 R3, R1, R2
SAR.8 R4, R3, R2
VADD.16 R5, R3, R4
MOVI R1, -512
ADDI R2, R1, 100000
LD.U128 R3, R2, -16
ST.256 R3, R2, 0
BEQ R1, R2, end
JAL R63, R0, function
JAL R0, R63, 0
CHUNK R7, 3, 0xffffffff
CONST128 R8, 0xffffffffffffffffffffffffffffffff
CONST256 R9, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
CSRW R8, 3
CSRR R9, 0
SVC 1
end: WFI
```

Scalar suffix defaults256, SIMD defaults64. Signed immediate -512..511 uses
32-bit encoding; larger values use64-bit, signed range -2^41..2^41-1. `.X`
suffix forces64-bit to preserve disassembly round trips even for small values.
Branches/JAL labels always use64-bit in the assembler for stable two-pass
layout; numeric operands are signed word displacements. No branch relaxation.
JAL label with B!=R0 is an explicit base-relative convention; the assembler
resolves labels PC-relative, so symbolic JAL should use B=R0.
Memory operands use `data_register, base_register, byte_offset`, not brackets.

CHUNK inserts unsigned32 into one of eight 32-bit chunks of its destination.
CONST256 emits eight CHUNKs; CONST128 emits four CHUNKs and preserves high128
of the destination (address calculations ignore those high bits). Both accept
unsigned hex/decimal, negative CONST256 encodes two's complement. CONST128
rejects negative values and values exceeding128 bits. No hidden scratch register.

`.word 0x12345678` emits any32-bit word, including illegal encodings. Disassembler
uses it for illegal or truncated instructions, permitting exact binary round
trips even for malformed input. Raw binaries must be a multiple of4 bytes.
Diagnostics include source line. Source/binary limit16 MiB, line4096 bytes,
131072 statements and4096 labels, physical simulator RAM at most16384 pages (64 MiB).
Outputs publish by exclusive temporary file, flush, atomic replace; failed
assembly leaves the prior output intact.
