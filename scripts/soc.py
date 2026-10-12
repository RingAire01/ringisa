"""Build, simulate and synthesize RingISA SoC; never treats skips as passes."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import os
import re
from collections import Counter
def synthesis_counts(path,top):
    modules=json.loads(path.read_text())['modules']
    def walk(name):
        result=Counter();memory=0
        for obj in modules[name].get('memories',{}).values():memory+=obj['width']*obj['size']
        for cell in modules[name]['cells'].values():
            if cell['type'] in modules:
                children,bits=walk(cell['type']);result.update(children);memory+=bits
            else:result[cell['type']]+=1
        return result,memory
    cells,memory=walk(top)
    return {'top':top,'primitive_cells':sum(cells.values()),'inferred_memory_bits':memory,'cell_types':dict(sorted(cells.items()))}
from rtl import ROOT,TARGET,find,run
def main():
    p=argparse.ArgumentParser();p.add_argument('--test',action='store_true');p.add_argument('--synth',action='store_true');args=p.parse_args()
    print(run([sys.executable,'scripts/boot.py'],'soc-images.log'))
    sources=sorted(str(s.relative_to(ROOT)).replace('\\','/') for s in (ROOT/'rtl').rglob('*.sv'))
    if args.test:
        iv,vvp=find('iverilog'),find('vvp')
        for top in ['soc_tb','bus_tb','adapter_tb','lite_tb','uart_tb']:
            run([iv,'-g2012','-Wall','-Wno-sensitivity-entire-array','-Irtl/decode','-Irtl/soc','-s',top,'-o',TARGET/(top+'.vvp'),*sources,'tests/soc/'+top+'.sv'],top+'-compile.log')
        print(run([vvp,TARGET/'bus_tb.vvp'],'soc-bus.log'))
        print(run([vvp,TARGET/'adapter_tb.vvp'],'soc-adapter.log'))
        print(run([vvp,TARGET/'lite_tb.vvp'],'soc-lite.log'))
        print(run([vvp,TARGET/'uart_tb.vvp'],'soc-uart-races.log'))
        manifest=json.loads((TARGET/'soc/manifest.json').read_text())
        suffix='.exe' if os.name=='nt' else ''
        flags=['-D_CRT_SECURE_NO_WARNINGS'] if os.name=='nt' else []
        run([os.environ.get('CC','clang'),'-std=c11','-Wall','-Wextra','-Wpedantic','-Werror','-O2',*flags,'tests/soc/replay.c','tools/common/io.c','tools/common/value.c','tools/common/generated.c','tools/simulator/memory.c','tools/simulator/cpu.c','-o',TARGET/('soc-replay'+suffix)],'soc-replay-build.log')
        for name,expected in manifest.items():
            shutil.copyfile(TARGET/'soc'/f'{name}.hex',TARGET/'soc/current.hex')
            output=run([vvp,TARGET/'soc_tb.vvp',f'+uart={int(expected["uart"])}',f'+irq={int(expected["interrupt"])}',f'+memory={int(expected["memory"])}',f'+privilege={expected.get("privilege",2)}',f'+signature={expected.get("signature",32)}',f'+fault={expected.get("fault",0)}'],'soc-'+name+'.log')
            if 'PASS SoC' not in output:raise RuntimeError('missing acceptance result')
            replay=run([TARGET/('soc-replay'+suffix),TARGET/'soc'/f'{name}.bin',TARGET/('soc-'+name+'.log')],'soc-'+name+'-replay.log')
            pattern=r'^(R\d+|CSR\d+)=(0x[0-9a-fA-F]+)$'
            state=lambda text:{k:int(v,16) for k,v in re.findall(pattern,text,re.M)}
            if len(state(replay))!=73 or state(replay)!=state(output):raise RuntimeError('C/RTL SoC architectural mismatch: '+name)
            if re.search(r'FINAL pc=(\w+)',replay)[1]!=re.search(r'FINAL pc=(\w+)',output)[1]:raise RuntimeError('SoC replay PC mismatch')
            print(name,output.splitlines()[-2])
        print('PASS eight RTL bare-metal programs and C architectural replays, including combined acceptance and native128 MMU')
    if args.synth:
        yosys=find('yosys')
        summary=[]
        for top in ['ringisa_cpu_axi','ringisa_axi_interconnect','ringisa_peripherals','ringisa_soc']:
            image=f'chparam -set ROM_IMAGE "target/soc/combined.hex" {top};' if top in ('ringisa_axi_interconnect','ringisa_soc') else ''
            cmd=f'read_verilog -sv -Irtl/decode -Irtl/soc {" ".join(sources)}; {image} hierarchy -check -top {top}; proc; opt; check -assert; select -assert-none t:$dlatch; stat; write_json target/{top}.json'
            result=run([yosys,'-Q','-T','-p',cmd],top+'-synthesis.log');print('PASS process synthesis',top)
            summary.append(synthesis_counts(TARGET/(top+'.json'),top))
        (TARGET/'soc-synthesis-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
        for item in summary:print(item['top'],item['primitive_cells'],'RTLIL cells;',item['inferred_memory_bits'],'inferred RAM/ROM bits (not FPGA resources)')
if __name__=='__main__':main()
