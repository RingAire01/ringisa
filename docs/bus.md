# Physical memory fabric contract

The synthesizable core deliberately exposes a transactional gather/scatter bus
to preserve precise cross-page store exceptions. It is not AXI-compatible.
A platform adapter may serialize it to RAM/AXI only if it reserves/validates
all targets first and guarantees store completion without a later partial fault.

- `memory_request`: held until response, exactly one outstanding transaction.
- `memory_write`: store when1, read when0.
- `memory_enables[31:0]`: enabled byte indices.
- `memory_addresses[i*64 +:64]`: full physical address for byte i.
- `memory_write_data[i*8 +:8]`: byte i store data.
- `memory_response`: completion pulse; `memory_error` means **no effects**.
- `memory_fault_index[4:0]`: first enabled byte whose physical access failed.
- `memory_read_data[i*8 +:8]`: read byte i, sampled only on successful response.

Requests/data remain stable while waiting. A slave accepts once, performs all
validation before reads with side effects or any write, then responds once.
It must not repeat effects each cycle the request stays high. Timeout/retry
policy belongs to the platform; current core stalls until a response or reset.
Walks read sixteen contiguous bytes using the same bus, never write PTEs.
Maximum physical table read cannot wrap because tables are 4 KiB aligned.

Reset cancels outstanding internal work; platform reset must also cancel bus
transactions. The verification memory fabric implements bounded sparse-backed
RAM (via an image array), transactional fault checks and exactly-once responses.
Peripheral integration, AXI adapter, CDC and asynchronous reset strategy remain
platform-specific work; this interface is not a claim of a complete mobile SoC.

`rtl/memory/ram_fabric.sv` provides a concrete single-port byte RAM realization
for on-chip use, with configurable64-bit physical BASE and window size. It
validates all addresses, then serially transfers bytes without any subsequent
fault point. No other master observes a partial transfer. Loader writes are
accepted only while idle and never during a transaction; integrate loader access
as a trusted pre-boot capability. RAM content is not cleared on reset and must
be initialized by the loader before release. `ram_tb` tests a window ending at
physical `0xffffffffffffffff`, including failed-store atomicity.
