# Roadmap / release gates

- [x] M0 original encoding, register/address/privilege design, machine-readable table.
- [x] M1 portable C arithmetic, assembler, disassembler, executable simulator.
- [x] M2 full128-bit paging, sparse physical RAM, caches, traps and return.
- [x] M3 functional RTL modules and integrated multicycle core/MMU source.
- [x] M4 execute RTL directed/random differential tests; repair failures.
- [x] M5 process synthesis/structural checks for core and concrete RAM fabric.
- [x] M6 external-input hardening, sanitizer/static analysis, CI and documentation.
- [x] Final current-source generic gate synthesis replay after negative-offset fix.
- [ ] Execute remote Linux / actual GNU GCC CI matrix (configuration committed,
  local `gcc` is a clang alias and is not independent compiler evidence).

Initial completion requires executed RTL evidence, not just RTL source. Mobile
PPA, peripheral fabric, software OS port and REO compiler backend are subsequent
product work, not assertions implied by the v0.1 reference implementation.
