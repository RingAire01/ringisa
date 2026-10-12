"""Check collision/architecture/semantics rejection without modifying the repo."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile

ROOT=Path(__file__).resolve().parents[2]
def main():
    loader=importlib.util.spec_from_file_location('ringisa_specgen',ROOT/'tools/specgen/generate.py');module=importlib.util.module_from_spec(loader);loader.loader.exec_module(module)
    original=json.loads((ROOT/'spec/isa.json').read_text());cases=[]
    duplicate=copy.deepcopy(original);duplicate['instructions'][1]['op']=duplicate['instructions'][0]['op'];cases.append(duplicate)
    truncated=copy.deepcopy(original);truncated['virtual_address_bits']=64;cases.append(truncated)
    reduced=copy.deepcopy(original);reduced['mmu']['levels']=5;cases.append(reduced)
    missing=copy.deepcopy(original);del missing['semantics']['ADD'];cases.append(missing)
    with tempfile.TemporaryDirectory(dir=ROOT/'target',prefix='spec-validation-') as directory:
        module.ROOT=Path(directory);(module.ROOT/'spec').mkdir()
        for case in cases:
            (module.ROOT/'spec/isa.json').write_text(json.dumps(case))
            try:module.generate()
            except ValueError:pass
            else:raise AssertionError('invalid architecture/spec accepted')
    print('PASS specification rejection: opcode collision, address truncation, reduced page depth, missing semantics')
if __name__=='__main__':main()
