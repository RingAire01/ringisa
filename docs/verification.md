# Verification ledger

## Executed initial software checkpoint

Command: `python scripts/build.py --test` (Windows, clang, C11,
`-Wall -Wextra -Wpedantic -Werror -O2`).

- All four C binaries built without compiler diagnostics.
- Architectural C suite: PASS9096 checks.
- Integration: PASS all51 opcode round trips, all scalar/SIMD widths,
  forced extension encodings, random invalid-binary round trip, labels,
  180 randomized independent Python ALU oracle cases and executable example.
- C paging covers full high128 addresses, highest page,15-level walks,
  permissions/A/D, invalid/reserved PTE, unmapped traversal, ASID separation,
  TLB invalidation, atomic cross-page failure/success and address overflow.

RTL source presence is not a simulation/synthesis pass. Subsequent executed
results and security review will be appended before the final checkpoint.

## Final functional replay (Windows, clang22.1.8 / LLVM-MinGW)

`python scripts/build.py --test --sanitize`:

- PASS11176 C architectural checks; same suite also linked through `libringisa.a`.
- PASS180 independent Python scalar arithmetic cases; all51 opcode round trips,
  illegal-word preservation, mixed lengths, labels and interactive debugger.
- PASS121 hostile/malformed/resource/publication-failure cases, preserving
  existing output. PASS4 invalid-spec rejection fixtures.
- PASS malloc-family allocation failure injection at every physical mapping
  allocation point and preservation of existing pages; no tracked leaks.
- No ASan/UBSan reports; C11 `-Wall -Wextra -Wpedantic -Werror` builds clean.

`python scripts/analyze.py`: PASS9 clang translation units, zero diagnostics.

`python scripts/rtl.py --test --synth`:

- PASS26384 decode validity vectors: all256 OP values x4 lengths x16 FUNC
  values plus10000 seeded randomized W0/W1 pairs, compared to C decoder.
- PASS16 full core programs, compare all64 GPRs,9 CSRs, full128 PC and physical
  memory. Includes72 randomized scalar/SIMD operations, all register indices,
  memory widths, mixed encoding lengths, carry/borrow, signed loads, branch and
  return, syscall/illegal/overflow/underflow/physical faults, interrupt return,
  high128 paging/cross-page faults, device alignment and randomized bus stalls.
- PASS directed MMU: exactly15 initial table reads,116-bit VPN tags, ASID/global
  cache isolation, invalid/reserved/permission faults, highest128 VA and highest64 PA.
- PASS134 address-generator boundary vectors; negative and positive offsets,
  high/low-limb carry and every VA bit position.
- PASS concrete RAM fabric: loader, highest64-bit physical window, atomic failed
  store, successful256-bit transaction. No placeholder memory implementation.
- PASS core and RAM process synthesis, no structural problems/latches. Current
  core has13593 RTLIL cells with inferred memories; not a physical area number.

`python scripts/rtl.py --gates`: PASS current-source full generic gate synthesis
using `synth -top ringisa_core -noabc`, after the negative-offset fix.912445
generic one-bit cells; no memories/processes remaining; `check -assert` reports
zero problems and latch assertion passes. This is a generic logic netlist,
**not** standard-cell/FPGA technology mapping, timing or mobile PPA validation.
Output: `target/core-gates.json`, log: `target/gate-synthesis.log` (ignored).

Final replay of `python scripts/build.py --test --sanitize` and
`python scripts/rtl.py --test --synth` returned exit0 on the implementation
checkpoint `7b9905b7cc951636ef875981fca0045ea14cdc71`; captured logs are
`target/final-software.log` and `target/final-rtl.log`. Debug sanitizer and
Release builds were also executed. Actual local GNU GCC and Linux execution
remain unverified; local `gcc --version` identifies clang22.1.8.

## Repairs and failed attempts (resolved)

- Icarus initial local installer required elevation and was not used; validated
  portable OSS CAD Suite archive was unpacked in ignored `target/` instead.
- YoWASP initial cache location was inaccessible. Native suite used; scripts
  scope temporary/cache paths under `target/`.
- Fixed reserved SV identifier `iff`, implicit-net declaration ordering,
  unsized testbench concatenation and explicit simulation time units.
- Fixed ASID test fixture accidentally setting G; implementation correctly
  reused the global translation, so the fixture's original expectation was wrong.
- Fixed combinational loop-counter latch warning in the memory arbiter.
- Fixed Yosys macro-adjacent ternary lexical error with explicit spacing.
- Manual address audit found inverted negative-offset overflow logic. Replaced
  with129th-bit test; added standalone134-vector and two whole-core regressions.
- Stale full gate run was intentionally canceled after the address fix. Its
  termination status is not an unresolved implementation failure. Replacement
  final-source gate replay passed and supersedes that canceled attempt.

Icarus informational `sensitivity-entire-array` warnings are disabled explicitly:
whole-array combinational sensitivity is required for the associative CAMs,
not an accidental or unsafe sensitivity list. Other warnings remain enabled.

## Scope not claimed

No FPGA board, standard-cell library, place/route, timing closure, mobile power
or performance, Linux/GNU GCC runtime in this local environment, formal proof,
production security certification, REO compiler port or live third-party CI.
See `security.md` for threat boundaries and accepted residual risks.
