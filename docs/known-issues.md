# Known issues and release limitations

- Current-source generic gate synthesis, process synthesis and directed/
  differential RTL tests have passed after the negative-offset fix.
- No PPA qualification, timing closure, FPGA board bring-up or silicon evidence.
- Phase2 provides an AXI adapter and complete on-chip SoC. Architectural
  all-or-none stores require the documented integrated single-master fabric;
  arbitrary independently faulting external AXI slaves are not transactional.
- Single core only; no atomics/SMP shootdown/cache coherency, floating point,
  page-size extensions or exception delegation in base v0.1.
- CLI supports physical memory images/high reset addresses, interactive stepping,
  registers, CSR and virtual/physical memory inspection; no source-level debugger.
- Assembler emits flat binaries, no ELF linking/debug info/external relocations.
- No REO compiler target adapter installed; other RingAire projects unchanged.
- Mobile power/performance objectives are design goals, not validated metrics.
- Large combinational multipliers and fully associative TLB storage dominate
  area; current generic synthesis contains912445 one-bit cells. Do not
  equate that number with ASIC area, FPGA LUT count or a mobile-ready design.
- Local `gcc` is LLVM's clang wrapper, not independently tested GNU GCC.
  Actual Phase2 remote CI execution status is in `docs/soc/verification.md`.
  Formal proof, broad fault injection and technology-specific timing are not
  complete. ECP5 peripheral mapping passes; full SoC mapping failed in ABC9
  with stack overflow after deriving FF demand above85F capacity. No PNR.
