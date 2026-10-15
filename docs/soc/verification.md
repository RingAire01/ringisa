# Phase 2 verification ledger

## Subsequent storage optimization

The next implementation checkpoint changes RAM/register/TLB/PWC storage without
changing ISA or cache replacement semantics. Current results and new scoreboards
are in [storage.md](storage.md); the remainder of this document preserves the
original Phase2 results, including its failed FPGA mapping experiment. Do not
apply the old synthesis cell count or exact cycle count to later revisions.

Starting revision `08066a00074a3508b5ba15c41ab1f596cebeeb42`, clean `main`,
origin `https://github.com/RingAire01/ringisa.git`. Original command
`python scripts/rtl.py --test --synth` returned exit0, all existing16 CPU
differential programs and26384 decode vectors passed; captured separately in
`target/phase2-baseline.log`. Prior reports were not treated as fresh evidence.

## Commands and scopes

```
python scripts/build.py --test --sanitize
python scripts/analyze.py
python scripts/soc.py --test
python scripts/soc.py --synth
python scripts/rtl.py --test --synth --soc
python scripts/fpga.py --map --peripherals
python scripts/fpga.py --map --pnr
```

Executed software checks:11176 architectural checks (direct link and archive),
180 independent Python ALU oracle cases,121 hostile input/publication cases,
allocation failure injection and invalid-spec fixtures. No ASan/UBSan findings.
Core ABI/ISA and original C source execution engine unchanged; generated ISA
opcode definitions have not been extended.

## New functional verification

- Eight actual RTL CPU boot programs including combined and high128-bit MMU
  fetch/data/fault return. Success requires executed register/RAM signatures,
  correct privilege, readback, exception state and peripheral effects.
- Combined run:33035 clocks,186 retired instructions,20 UART bytes (actual wire
  `RingISA SoC boot OK\n`), one timer interrupt, source/controller acknowledge,
  cleared trap-active state, ERET and resumed main success. Counts are simulation
  observations, not frequency or throughput claims.
- Independent C CPU replay of each program compares all64 GPRs,9 CSRs, full128
  PC and every observed RAM store byte at instruction retirement. Device read
  values and interrupt arrival are replayed observations; **not independent
  cycle-level peripheral modeling**. Device behavior is separately checked by
  waveform and protocol tests. No register result is injected into C.
- Bus seeded stress: deterministic seed0x52415849, AW/W independence, B/R stalls,
  217 checked transactions,
  random byte strobes against a separate byte-merge oracle, narrow lanes,
  ROM write rejection, unmapped high PA, invalid size/alignment/burst,
  unsupported burst draining/response beat counts, UART RX/TX/read-clear,
  timer/controller source/ack, illegal offsets, idle/queued/active resets.
- CPU adapter seed0x41584932:41 logical transactions, wide unaligned cross4KiB
  access, byte31 fault with no earlier changes, all five channel random delays,
  held master payload assertions, reset in each adapter phase.
- AXI-Lite direct slave:16 checks, reverse AW/W order, read while partial write
  queued, partial/zero strobes, held responses, invalid regions/offsets and four
  reset positions. None of these use an always-success fake peripheral.
- Four dedicated UART checks verify RX completion simultaneous with an empty
  RX read or consuming an older byte, unread-byte overrun and read-clear.
  New-byte publication wins over read-clear; no frame silently disappears.
- All eight C architecture replays also passed standalone ASan/UBSan execution.

## Synthesis / implementation distinction

Process synthesis and structural/latch assertions executed separately for CPU,
adapter, AXI router, peripherals, RAM and integrated SoC. Actual counts are
machine-readable in `target/soc-synthesis-summary.json`; final results below
supersede any earlier source checkpoint. RTLIL cells are not FPGA LUT counts.

ECP5 peripheral-only mapping completed. Full SoC mapping attempted with Yosys
`synth_ecp5`: failed in ABC9 XAIGER2 output with Windows status3221225725
(0xc00000fd, stack overflow). Netlist was not produced, so nextpnr placement/
routing/timing did not execute. Before failure the tool derived184743
TRELLIS_FF and204 MULT18X18D, plus very large distributed RAM. These are
intermediate mapping observations, not completed device utilization.
The85F device cannot accommodate that FF requirement. No supported larger
qualified local board/device combination is available; no fabricated Fmax.
Logs: `target/fpga-soc-mapping.log`, `target/fpga-peripherals-mapping.log`.

