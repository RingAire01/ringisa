"""Run actual RTL simulation and synthesis. Missing tools fail, never fake PASS.

Override IVERILOG, VVP, YOSYS with executable paths; searches PATH and optional
ignored target/oss-cad-suite extraction. No dependencies are auto-downloaded.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'target'
def find(name):
    explicit=os.environ.get(name.upper())
    if explicit:return explicit
    found=shutil.which(name)
    if found:return found
    for parent in [TARGET/'oss-cad-suite/bin',TARGET/'iverilog/bin',TARGET/'python/Scripts']:
        for n in [name+'.exe',name,'yowasp-'+name+'.exe']:
            if (parent/n).is_file():return str(parent/n)
    raise RuntimeError(f'{name} is not available; set {name.upper()}')
def run(args,log=None):
    env=os.environ.copy()
    suite=TARGET/'oss-cad-suite'
    env['PATH']=str(suite/'bin')+os.pathsep+str(suite/'lib')+os.pathsep+env['PATH']
    env['YOWASP_CACHE_DIR']=str(TARGET/'yowasp-cache')
    temp=TARGET/'tmp';temp.mkdir(exist_ok=True)
    for name in ('TMP','TEMP','TMPDIR'):env[name]=str(temp)
    print('+',' '.join(map(str,args)),flush=True)
    result=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,text=True,capture_output=True)
    if log:(TARGET/log).write_text(result.stdout+result.stderr)
    if result.returncode:print((result.stdout+result.stderr)[-4000:]);raise RuntimeError(f'command failed: {result.returncode}; full output in target/{log}' if log else f'command failed: {result.returncode}')
    return result.stdout
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--test',action='store_true');parser.add_argument('--synth',action='store_true');parser.add_argument('--gates',action='store_true');parser.add_argument('--soc',action='store_true');args=parser.parse_args()
    TARGET.mkdir(exist_ok=True);sources=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'rtl').rglob('*.sv'))
    if args.test:
        iv=find('iverilog');vvp=find('vvp')
        for top in ['core_tb','mmu_tb','decoder_tb','ram_tb','address_tb']:
            # Whole-array sensitivity is intentional for the associative CAMs;
            # Icarus's informational warning describes correct required behavior.
            run([iv,'-g2012','-Wall','-Wno-sensitivity-entire-array','-Irtl/decode','-Irtl/soc','-s',top,'-o',TARGET/(top+'.vvp'),*sources,f'tests/rtl/{top}.sv'],top+'-compile.log')
        print(run([vvp,TARGET/'mmu_tb.vvp'],'mmu-simulation.log'))
        print(run([vvp,TARGET/'ram_tb.vvp'],'ram-simulation.log'))
        print(run([vvp,TARGET/'address_tb.vvp'],'address-simulation.log'))
        suffix='.exe' if os.name=='nt' else ''
        vectors=run([TARGET/('ringisa-vectors'+suffix)])
        (TARGET/'decoder-vectors.hex').write_text(vectors)
        print(run([vvp,TARGET/'decoder_tb.vvp',f'+vectors={TARGET/"decoder-vectors.hex"}',f'+count={len(vectors.splitlines())}'],'decoder-simulation.log'))
        run([sys.executable,'tests/rtl/differential.py',vvp],'differential.log');print((TARGET/'differential.log').read_text())
    if args.synth or args.gates:
        yosys=find('yosys')
        flow='synth -top ringisa_core -noabc' if args.gates else 'hierarchy -check -top ringisa_core; proc; opt'
        commands=f'read_verilog -sv -Irtl/decode -Irtl/soc {" ".join(sources)}; {flow}; check -assert; select -assert-none t:$dlatch t:$_DLATCH_*; stat; write_json target/core{"-gates" if args.gates else ""}.json'
        out=run([yosys,'-Q','-T','-p',commands],'gate-synthesis.log' if args.gates else 'synthesis.log')
        print(out[-5000:]);print('PASS RTL elaboration/process synthesis/structural check; not timing or technology mapping')
        if args.synth:
            ram='read_verilog -sv rtl/memory/ram_fabric.sv; hierarchy -check -top ringisa_ram_fabric; proc; opt; check -assert; select -assert-none t:$dlatch; stat; write_json target/ram.json'
            run([yosys,'-Q','-T','-p',ram],'ram-synthesis.log')
            print('PASS standalone concrete RAM fabric synthesis/structural check')
    if args.soc:
        command=[sys.executable,'scripts/soc.py']
        if args.test:command.append('--test')
        if args.synth:command.append('--synth')
        print(run(command,'soc-full.log'))
if __name__=='__main__':main()
