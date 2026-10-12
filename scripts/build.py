"""Portable build and regression entry point. Requires a C11 compiler."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def run(args):
    print('+', ' '.join(map(str,args)), flush=True)
    subprocess.run(list(map(str,args)),cwd=ROOT,check=True)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--test',action='store_true');parser.add_argument('--sanitize',action='store_true');parser.add_argument('--config',choices=['Release','Debug','Alpha'],default='Release');args=parser.parse_args()
    run([sys.executable,'tools/specgen/generate.py'])
    target=ROOT/'target';target.mkdir(exist_ok=True)
    compiler=os.environ.get('CC','clang');flags=['-std=c11','-Wall','-Wextra','-Wpedantic','-Werror']
    flags += {'Release':['-O3','-DNDEBUG'],'Debug':['-O0','-g3'],'Alpha':['-O2','-g']}[args.config]
    if args.sanitize:flags+=['-fsanitize=address,undefined','-g']
    suffix='.exe' if os.name=='nt' else ''
    common=['tools/common/generated.c','tools/common/value.c','tools/common/io.c']
    machine=['tools/simulator/memory.c','tools/simulator/cpu.c']
    archiver=os.environ.get('AR') or shutil.which('llvm-ar') or shutil.which('ar')
    if archiver:
        objects=[];(target/'lib').mkdir(exist_ok=True)
        for source in ['tools/common/generated.c','tools/common/value.c',*machine]:
            obj=target/'lib'/(Path(source).stem+'.o');run([compiler,*flags,'-c',source,'-o',obj]);objects.append(obj)
        with tempfile.TemporaryDirectory(dir=target,prefix='archive-') as temporary:
            archive=Path(temporary)/'libringisa.a';run([archiver,'rcs',archive,*objects]);os.replace(archive,target/'libringisa.a')
    else:print('Static library skipped: no archiver available; set AR to enable it',flush=True)
    for name,sources in [('as',['tools/assembler/main.c']),('dis',['tools/disassembler/main.c']),('sim',['tools/simulator/main.c','tools/simulator/debug.c']+machine),('test',['tests/test.c']+machine),('vectors',['tests/encoding/vectors.c'])]:
        if name in ('test','vectors') and not args.test:continue
        run([compiler,*flags,*common,*sources,'-o',target/('ringisa-'+name+suffix)])
    if args.test:
        if archiver:
            run([compiler,*flags,'tests/test.c',target/'libringisa.a','-o',target/('ringisa-library-test'+suffix)])
            run([target/('ringisa-library-test'+suffix)])
        run([compiler,*flags,'-Dcalloc=ri_test_calloc','-Drealloc=ri_test_realloc','-Dfree=ri_test_free','-c','tools/simulator/memory.c','-o',target/'memory-fault.o'])
        run([compiler,*flags,'tools/common/generated.c','tests/memory/allocation.c',target/'memory-fault.o','tools/common/value.c','-o',target/('ringisa-allocation'+suffix)])
        run([target/('ringisa-allocation'+suffix)])
        run([target/('ringisa-test'+suffix)])
        run([sys.executable,'tests/integration.py'])
        run([sys.executable,'tests/security.py'])
        run([sys.executable,'tests/encoding/spec_validation.py'])
if __name__=='__main__':main()