## Actual repairs and limitations

1. Combined boot initially enabled IRQ with a stale controller pending bit
   left by polling. Firmware now clears timer source then controller ACK.
2. First high128 invalid-leaf test read uninitialized RAM and got physical
   fault10 instead of invalid-PTE7. Boot now explicitly writes invalid PTE0;
   RAM reset-clearing was not fabricated to mask firmware initialization.
3. Original remote CI had Windows MS CRT ISO C deprecation errors. The build
   explicitly enables portable ISO C usage via `_CRT_SECURE_NO_WARNINGS`, with
   bounded parser and exclusive temporary-file publication unchanged. This
   compatibility exception does not disable compiler correctness diagnostics.
4. A120-second aggregate local synthesis attempt timed out; standalone
   synthesis rerun completed. Timeout was not recorded as a synthesis pass.
5. Final review found simultaneous UART read/completion could clear a newly
   received byte. Clear now precedes publication, and a read frees the existing
   slot for a new frame on that clock. Four directed regression checks pass.

No board execution, PNR/timing closure, power measurement, formal AXI proof,
arbitrary external slave atomicity, DDR or multi-master validation. Reset
aborts execution and may preserve partial RAM transfer bytes; it is not an
architectural exception. Malicious/broken master timeout recovery is not defined.
Remote CI status is recorded only after actual GitHub execution observation.

Observed GitHub run [38288535516](https://github.com/RingAire01/ringisa/actions/runs/38288535516)
for integration commit `ef7ad3e59790c63395eadd3cea844decf9caaa63`: **success**.
All five jobs passed: Windows/Linux clang/gcc software matrix and Linux
hardware/sanitizers/analysis/full core+SoC tests/synthesis/generated consistency.
This includes genuine remote Linux GNU GCC execution, not the local wrapper.
The later UART race fix is verified separately by local tests and its own CI;
the earlier green run does not claim coverage of that subsequent revision.

## Final local synthesis statistics

| Hierarchical top | Primitive RTLIL cells | Inferred memory bits |
|---|---:|---:|
| CPU AXI adapter |217|0|
| AXI router with initialized ROM and RAM |16777|1179648|
| Peripheral subsystem |292|0|
| Integrated initialized SoC |30911|1365760|

These counts include initialization/read/write RTLIL cells, not bit-level gates
or LUTs. All four process/check/latch assertions returned exit0. Peripheral-only
ECP5 mapping:632 LUT4,360 TRELLIS_FF,280 CCU2C,107 PFUMX,5 L6MUX21
(1387 cells including3 scope records), structural check0 problems. No PNR.
Full core26384 decode/16 differential regression rerun passed alongside SoC;
clang analysis covered10 C translation units, no diagnostics.

## Changed-boundary security review

Assets: precise CPU memory state, privilege/exception state and device side
effects. Trust boundary: translated CPU PA and AXI/Lite inputs entering mapped
slaves; boot image is trusted build input, not runtime guest-controlled host
filesystem access. Review traced full64-bit PA through preflight/router, byte
lane masks, unsupported burst draining, retained response ownership and reset.
Regression checks address overflow/unmapped ranges, readonly ROM, atomic fault
preflight, malformed protocols, invalid device accesses and bounded C trace
parsing (one million events,32 writes/instruction). C replay only accepts mapped
device/physical input ranges. No new HTTP/auth/deserialization service, shell
user input, credentials or external DMA privileged path was introduced.
Existing hostile assembler input and allocation-fault tests remain enabled.
Residual risks: untrusted master can stall by withholding beats, reset can leave
partial RAM bytes, ROM loading depends on trusted file provenance, no formal
proof or external fault rollback. These are explicit unsupported environments,
not hidden successful tests. No known high/critical defect in the verified
single-master integrated-platform scope; this is not a whole-repository audit.
