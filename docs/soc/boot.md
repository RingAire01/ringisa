# Bare-metal boot and programs

```
python scripts/build.py --test
python scripts/boot.py
python scripts/soc.py --test
python scripts/rtl.py --test --synth --soc
```

Assembler is unchanged. Scripts generate meaningful source under `examples/soc`
and binary/hex images under ignored `target/soc`. Program at physical0, machine
handler at0x1000, paged payload (MMU tests only) at0x2000. Numeric trap vector
and padding are image layout, not new instructions or object formats. Sources
use the existing64-bit immediate, CHUNK pointer construction and ABI R62 stack.
Stack starts at RAM end0x30000,32-byte aligned. No implicit C runtime or REO port.

Eight independently executed programs:

1. rom_boot: reset fetch, stack/address initialization, CPU/RAM success signature.
2. ram_test:32-bit store/read compare and256-bit unaligned cross4KiB transfer.
3. uart_test: poll ready, emit `RingISA SoC boot OK\n`, wait for serial completion.
4. timer_poll: compare programming, cycle counter event, source/controller ack.
5. timer_interrupt: TVEC/IE/STATUS setup, timer trap, handler, ERET and cause check.
6. combined: all preceding interactions in order, one timer interrupt and return.
7. high128_mmu: boot creates15-level tables in RAM, enters S at
   `0xffff0123456789ab0000000000000000`, fetches ROM via native128 VA,
   accesses translated RAM and leaves success signature at physical0x20020.
8. high128_fault: additionally touches an explicitly invalid third leaf, verifies
   cause7, full128 EPC return advancement and resumed S execution.

Success R60=0x600d and RAM signature at0x10020 (paged tests0x20020), then WFI.
Failure branch writes0xffffffff and sleeps; bench rejects it. Programs are
not intended as production firmware. Simulation uses divisor4 to minimize
execution time; adapt divisor to the actual hardware clock for115200 baud.
ROM can be replaced via the top's initialization parameter. Boot image address
map is from `spec/soc.json`; fixed demonstration virtual addresses are test data.
