# AXI transport contract

## Supported subset

- Single requester and one backend owner;64-bit PA,32-bit data, no transaction
  IDs (a fixed zero ID can be supplied by a platform wrapper).
- AW and W buffered independently, W-before-AW and AW-before-W both supported.
  AR has a separate one-entry buffer. Completed writes take arbitration priority
  over queued reads; no new backend execution before prior response consumption.
- All five channels use VALID/READY. B/R responses and payloads are held until
  accepted. Master VALID and payloads do not depend on READY. Reset cancels
  channel buffers and outstanding activity across all blocks.
- Successful transfers use LEN=0, BURST=INCR, SIZE=0/1/2 (byte/halfword/word)
  naturally aligned to size. WSTRB must be a subset of the addressed beat lanes.
  Narrow read bytes are in their original32-bit lane positions. WLAST required.
- OKAY=0; SLVERR=2 for ROM writes, unsupported transfer formats, malformed strobes,
  misalignment or invalid peripheral operation; DECERR=3 for unmapped address.
- Data bursts are not supported. LEN>0 writes are drained for LEN+1 beats,
  produce one SLVERR without effects. LEN>0 reads return LEN+1 SLVERR beats with
  RLAST only on the final beat. Invalid WLAST on a LEN=0 request is SLVERR.
  Masters must still obey the advertised beat count; no recovery for a master
  that abandons a write burst or never supplies missing W beats is promised.
- Optional cache/protection/QoS/lock/region sidebands are not exposed. Platform
  wrappers must use nonexclusive, noncached, privileged normal fixed values;
  this is not a complete AXI4 conformance certification.

## CPU adapter

The CPU submits up to32 independently translated byte addresses. Adapter first
scans every enabled byte. Writes must all target RAM or exactly one aligned
four-byte peripheral register. ROM writes/unknown addresses/unsupported device
widths fail before an AXI side effect. The first failing byte index is returned
to LSU for full128-bit TVAL reconstruction. MMU faults happen before the adapter.

RAM/ROM are serialized into single-byte AXI beats; arbitrary unaligned and
cross-page ISA accesses are supported after translation. MMIO is one32-bit
aligned transfer; use LD.U32/ST.32. A narrower/larger MMIO access is a physical
bus fault, not an ISA redefinition. The adapter holds the CPU completion until
the request drops. FENCE ordering follows the core's single outstanding request.

Integrated RAM cannot fault after validated address/permissions; only one master
can observe it. Thus a wide store is all-or-none with respect to architectural
faults/observers in this platform, **not globally atomic AXI multi-beat access**.
External slaves that can fail later beats, concurrent DMA and transactional
device groups require reservation/commit or a new fabric design before use.
Unexpected B/R errors propagate; they cannot roll back arbitrary external I/O.
Reset during a committed transfer may leave earlier RAM bytes written and
aborts CPU execution; reset is not a resumable precise architectural exception.

## AXI-Lite

Bridge serializes the owned backend transaction, with independent AW/W handshakes
and retained AR until READY. Peripheral bank accepts independently buffered
AW/W, allows reads while a write is only partially queued, and retains B/R under
backpressure. Side effects occur once when the complete access is accepted,
not when a response is repeatedly observed. Invalid register/width operations
do not produce successful responses or side effects. No timeout/retry policy:
an unresponsive external device would stall until platform reset.
