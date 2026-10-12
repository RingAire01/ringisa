# Architectural decisions

1. Preserve mandatory64x256-bit GPRs, full128-bit VA/PC and15-level translation.
   Portable C uses four64-bit limbs and two64-bit address limbs, no host pointers.
2. R0 hardwired zero; R63 link, R62 stack, R61 frame convention. No special
   register instructions. Narrow scalar zero extension except SAR; signed
   loads sign extend all the way to256.
3. Use OP to distinguish operation, FUNC only width. Reserve invalid widths.
   CHUNK's W1 is unsigned32; assembling arbitrary128-bit pointers needs four
   inserts. No operation depends on truncated64-bit addresses.
4. Software-managed A/D, explicit faults. This is a coherent supported policy,
   not a partially implemented automatic-update walker. Both C and RTL use it.
5. Only L0 leaves; future larger-page formats must define alignment/reservations.
6. All traps enter M; S exists for non-U mappings, WFI and local TLBI. CSR access
   is M-only initially; machine monitor manages S address spaces. No delegation.
7. Atomic gather/scatter memory interface selected for precise cross-page stores.
   External bus adapter must uphold all-or-none. No fake partial-store rollback.
8. Strongly ordered single-issue multicycle core. Large combinational multiply
   is functionally synthesizable but **not** a low-power optimized implementation.
   Timing/area optimization comes after differential correctness evidence.
9. Keep ISA repository independent from REO. Existing REO backend is not reused
   as a binary encoding definition. Compiler integration is a subsequent target
   adapter, not modification of unrelated user repositories in this task.
10. MIT initial repository license; third-party test tools are ignored build
    dependencies, never vendored as original source.
