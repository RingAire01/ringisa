# Progress checkpoint

## Storage implementation checkpoint (2026-10-15)

RAM now uses a synchronous read register and single loader/store write port;
register-file reset uses per-word validity; TLB/PWC keep original full match
and round-robin semantics but read selected payloads via indexed memories.
ISA widths, encodings and exception behavior are unchanged. New scoreboards:
5056 register port checks,714000 TLB/PWC checks and1301 RAM transactions.
Original core16-program differential and eight SoC program/C replays pass;
combined33075 cycles/186 retired/20 UART bytes/one timer interrupt. Software
sanitizer regression and10-unit static analysis pass. SoC process synthesis:
28411 RTLIL primitive cells,1366368 memory bits, no structural/latch failures.
Standalone128 KiB RAM full ECP5 mapping uses64 DP16KD blocks; register file
uses1024 distributed primitives and64 FF. Complete ABC9 retry still fails with
Windows stack overflow, but intermediate FF drops184743->129128. This is not
a completed physical implementation. Reproduce with `scripts/storage.py` and
read `docs/soc/storage.md` for current scope and further mapping results.

Remaining tasks: large CAM tags/arithmetic resource demand, suitable device,
measured timing/PNR and actual board integration; no PPA or hardware success.

## Phase 2 checkpoint (2026-10-13)

Implemented complete single-master SoC under `rtl/soc`: CPU AXI adapter,
address router, boot ROM, existing transactional RAM, AXI-Lite bridge/peripherals,
8N1 UART TX/RX, timer, interrupt controller and generic FPGA wrapper. Original
CPU, ISA, MMU and C execution semantics retained. Eight RTL boot programs and
C architecture/RAM-write replays pass, including combined acceptance and full
128-bit paged execution/fault return. Bus217 transactions, adapter41 logical
transactions, direct AXI-Lite16 checks pass. Software sanitizer regression and
10-unit clang analysis pass. Four SoC process synthesis targets pass; integrated
30911 RTLIL cells/1365760 memory bits, not FPGA LUTs. Peripheral ECP5 mapping
passes; complete mapping fails in ABC9 with Windows stack overflow, intermediate
184743 FF exceeds85F capacity. No PNR, timing, hardware or power claim.

Reproduce: `python scripts/build.py --test --sanitize`,
`python scripts/analyze.py`, `python scripts/rtl.py --test --synth --soc`.
Read `docs/soc/verification.md` and `docs/soc/fpga.md` for actual results and
limitations. Next phase: verified storage/ALU optimization or suitable larger
FPGA tooling, real board constraints and physical bring-up. Not authorized here.

## Phase 1 historical checkpoint

Repository: `RingAire/ringisa`, branch `main`, initial standalone project.

Implemented:51-opcode authoritative specification with generated C/SV tables,
C assembler/disassembler/simulator/static library/debugger,64x256 GPRs, scalar
and SIMD execution, full128-bit addressing/PC, sparse64-bit physical RAM,
15-level MMU with128-bit PTEs, ITLB/DTLB/L2/PWC, U/S/M/CSRs/traps/interrupts,
integrated multicycle CPU RTL and concrete synthesizable transactional RAM.

Executed final functional checkpoint:11176 C checks, library link regression,
180 independent scalar oracle cases,121 hostile-input cases, allocation failure
injection,26384 C/RTL decode vectors,16 full core differential programs, MMU,
address generator and RAM directed RTL tests. ASan/UBSan passes; static analysis
has no diagnostics. Core and RAM process synthesis/check passes. Current-source
generic gate synthesis replay after the negative-offset fix passed:912445
generic one-bit cells, no remaining memories/processes, zero structural problems
and no latches. No technology mapping, timing closure or physical PPA is claimed.

Implementation checkpoint revision: `7b9905b7cc951636ef875981fca0045ea14cdc71`.
The subsequent verification-ledger commit records the final replay results.

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
