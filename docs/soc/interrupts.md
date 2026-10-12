# Interrupt execution

Peripheral pending/mask drives CPU's existing external64-bit interrupt input;
it is ORed into IP reads by the unmodified CSR block. CSR IE and STATUS.IE still
gate delivery. All interrupts trap to M, CAUSE14, TVAL0 and EPC at the next
instruction boundary. Nothing in the interconnect delegates traps or truncates
EPC. An active memory operation completes before IRQ entry.

Firmware sets TVEC0x1000, enables controller bit0 and CSR IE bit0, sets STATUS
IE, then programs/enables timer. The handler reads CAUSE, disables timer,
clears timer PENDING, clears controller pending, increments R30 and stores
CAUSE in RAM, then ERET. It uses R40 and R31 as explicitly allowed demonstration
scratch registers, not an undisclosed fully preserved interrupt ABI. Main checks
CAUSE14, R30=1, clears STATUS IE and publishes success. ERET restores the saved
privilege/IE and EPC using the baseline ISA. Controller ACK precedes return.

Bench checks actual trap count, handler effect, cleared timer/controller state,
trap-active flag cleared, restored privilege and completed main code. Combined
test first polls/acknowledges a prior timer event; controller pending must also
be cleared before the later interrupt enable. This was an actual integration
failure discovered and repaired, not a skipped check.

No hardware interrupt priority encoder is needed for the current common trap
class; handler software can examine IP/ACTIVE bit masks. No automatic nesting,
interrupt stack or fast interrupt path. External interrupt source is level-based
and requires board/device-specific deassertion before ACK.
