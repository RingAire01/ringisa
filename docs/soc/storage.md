# FPGA storage inference improvements

This iteration preserves all ISA encodings, register contents observable after
reset, native128-bit translation tags and fully associative round-robin cache
replacement. It changes storage implementation and physical RAM read latency,
not guest-visible values or exception behavior. There are no caches, widths or
instruction features removed to make synthesis pass.

## Implemented changes

- Transactional RAM: one mutually exclusive loader/store write port, explicit
  synchronous byte read register and a separate READ_BACK FSM phase. The full
  scatter list is still validated before the first side effect. Stored data and
  read-register contents are not reset; transaction ownership and returned data
  are reset. Read validity comes from the FSM, not uninitialized register data.
  Each enabled read byte now costs one extra cycle. Disabled bytes remain zero.
- Register file: one64-bit validity mask resets instead of resetting every
  256-bit data word. All four read ports return zero until that word receives a
  post-reset write. R0 remains zero. Data write and valid publication happen on
  the same edge. Reset wins over writes, so stale pre-reset contents never leak.
- TLB: the full tag/root/ASID/global match remains a CAM, preserving the highest
  matching-slot priority and round-robin insertion order. Only the selected
  PPN/permissions/device payload uses a single indexed memory read. Global
  matching has a separate one-bit field; no VPN/root/ASID bits are omitted.
- Page-walk cache: retain the original full match and replacement semantics,
  select a slot index, then read one128-bit PTE payload through indexed memory.
  TLB/PWC outputs still read combinationally; no lookup pipeline was added.

Bounded RAM indices use `$clog2(MEMORY_BYTES)` only **after full64-bit address
validation**; non-power-of-two sizes are range checked, never silently wrapped.
No loader write is accepted during a CPU request or reset. The read/write port
exclusion also avoids undefined dual-write or read-during-write collisions.

## Reproduce

```sh
python scripts/build.py --test --sanitize
python scripts/rtl.py --test --synth --soc
python scripts/storage.py
python scripts/storage.py --compare 434b1ca
python scripts/storage.py --full --top ram --top registers
python scripts/storage.py --compare 434b1ca --full --top registers
python scripts/storage.py --full --top registers --simulate-registers target/oss-cad-suite/share/yosys/lattice
python scripts/fpga.py --map --pnr
python scripts/fpga.py --map --pnr --lut-mapper abc
```

`--compare` reads four selected files from an existing local hexadecimal Git
revision into ignored `target/storage/<revision>`. It never checks out, resets
or replaces the working tree. The historical commit must be available locally;
CI instead checks current source without depending on shallow Git history.

Default storage synthesis stops after `synth_ecp5 -run begin:map_ffram` (the upper
label is exclusive, so the preceding `map_ram` stage is included); it asserts
nonzero block RAM inference for RAM and distributed payload inference for the
register file/TLB/PWC. It does **not** assert whole-device fit. `--full` completes
technology mapping. Machine-readable summaries live under `target/`; complete
logs are `target/storage-*-inference.log` and `*-mapping.log`. Primitive-library
whiteboxes are treated as library blackboxes for intermediate JSON output, as
in the synthesis flow's normal final stage; they are not substituted designs.

## Added verification

- Register-file scoreboard:5056 checks across all four ports, same-index
  read/write, zero register, reset/write priority and stale-data visibility.
  Seed0x52464732. Expected words are independently tracked, not DUT internals.
- TLB/PWC scoreboard:238000 checks each for1,3 and32 entries (714000 total).
  Includes every116-bit VPN bit, full root, ASID and global behavior, duplicate
  selection, replacement wrap and invalidate/reset concurrent with insert.
  Seeds0x544c4233,0x544c4235,0x544c4252.
