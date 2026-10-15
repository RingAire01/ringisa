"""Reproducible ECP5 storage inference / mapping, not placement or timing.

--compare REV reads only four selected RTL files from an existing local commit;
it never checks out or edits historical/user files. Default mapping stops after
memory inference. --full executes the remaining technology mapping stages.
"""
import argparse
from collections import Counter
import json
import re
import subprocess
from pathlib import Path

from rtl import ROOT, TARGET, find, run

MODULES = {
    'ram': ('ringisa_ram_fabric', 'rtl/memory/ram_fabric.sv', 'MEMORY_BYTES', 131072),
    'registers': ('ringisa_register_file', 'rtl/registers/register_file.sv', None, None),
    'tlb': ('ringisa_tlb', 'rtl/mmu/tlb.sv', 'ENTRIES', 512),
    'pwc': ('ringisa_page_walk_cache', 'rtl/mmu/page_walk_cache.sv', 'ENTRIES', 32),
}


def measure(name, revision, full):
    top, relative, parameter, value = MODULES[name]
    label = revision or 'current'
    directory = TARGET / 'storage' / label
    directory.mkdir(parents=True, exist_ok=True)
    if revision:
        result = subprocess.run(['git', 'show', f'{revision}:{relative}'], cwd=ROOT,
                                check=True, capture_output=True, text=True)
        source = directory / (name + '.sv')
        source.write_text(result.stdout, newline='\n')
    else:
        source = ROOT / relative
    source_arg = source.relative_to(ROOT).as_posix()
    netlist = directory / (name + ('-full.json' if full else '-inference.json'))
    netlist_arg = netlist.relative_to(ROOT).as_posix()
    configure = f'chparam -set {parameter} {value} {top};' if parameter else ''
    # -run's upper label is exclusive: map_ffram includes the preceding map_ram
    # stage without expanding the memories that could not map to RAM primitives.
    flow = f'synth_ecp5 -top {top}' + ('' if full else ' -run begin:map_ffram')
    command = (f'read_verilog -sv {source_arg}; {configure} {flow}; blackbox =A:whitebox; '
               f'check -assert; select -assert-none t:$dlatch t:$_DLATCH_*; '
               f'stat; write_json {netlist_arg}')
    run([find('yosys'), '-Q', '-T', '-p', command],
        f'storage-{label}-{name}-' + ('mapping.log' if full else 'inference.log'))
    cells = json.loads(netlist.read_text())['modules'][top]['cells']
    types = Counter(cell['type'] for cell in cells.values())
    ff_bits = sum(int(cell['parameters']['WIDTH'], 2) for cell in cells.values()
                  if cell['type'] in ('$dff', '$dffe', '$sdff', '$sdffe', '$sdffce',
                                      '$adff', '$adffe') and 'WIDTH' in cell['parameters'])
    memory_bits = sum(int(cell['parameters']['WIDTH'], 2) * int(cell['parameters']['SIZE'], 2)
                      for cell in cells.values() if cell['type'] == '$mem_v2')
    item = {'revision': label, 'module': top, 'full_mapping': full,
            'cells': dict(sorted(types.items())), 'unmapped_ff_bits': ff_bits,
            'unmapped_memory_bits': memory_bits}
    if not revision:
        # Machine-checkable guard against accidentally reintroducing reset-data
        # arrays or asynchronous RAM reads. This is memory inference, not fit.
        if name == 'ram' and (types['DP16KD'] != 64 or types['TRELLIS_DPR16X4'] != 0
                              or types['$mem_v2'] != 0):
            raise RuntimeError('128 KiB RAM must infer 64 ECP5 blocks, not distributed/unmapped data RAM')
        if name in ('registers', 'tlb', 'pwc') and types['TRELLIS_DPR16X4'] == 0:
            raise RuntimeError(f'{name} did not infer ECP5 distributed payload memory')
        if name == 'registers' and (types['TRELLIS_FF'] if full else ff_bits) > 64:
            raise RuntimeError('register-file data unexpectedly mapped to flipflops')
    print(label, name, 'BRAM=', types['DP16KD'], 'LUTRAM=', types['TRELLIS_DPR16X4'],
          'FF=', types['TRELLIS_FF'] if full else ff_bits, 'unmapped memory bits=', memory_bits)
    return item


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare', metavar='REV')
    parser.add_argument('--full', action='store_true')
    parser.add_argument('--top', choices=MODULES, action='append')
    parser.add_argument('--simulate-registers', metavar='LATTICE_LIBRARY_DIR',
                        help='with --full: simulate the mapped RF using real Yosys Lattice primitive models')
    args = parser.parse_args()
    if args.compare and not re.fullmatch(r'[0-9a-fA-F]{7,40}', args.compare):
        parser.error('--compare requires a hexadecimal local commit ID')
    library = Path(args.simulate_registers).resolve() if args.simulate_registers else None
    if library:
        if not args.full or 'registers' not in (args.top or MODULES):
            parser.error('--simulate-registers requires --full and the registers target')
        for model in ('common_sim.vh', 'ccu2c_sim.vh'):
            if not (library / model).is_file():
                parser.error(f'missing functional Lattice model: {library / model}')
    TARGET.mkdir(exist_ok=True)
    summary = [measure(name, revision, args.full)
               for revision in ([args.compare, None] if args.compare else [None])
               for name in (args.top or MODULES)]
    path = TARGET / ('storage-full-summary.json' if args.full else 'storage-inference-summary.json')
    path.write_text(json.dumps(summary, indent=2) + '\n')
    if library:
        source = 'target/storage/current/registers-mapped.v'
        run([find('yosys'), '-Q', '-T', '-p',
             f'read_json target/storage/current/registers-full.json; write_verilog -noattr -noexpr {source}'],
            'storage-register-gates-export.log')
        simulation = TARGET / 'storage/current/registers-mapped.vvp'
        run([find('iverilog'), '-g2012', '-I', library, '-s', 'register_tb', '-o', simulation,
             source, library / 'common_sim.vh', library / 'ccu2c_sim.vh', 'tests/rtl/register_tb.sv'],
            'storage-register-gates-compile.log')
        output = run([find('vvp'), simulation], 'storage-register-gates-test.log')
        if 'PASS register file' not in output:
            raise RuntimeError('mapped register-file scoreboard did not finish')
        print(output)
    print('PASS storage mapping/inference checks; not place/route, timing or device fit')


if __name__ == '__main__':
    main()
