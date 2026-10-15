# FPGA readiness and timing scope

The subsequent [storage optimization](storage.md) adds measured standalone
BRAM/LUTRAM mapping, a classic-ABC fallback, new regression tests and a full
SoC mapping retry. Counts and failures below describe the original Phase2
checkpoint unless explicitly superseded in that document.

Local portable OSS CAD Suite provides Yosys, nextpnr-ecp5/ice40/nexus/himbaechel,
Trellis databases and supporting tools. No physical FPGA board is connected.
Only an open ECP5 device feasibility flow is supplied; no tiny iCE40 chosen to
pretend the CPU fits. Exact experiment: LFE5U-85F, CABGA381, speed6, requested
25 MHz; `fpga/ecp5/target.json`. No pin map or board constraint is invented.

```
python scripts/boot.py
python scripts/fpga.py --map --peripherals
python scripts/fpga.py --map --pnr
python scripts/fpga.py --map --pnr --lut-mapper abc
```

Full mapping/PNR results must be read from the verification ledger. Pinless
`--lpf-allow-unconstrained` is feasibility only and cannot create a deployable
board image. No fabricated LUT/BRAM, achieved Fmax, power or timing-closure
numbers. Generic CPU cell count912445 is **not FPGA LUT count**.

Structural timing risks (not measured critical paths):256-bit combinational
multiply/add/shifts, parallel SIMD multipliers and selection, asynchronous large
register-file muxes, full116-bit associative TLB tags (512 L2 entries), CSR/read
and decode muxes. Transport uses registered state machines and one backend
owner; buffering eliminates combinational READY cycles across AW/W/B/AR/R.
RAM implementation validates/transfers serially, keeping transaction latency
high but separating address checks from writes. CPU byte decomposition makes
fetch and wide-memory execution slow; cycles are not performance qualification.

Fully associative TLB tags still map to a very large number of FFs even after
the storage refactor; process synthesis and even generic gates do not establish any
ECP5 resource fit. A larger suitable device/toolchain or verified internal
storage/ALU optimizations will likely be necessary. ISA width/address changes
are not an acceptable fitting shortcut. Next milestone requires selecting a
real board, pin/clock constraints, complete PNR, measured timing and hardware
UART/interrupt bring-up. Power needs a separate measured/characterized flow.