- RAM scoreboard:241/307/753 transactions for1/67/513-byte RAM (1301 total),
  uppermost64-bit PA, odd-size boundaries, duplicate scatter destinations,
  masks, late invalid-byte faults without partial stores, captured requests,
  loader exclusion, read-wait reset recovery and retained contents.
  Seeds0x52414d33,0x52414d75,0x52414f33.
- Existing decoder, core differential, MMU, SoC, UART, bus and independent C
  architecture replay tests remain mandatory and are not replaced by scoreboards.

The new register and TLB/PWC scoreboards were also executed against the actual
`434b1ca` historical RTL and passed with the same5056/714000 checks. Thus the
expected reset/match/duplicate behavior was not invented from the optimized
implementation merely to make it pass. RAM intentionally changes latency;
its scoreboard checks the transaction protocol and data effects instead.

## Verified standalone technology mapping

128 KiB RAM:64 DP16KD, no distributed memory,2614 control/data-path FF.
Register file:1024 TRELLIS_DPR16X4,64 FF. These are completed ECP5 mappings
of standalone modules, **not** a complete SoC PNR or achieved clock frequency.
CAM tags and wide arithmetic remain substantial resource/timing risks.
The same full-mapping command measured the historical register file at16128 FF
and0 distributed RAM primitives; the new file has16064 fewer FF. This is a
measured module comparison, not an estimate from declared array sizes.

The technology-mapped register-file netlist also passes the same5056-check
scoreboard using the actual Yosys `common_sim.vh`/`ccu2c_sim.vh` functional
primitive models. `--simulate-registers` takes the installed Lattice library
directory explicitly; adjust the example path for your tool installation.
No source RTL is substituted for the mapped RF. This gate-level test does not
cover timing delays or a whole mapped CPU. RAM gate simulation is not claimed:
the supplied DP16KD model is a blackbox, not a functional BRAM model.

The completed `--compare 434b1ca` inference run reports:

| Module | DP16KD old → new | Distributed primitives old → new | Unmapped memory bits old → new |
|---|---:|---:|---:|
|128 KiB RAM|0 →64|65536 →0|0 →0|
|Register file|0 →0|0 →1024|16384 →0|
|512-entry TLB|0 →0|0 →512|132608 →101376|
|32-entry PWC|0 →0|0 →64|8736 →4640|

These are intermediate memory-mapping results, not total mapped FF/LUT counts.
Unmapped arrays have not yet undergone the later FF expansion/optimization.
TLB/PWC tags still require substantial storage; payload RAM inference alone
does not imply the entire CAM fits. All eight old/new inference commands and
their structural/latch checks completed successfully.

