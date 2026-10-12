# Progress checkpoint

Repository: `RingAire/ringisa`, branch `main`, initial standalone project.

Implemented:51-opcode authoritative specification with generated C/SV tables,
C assembler/disassembler/simulator/static library/debugger,64x256 GPRs, scalar
and SIMD execution, full128-bit addressing/PC, sparse64-bit physical RAM,
15-level MMU with128-bit PTEs, ITLB/DTLB/L2/PWC, U/S/M/CSRs/traps/interrupts,
integrated multicycle CPU RTL and concrete synthesizable transactional RAM.

Executed final functional checkpoint:11171 C checks, library link regression,
180 independent scalar oracle cases,121 hostile-input cases, allocation failure
injection,26384 C/RTL decode vectors,16 full core differential programs, MMU,
address generator and RAM directed RTL tests. ASan/UBSan passes; static analysis
has no diagnostics. Core and RAM process synthesis/check passes. An earlier
generic gate synthesis passed; it predates the discovered negative-offset fix
and is not final-source evidence. Current-source gate replay is pending.

Resume verification:

```
python scripts/build.py --test --sanitize
python scripts/analyze.py
python scripts/rtl.py --test --synth
python scripts/rtl.py --gates
```

Read `docs/verification.md` before claiming any result. Next product work:
technology/FPGA target selection, memory adapter/boot integration and measured
PPA; replace large fully associative translation arrays and combinational
multipliers only with differential regression preservation. REO integration
contract is in `docs/integration.md`; no sibling repositories were changed.
