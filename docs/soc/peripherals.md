# Peripheral semantics

Offsets/bases are generated in `address-map.md`. Register transactions are
32-bit aligned; byte writes obey strobes. Unknown offsets return SLVERR, unknown
regions DECERR. Registers default zero unless explicitly stated below.

## UART (8N1 TX and RX)

- TX, write only: low8 bits launch a frame when byte0 strobe is set. Busy write
  is SLVERR, no new frame. Empty byte0 strobe has no transmit side effect.
- RX, read only: low8 received byte. Reading clears RX-ready. No RX FIFO;
  one unread byte is retained and a later valid byte sets sticky overrun.
  A simultaneous read consumes the old byte and permits new-byte publication;
  RX completion wins over read-clear even if the slot was previously empty.
- STATUS, read only: bit0 TX-ready, bit1 RX-ready, bit2 overrun, bit3 framing.
- CONTROL: bit0 enables RX-ready IRQ; writing bit1 clears overrun/framing.
  Bit1 is a command, not retained. All other bits ignored/reserved for platform.
- DIVISOR: cycles per serial bit, minimum4. Reset max(4,CLOCK_HZ/115200).
  Changing while TX busy or RX frame active is SLVERR. Invalid divisor rejected.
  RX has a two-flop synchronizer and samples at bit centers, half-bit start
  qualification, stop-bit verification. Not a baud-error-tolerance qualification.

Acceptance receives actual UART TX waveform independently of tx_event/tx_byte.
Bus regression injects an independent RX frame0xa5 and checks read-clear.

## Timer

COUNT:32-bit wrapping clock counter; writable with byte merge. COMPARE resets
0xffffffff; writable with merge. CONTROL bit0 enables counting, other bits
ignored. When enabled and old COUNT>=COMPARE, PENDING bit0 latches1. It stays
set when disabled; write1 to PENDING low byte acknowledges, write0 does nothing.
Ack wins that cycle; if counting remains beyond compare, next cycle reasserts.
Disable or update the compare before clearing for one-shot behavior. This timer
uses deterministic clock edges, not host wall time. No implicit CPU CSR writes.

## Interrupt controller

Sources bit0 timer, bit1 UART RX-ready, bit2 synchronized external input.
PENDING read only, latches asserted sources regardless of MASK. MASK read/write
low3 bits. ACK write-one-to-clear low3 bits; still-asserted level source wins over
ack and remains pending. ACTIVE read only = PENDING & MASK. Other source bits
zero. Sources independently feed CPU IE/IP bit indices; no encoded priority,
claim/complete or delegation. CPU selects the single interrupt trap class14.

Clear peripheral source first, then controller ACK. This prevents repeated
delivery of a live level interrupt; hiding a pending source by MASK alone does
not acknowledge it. Zero masks on reset guarantee no unrequested trap.