Remote CI for code commit `ec8d36ccdd64dfdb6a0d9ac7ab2d59a3ffddaa31` is
[successful](https://github.com/RingAire01/ringisa/actions/runs/38674472594):
all four Windows/Linux compiler jobs and the hardware job passed, including
storage inference and technology-mapped RF simulation. A documentation-only
follow-up does not expand the scope of the measured code revision.

After these changes, the combined boot test completes in33075 simulated clocks
(186 retired instructions,20 UART bytes, one acknowledged timer interrupt).
The extra40 clocks versus the previous33035 come from synchronous RAM reads;
this is intentional latency, not a timing failure or an ISA change. The test
does not assert a fixed clock count; it checks actual hardware effects.
Full SoC process synthesis/check/latch assertions pass:28411 hierarchical
primitive RTLIL cells,1366368 inferred memory bits. The additional608 storage
bits duplicate the global flag for the608 TLB CAM entries so payload RAM does
not need hundreds of global-flag read ports. These are not LUT or BRAM counts.

No frequency improvement is claimed. The TLB now has a match-to-priority-index
path before payload lookup; replacing FF muxes with indexed RAM may improve
resource use without improving that path's delay. Measure after full mapping
and PNR before interpreting the structural change as a performance win.

## Full-device retry and host-tool failure

The new full SoC ABC9 attempt still exits3221225725 (Windows stack overflow)
at XAIGER2 export. Before that failure it derives129128 TRELLIS_FF,88 DP16KD,
664 distributed RAM primitives and204 MULT18X18D. The previous attempt derived
184743 FF:55615 fewer FF (about30.1%). These are **intermediate** observations,
not completed fit/PNR counts. FF demand still exceeds the85F target capacity.

`--lut-mapper abc` retains the ordinary memory/DSP/carry/FF flow but uses classic
ABC LUT4 mapping in place of ABC9. It is a reproducible tool-host fallback,
not an ISA/multiplier reduction or claimed timing improvement. It does not
relabel an ABC9 failure as success. Completed mapping/PNR results are recorded
separately when actually available. An optional standalone512-entry full-TLB
ABC9 mapping also exceeded a240-second foreground limit; the timeout is not
counted as mapping success. Inference and behavioral checks remain separate.

An initial inference-script check incorrectly stopped at `begin:map_ram`,
which excludes the `map_ram` stage. Its nonzero exit was investigated rather
than suppressing the guard. The corrected exclusive upper label is
`begin:map_ffram`; the full standalone mappings above were unaffected.

## Completed classic-ABC mapping and failed device placement

`python scripts/fpga.py --map --pnr --lut-mapper abc` completed full SoC ECP5
technology mapping and its structural check reported0 problems. This resolves
the host ABC9 stack failure via a different supported LUT mapping flow, not by
removing ISA functionality. The mapped top contains305800 cells including32
scope records:173100 LUT4,127144 TRELLIS_FF,4568 CCU2C,88 DP16KD,
664 TRELLIS_DPR16X4 and204 MULT18X18D. This is an actual completed mapping,
unlike the earlier intermediate ABC9 figures.

nextpnr ran for LFE5U-85F/CABGA381/speed6 at requested25 MHz, seed52495341,
with unconstrained pins permitted for feasibility. Its resource report:

| Resource | Required | Available | Tool-reported utilization |
|---|---:|---:|---:|
|TRELLIS_FF|127144|83640|152%|
|TRELLIS_COMB (packed logic requirement)|187248|83640|223%|
|MULT18X18D|204|156|130%|
|DP16KD|88|208|42%|

Placement failed with `no BELs remaining to implement cell type TRELLIS_COMB`
(nextpnr exit125). **The complete design does not fit this device.** Routing,
timing closure, achieved Fmax and board execution were not completed. The
25 MHz command-line target is not an achieved frequency. Packed COMB demand
is not interchangeable with the173100 pre-pack LUT4 count. No power result.

Artifacts remain ignored: `target/soc-ecp5.json` (mapped netlist),
`target/fpga-soc-abc-mapping.log` and `target/fpga-soc-pnr.log`. The command
returns nonzero on the placement failure; no resource/timing check is disabled
to turn that failure green. The next implementation milestone requires reducing
CAM/arithmetic demand or choosing a genuinely larger supported device, without
silently shrinking the architectural state or truncating128-bit addresses.

## Changed-boundary robustness review

Untrusted guest physical addresses still pass full-width validation before
forming narrow storage indices. Zero masks, high PA, late invalid bytes,
duplicate destinations and request-input mutation are covered. No filesystem,
network service, authorization policy, dependency or secret was introduced.
The small compare tool accepts only hexadecimal Git revisions and fixed source
paths, uses subprocess argument arrays (not a command shell), and writes only
ignored build artifacts. Yosys commands contain fixed validated project paths.

Reset tests target publication of stale/uninitialized words and ownership of
the synchronous read register. Validity masking is an architectural reset
implementation, **not physical zeroization**: stored bits remain in FPGA memory
until overwritten. Reset during a multi-byte store still aborts execution and
can preserve partial physical writes, as previously documented. No new claim
of power-failure persistence, arbitrary external-slave rollback or physical
side-channel protection is made. Full tag CAM resource demand and unmeasured
timing are accepted remaining implementation risks, not verified-safe metrics.
