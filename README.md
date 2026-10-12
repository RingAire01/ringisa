# RingISA

Original hardware-oriented Load/Store RISC architecture under RingAire.
64 architectural 256-bit registers, scalar 8–256-bit arithmetic, 256-bit SIMD,
native unsigned **128-bit virtual addresses and PC**, 64-bit physical addresses,
15-level page tables with 128-bit PTEs, U/S/M privilege, mixed 32/64-bit instructions.

This is a correctness-first, single-core multicycle reference implementation.
It is **not** a fabricated mobile-performance or silicon-readiness claim.
No ARM/RISC-V compatibility layer is used.

## Build software

Requires Python 3.10+ and a C11 compiler (`clang` by default, override `CC`).
No external C libraries. On Windows append `.exe` to tool paths.
When `llvm-ar` or `ar` is available (override `AR`), the build also produces
`target/libringisa.a` for embedding the reference machine in C applications.

```sh
python scripts/build.py --test
target/ringisa-as examples/arithmetic.s target/arithmetic.bin
target/ringisa-dis target/arithmetic.bin
target/ringisa-sim target/arithmetic.bin --trace --inspect --steps 100000
target/ringisa-sim target/arithmetic.bin --debug
```

Simulator exits successfully on WFI, unsuccessfully on a trap or step-limit
exhaustion. The library continues trap-handler execution when callers use
`ri_step`; the CLI deliberately stops on a trap for inspection. `--steps 1`
performs one instruction attempt and `--inspect` dumps all registers and the
first 32 bytes of physical memory. CLI currently loads identity/bare code at
physical/virtual zero by default. `--pc U128 --satp U64 --asid U16 --priv U|S|M
--tvec U128` configures native address-space execution from a physical memory
image. `--handle-traps` continues into guest trap handlers rather than stopping.
`--debug` provides `step`, `run`, `regs`, `csr`, `pc`, `mem VA N`, `pmem PA N`
and `quit`; reads are bounded to32 bytes and execution shares a total step budget.

## Phase 2: minimal SoC

`rtl/soc/soc.sv` integrates the original CPU/MMU,64-bit-address32-bit-data AXI
adapter/router,16 KiB boot ROM,128 KiB transactional RAM, AXI-Lite UART (8N1
TX/RX), timer and interrupt controller. Eight bare-metal programs execute on
the real RTL CPU, including native128-bit paged execution and fault return.

```sh
python scripts/build.py --test
python scripts/boot.py
python scripts/soc.py --test --synth
python scripts/rtl.py --test --synth --soc
```

The combined acceptance test independently receives `RingISA SoC boot OK\n`
from the UART wire, checks RAM, timer interrupt entry/ack/ERET, privilege and
the executed success signature. C architecture replay compares all73 GPR/CSR
values and PC using observed peripheral inputs/IRQ events, not a duplicated
cycle-level device model. Protocol tests separately verify side effects and
handshakes. See [SoC architecture](docs/soc/architecture.md), [verification](docs/soc/verification.md),
[AXI contract](docs/soc/axi.md) and [FPGA scope](docs/soc/fpga.md).

No hardware deployment, arbitrary external-slave atomicity or mobile PPA is
implied. Internal storage/multipliers remain large; FPGA feasibility results
are reported separately from successful simulation/process synthesis.

## Reference core RTL

SystemVerilog modules are under `rtl/`. `ringisa_core` exposes an atomic physical
gather/scatter memory interface, debug register read port, retire/trap signals,
128-bit reset PC and interrupt inputs. See [bus contract](docs/bus.md).
The memory fabric is responsible for validating all bytes before any store.

```sh
python scripts/rtl.py --test
python scripts/rtl.py --synth
python scripts/rtl.py --gates
```

Requires Icarus Verilog and Yosys (native or YoWASP). Tool discovery and override
variables are documented in the script. RTL verification results and exact
scope are recorded in [verification](docs/verification.md), not assumed here.

## Architecture and tooling

- [Architecture](docs/architecture.md), [generated instructions](docs/instructions.md)
- [Assembly syntax](docs/assembly.md), [decisions](docs/decisions.md)
- [Roadmap](docs/roadmap.md), [progress](docs/progress.md)
- [Known issues](docs/known-issues.md), [verification](docs/verification.md)
- `spec/isa.json`: authoritative encoding, opcode table and instruction semantics.
- `tools/specgen`: validates collisions and generates C/SV metadata and reference.
- `tools/assembler`, `tools/disassembler`, `tools/simulator`: C tools.
- `tests`: C architectural regression, Python independent oracle, RTL differential tests.

Do not execute untrusted guest programs without a host process sandbox. Physical
RAM and instruction counts are bounded; this library is not a security sandbox.

## License

MIT, copyright RingAire. Downloaded build tools under ignored `target/` retain
their own licenses and are not part of this project's source distribution.
