# RingISA minimal SoC

The unchanged `ringisa_core` is the only execution engine. Its MMU translates
full128-bit guest addresses into64-bit physical byte addresses, before any
AXI transport. ISA opcodes,64x256-bit GPRs, traps and U/S/M semantics are unchanged.

```
core + MMU -> transactional gather/scatter -> CPU AXI adapter
  -> single-master AXI4 address router -> ROM / transactional RAM
                                      -> AXI-Lite bridge -> UART / timer / IRQ
```

`ringisa_soc` is the reusable top, synchronous active-high reset, defaults50 MHz.
UART RX and external IRQ are internally two-flop synchronized. UART TX is8N1.
Debug port reads one GPR, plus full128-bit PC, privilege, retirement, sleeping
and trap outputs. UART event instrumentation is optional observation, not how
the acceptance test establishes serial output. All blocks share one clock.

`ringisa_soc_fpga` removes wide debug outputs from pins and synchronizes an
active-high reset request over two clock edges. It uses FPGA initialization for
reset synchronizers and ROM. Hold reset for at least two rising edges; RAM is
not reset-cleared. No board pins, PLL, clock constraints or physical certification
are implied. The generic clock parameter changes the default UART divisor;
the timer counts clock edges, not host time. Example test firmware overrides
UART divisor to4 for fast simulation (not a115200-baud hardware demo).

64-bit AXI address,32-bit AXI data and32-bit AXI-Lite registers. No address
truncation, caches, speculation, DMA, second master, exclusive transactions,
reordering, coherence or external DRAM. Boot ROM16 KiB, on-chip RAM128 KiB.
Unknown physical ranges return errors. Region definitions are authoritative
in `spec/soc.json`; `tools/specgen/soc.py` validates non-overlap and generates
`rtl/soc/map.svh` and the address reference.

Current endpoint is a restricted serialized AXI implementation, not a universal
AXI fabric. Only the trusted integrated RAM/ROM/peripherals uphold the CPU
all-or-none fault guarantee; read `axi.md` and `memory.md` before attaching
an independently faulting external slave.
