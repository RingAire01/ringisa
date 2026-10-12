# Compiler and platform integration contract

RingISA is standalone; existing `RingEcho-Lang-C` and `rnu` are unchanged.
The software library is under `tools/common` and `tools/simulator`. A C caller
includes `ringisa.h`, initializes one `ri_cpu`, maps physical pages with
`ri_memory_map`, writes program/table bytes using `ri_phys_write`, sets PC and
initial CSRs, calls `ri_step`, and finally `ri_cpu_destroy`. Library state is
explicit and thread-affine. `ri_alu`/`ri_simd` return false for invalid widths,
operations or null result, preserving the caller's result on failure.
Encoding helpers return the reserved word0 when fields, opcode, immediate range
or canonical instruction constraints are invalid; callers must reject that
sentinel rather than emit it unintentionally. Decode never changes its output
on failure. Raw `.word` assembly remains an intentional way to emit illegal words.

REO integration point identified in the sibling repository:

1. Add a RingISA native target descriptor and target layout (pointer16 bytes,
   256-bit full register capacity, little-endian). Pointer size is not register
   size; do not collapse either to the host pointer width.
2. Lower typed IR to scalar widths and lane operations according to v0.1.
3. Materialize addresses through CHUNK; encode R fields with6-bit registers;
   honor R63/R62 ABI and32-byte stack alignment. Implement actual spilling,
   liveness and argument handling rather than legacy circular allocation.
4. Initially emit flat binaries compatible with this assembler/simulator. A
   linker and independently assigned object-machine identifier must be designed
   before adding ELF artifacts; do not reuse EM_ARM/EM_RISCV to impersonate them.
5. Qualify emitted code against the reference simulator and RTL. Port rnu's
   hardware-dependent boot/interrupt/I/O layer separately; x86 Multiboot/PIC
   assembly is not portable to RingISA.

This document is an integration interface, not a claim that compiler lowering
or a kernel port has been implemented. No REO source modifications are needed
to build or execute the RingISA initial release.
