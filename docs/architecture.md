# RingISA architecture v0.1

The opcode and instruction behavior source is `spec/isa.json`; the generated
reference is `instructions.md`. This document specifies shared architectural
state, translation and exception behavior. Unknown opcodes and noncanonical
encodings trap; they are not NOPs. Division, floating point, atomics, huge pages,
and multiple cores are not part of v0.1's base instruction set.

## Registers and ABI

64 registers R0–R63, each 256 bits. R0 always reads zero, writes discard data;
loads into R0 still perform the access and can fault. Scalar FUNC codes 0–5
select 8,16,32,64,128,256 bits; SIMD FUNC 0–3 select 8,16,32,64-bit lanes.
Unused FUNC values are illegal. Narrow arithmetic uses only low-width input
bits, wraps at that width and zero extends. SAR sign extends. Comparisons
produce 0 or 1. Shifts reduce counts modulo operand width. SIMD arithmetic
wraps per lane without cross-lane carry. No condition-code flags exist.

ABI: R63=link, R62=stack, R61=frame pointer (conventions, not hardware magic).
R1–R8 pass arguments; R1–R2 return values, including pointers in low 128 bits.
R1–R31,R63 caller saved; R32–R62 callee saved. Stack descends, alignment 32
bytes at call boundaries. Aggregates use memory; large return uses hidden R1
pointer and shifts arguments one register. Variadic/foreign-language ABI is not
qualified. Traps preserve every GPR; handlers save registers they modify.
Nested handlers must save CSRs explicitly; there is one M trap frame, no hidden
frame stack. Trap entry never requires an implicit memory write.

## Encoding and PC

W0 OP[31:24], A[23:18], B[17:12], PAYLOAD[11:2], L[1:0]. L=0 means 4
bytes; L=1 means 8 bytes, W1 follows little-endian; L=2/3 illegal. Alignment
4 bytes. R format PAYLOAD=C[11:6],FUNC[5:2], L=0. All I-format instructions
allow signed IMM10 or signed IMM42 when L=1, **except** the explicitly
32-bit-only system instructions. X in the table denotes CHUNK's mandatory
extension and distinct unsigned W1 semantics. Opcode reservations are permanent
illegal encodings until a later version defines them.

PC is unsigned128, not a host pointer or canonical 48-bit address. Sequential
PC addition is checked before effects, including a taken jump: overflow traps.
Branches compare 256-bit registers and use word displacement relative to the
current PC, not the following instruction. JAL uses PC when B=R0, otherwise
R[B].low128. Faulting branches do not update link registers. All address values
are legal to translate; a misaligned PC faults on instruction fetch.

## Memory

VA=unsigned128, PA=unsigned64, little-endian, sparse physical memory permitted.
EA=checked VA base.low128 + signed byte displacement, no wrap. Ordinary RAM
allows unaligned and cross-page operations of up to 32 bytes. Translate/check
all bytes before changing registers or store-visible memory. On a failing
byte TVAL reports that byte VA; EA arithmetic overflow reports the base VA,
cross-access overflow reports initial EA. No partial store is permitted.
Unmapped physical memory and read-only store target generate physical faults.

Single-core reference ordering is strongly ordered: one outstanding transaction,
instruction-order visible stores, no speculative device reads. FENCE serializes
transactions. Device pages (ATTR=1) require natural alignment and a single page;
all checks precede bus side effects. Hardware fabrics must implement the atomic
bus contract and access protection; emulated physical device pages are backing
RAM, not host I/O callbacks. No universal external peripheral map is prescribed.

## 15-level MMU

SATP bit0 enables paging in U/S; M bypasses paging. Bare addresses with high64
nonzero fault physically, not via truncation. SATP[63:12]=physical root PPN,
SATP[11:1]=0, high192=0. ASID is a separate 16-bit CSR. The root is a 4 KiB
allocation with only its first 16 entries addressable.

