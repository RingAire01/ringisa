# Security and correctness review scope

Assets: host files, host process memory, guest architectural state and guest
memory. Entry points: assembly text, binary images, CLI arguments, memory bus
responses, guest page tables and CSR operands. Assembly/binaries/guest values
are untrusted. Tool executable paths and the output directory are trusted
caller configuration. No network service, authentication, HTML, deserializer,
package installer or privileged host operation is exposed by the RingISA tools.

## Applied protections

- File inputs bounded16 MiB, statements131072, labels4096, lines4096 bytes.
  Label resolution is bounded linear search, not attacker-controlled recursion.
- NUL source bytes rejected; numeric parsing validates overflow and ranges;
  illegal register numbers/widths/immediates never silently truncate.
- Encode/decode field bounds and canonical system restrictions are checked;
  guests cannot index beyond64 GPRs or9 CSRs through encoded instructions.
- Binary fetch, every byte of memory operations and every PTE read checked.
  Physical page allocation bounded64 MiB; high128 VA never casts to a host
  pointer. Integer arithmetic uses unsigned limbs and explicit overflow.
- Precise exceptions: validate sequential PC, EA, translations and bus target
  permissions before architectural writes. CSR updates validate before commit.
- Atomic output publication uses exclusive creation next to destination,
  flush/sync then atomic replacement. Errors preserve existing outputs. Inputs
  are flat files, no archive extraction or guest-selected host paths.
- C tools do not use shell/system/exec or pass guest data to executable tools.
  Python build scripts invoke trusted compiler executables with argument arrays.
- No secrets/credentials. Output paths are an explicit caller-selected capability,
  not restricted to an assumed sandbox. Trusted-directory requirement prevents
  hostile concurrent symlink replacement; not a multi-user publication API.
- CPU/memory objects are thread-affine: one host thread owns each object.
  Independent CPUs can run in parallel; sharing an object requires external
  synchronization. No global mutable simulator or compiler state.

## Verification and residual risk

`tests/security.py` covers malformed/random text, limits, invalid encoding
operands and failed publication preservation. C scalar oracle and RTL
differential tests address data-flow/architecture consistency. Compiler warnings
are fatal; sanitizer/static-analysis evidence is recorded in verification, not
inferred from these controls. Current source dependencies: C standard library;
Python standard library. Third-party RTL tools are separate ignored dependencies.

Residual risks: process-level CPU exhaustion within step limits, simulator not a
host sandbox, filesystem permission/disk-full/OOM faults only partially injected,
memory fabric atomicity required from platform, no malicious electrical/fault
injection/side-channel resistance, no formal proof. No broad claim of OWASP/CWE
compliance or production mobile silicon qualification is made. Future exposed
services/compiler plugins require their own authentication and trust-boundary
review; present tooling has no HTTP/SQL/HTML/SSRF/CSRF/IDOR attack surface.
