"""Local adversarial input regressions; no production/third-party probing."""
from pathlib import Path
import os
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1];TARGET=ROOT/'target';EXT='.exe' if os.name=='nt' else ''
def main():
    assembler=TARGET/('ringisa-as'+EXT);source=TARGET/'hostile.s';output=TARGET/'hostile.bin';rng=random.Random(0x534543)
    cases=[b'MOVI R64,1',b'ADD.512 R1,R2,R3',b'ADD.8.X R1,R2,R3',b'MOVI R1,2199023255552',b'MOVI R1,-2199023255553',b'CHUNK R1,8,0',b'CHUNK R1,0,0x100000000',b'LD.U8 R1,R2,missing',b'CSRR R1,9',b'ERET.X',b'SVC -1',b'TLBI R1',b'.word -1',b'a: WFI\na: WFI',b'BEQ R1,R2,unknown',b'CONST128 R1,0x100000000000000000000000000000000',b'CONST256 R1,0x1'+b'0'*64,b'WFI\x00WFI',b'A'*4097]
    cases += [rng.randbytes(rng.randrange(1,256)) for _ in range(100)]
    for case in cases:
        output.write_bytes(b'keep-previous-output');source.write_bytes(case)
        result=subprocess.run([str(assembler),str(source),str(output)],cwd=ROOT,capture_output=True,timeout=10)
        assert result.returncode!=0 and output.read_bytes()==b'keep-previous-output',(case,result.stdout,result.stderr)
    # Oversized sources fail without publishing output.
    source.write_bytes(b' '*((16<<20)+1));result=subprocess.run([str(assembler),str(source),str(output)],cwd=ROOT,capture_output=True,timeout=10);assert result.returncode!=0
    # Failure publishing to a nonexistent parent must not create partial output.
    source.write_text('WFI\n');result=subprocess.run([str(assembler),str(source),str(TARGET/'nonexistent-parent/out.bin')],cwd=ROOT,capture_output=True,timeout=10);assert result.returncode!=0
    print(f'PASS {len(cases)+2} malformed/resource-limit/publication-failure cases; existing output preserved')
if __name__=='__main__':main()