VA[127:12] is the full 116-bit VPN. L14 index VA[127:124]; for levels
13 down to 0, index=VA[12+8*level +:8]. L0 is VA[19:12]. Page offset
VA[11:0]. There are exactly 15 table accesses on an uncached successful walk.
Each PTE is 16 bytes, aligned, little-endian:

| Bits | Meaning |
|---|---|
| 11:0 | flags |
| 27:12 | ATTR: 0 normal RAM, 1 device; other values illegal |
| 43:28 | SW: ignored, software available |
| 95:44 | PPN: 52-bit physical page number |
| 127:96 | reserved, must be zero |

Flags bit0 V, bit1 T (table, else leaf), bit2 R, bit3 W, bit4 X, bit5 U,
bit6 G, bit7 A, bit8 D; bits9–11 reserved. W without R is reserved.
Table PTEs allow V,T,G,SW,PPN only; ATTR and R/W/X/U/A/D must be zero.
T at L0 faults; leaf above L0 faults (no large pages yet). G propagates from
ancestors to leaf. U accesses only U leaves; S accesses only non-U leaves.
Read/write/execute permissions are distinct. There is no implicit SUM or MXR.
**Software-managed A/D**: A=0 or write with D=0 is permission cause9; a handler
sets bits and executes FENCE then TLBI. Walkers never mutate page tables.

Fault priority: physical read failure; reserved high32; V=0; invalid flags/ATTR;
invalid table/leaf placement; privilege/access/A/D permission. TVAL is the
original translating byte VA for walker faults, not the physical PTE address.

ITLB32, DTLB64, L2TLB512, table walk cache32 by default. TLB tags use all116
VPN bits plus root and ASID; global entries ignore ASID but retain root.
Round-robin replacement. Walk-cache tags are physical PTE address+root+ASID.
OS must stop affected accesses, publish PTE changes, FENCE, TLBI, then resume.
SATP/ASID writes don't implicitly flush. TLBI invalidates all four caches on
this single core; no remote shootdown is defined yet. Cache policy does not
change architectural results when software obeys synchronization rules.

## CSR and privilege

U=0, S=1, M=2. All traps enter M, vector to TVEC directly. No delegation.
CSRR/CSRW are M-only; SVC/BRK/FENCE any privilege; WFI/TLBI S or M;
ERET only M with STATUS trap-active bit set. CSR values are 256-bit containers:

| Index | CSR | Legal bits |
|---|---|---|
| 0 | EPC | low128 PC, aligned4 |
| 1 | CAUSE | low64, fault number |
| 2 | TVAL | full low128 fault value/address |
| 3 | TVEC | low128 PC, aligned4 |
| 4 | STATUS | bit0 IE, bits2:1 previous privilege, bit3 previous IE, bit4 trap-active |
| 5 | SATP | low64 as above |
| 6 | ASID | low16 |
| 7 | IE | low64 interrupt enable mask |
| 8 | IP | low64 pending mask; RTL ORs external interrupt lines |

All unspecified bits must be zero on writes. Previous privilege3 is illegal.
Trap: EPC=faulting PC (interrupt: next instruction PC), CAUSE=cause,
TVAL=value; save privilege/IE; IE=0, trap-active=1, privilege=M; PC=TVEC.
ERET restores PC/privilege/IE and clears saved/active status bits. General
registers remain unchanged. WFI retires then sleeps; an enabled pending
interrupt wakes it. Interrupts are sampled only at instruction boundaries;
CAUSE14, TVAL0, IP identifies sources. Handlers acknowledge by platform policy.

Causes: 1 illegal, 2 fetch-class reserved, 3 load-class reserved, 4 store-class
reserved, 5 address overflow, 6 alignment, 7 invalid PTE, 8 reserved PTE,
9 permission/A/D, 10 physical access (including walker), 11 SVC, 12 BRK,
13 privilege violation, 14 interrupt. Causes2–4 are reserved for future summary
fault modes: current accesses report detailed7–10 for all access kinds.
Illegal instruction TVAL=W0 zero-extended. Illegal CSR value reports W0.
