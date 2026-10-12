"""Tool round trips and randomized scalar checks with an independent Python oracle."""
from pathlib import Path
import json
import os
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1]
TARGET=ROOT/'target';EXT='.exe' if os.name=='nt' else ''
def tool(name,*args):
    return subprocess.run([str(TARGET/('ringisa-'+name+EXT)),*map(str,args)],cwd=ROOT,check=True,capture_output=True,text=True).stdout
def roundtrip(source,name):
    s=TARGET/(name+'.s');b=TARGET/(name+'.bin');d=TARGET/(name+'.dis.s');b2=TARGET/(name+'.round.bin')
    s.write_text(source);tool('as',s,b);d.write_text(tool('dis',b));tool('as',d,b2);assert b.read_bytes()==b2.read_bytes()
    return b
def main():
    rng=random.Random(0x52494e47)
    spec=json.loads((ROOT/'spec/isa.json').read_text())
    source=[]
    for ins in spec['instructions']:
        name=ins['name'];op=ins['op']
        if ins['format']=='R':
            for width in spec['scalar_widths'] if ins['family']=='scalar' else spec['simd_widths']:
                source.append(f'{name}.{width} R63,R62,R61')
        elif name=='CHUNK':source.append('CHUNK R63,7,0xffffffff')
        elif name in ('ERET','WFI','FENCE','TLBI'):source.append(name)
        elif name in ('SVC','BRK'):source += [f'{name} 511',f'{name}.X 512']
        elif name in ('CSRR','CSRW'):source.append(f'{name} R63,8')
        elif name=='MOVI':source += ['MOVI R63,-512','MOVI.X R63,-2199023255552']
        else:source += [f'{name} R63,R62,-512',f'{name}.X R63,R62,2199023255551']
    roundtrip('\n'.join(source),'all-opcodes')
    roundtrip('MOVI R1,1\nBEQ R1,R1,end\nMOVI R2,99\nend: WFI\n','labels')
    binary=TARGET/'invalid.bin';binary.write_bytes(rng.randbytes(4000));(TARGET/'invalid.s').write_text(tool('dis',binary));tool('as',TARGET/'invalid.s',TARGET/'invalid.round.bin');assert binary.read_bytes()==(TARGET/'invalid.round.bin').read_bytes()
    masks={bits:(1<<bits)-1 for bits in (8,16,32,64,128,256)}
    count=0
    for trial in range(12):
        lines=[];expected={};reg=3
        for _ in range(15):
            bits=rng.choice(list(masks));a=rng.getrandbits(256);b=rng.getrandbits(256);op=rng.choice(['ADD','SUB','AND','OR','XOR','MUL','SHL','SHR','SAR','SLTU','SLTS']);mask=masks[bits];x=a&mask;y=b&mask
            lines += [f'CONST256 R1,0x{a:x}',f'CONST256 R2,0x{b:x}',f'{op}.{bits} R{reg},R1,R2']
            signed=lambda v:v-(1<<bits) if v>>(bits-1) else v
            shift=b&(bits-1)
            result={'ADD':lambda:x+y,'SUB':lambda:x-y,'AND':lambda:x&y,'OR':lambda:x|y,'XOR':lambda:x^y,'MUL':lambda:x*y,'SHL':lambda:x<<shift,'SHR':lambda:x>>shift,'SAR':lambda:signed(x)>>shift,'SLTU':lambda:int(x<y),'SLTS':lambda:int(signed(x)<signed(y))}[op]()
            result&=mask
            if op=='SAR' and result>>(bits-1):result|=((1<<256)-1)^mask
            expected[reg]=result;reg+=1;count+=1
        lines.append('WFI');binary=roundtrip('\n'.join(lines),f'random-{trial}');output=tool('sim',binary,'--inspect')
        actual={int(line.split('=')[0][1:]):int(line.split('=')[1],16) for line in output.splitlines() if line.startswith('R')}
        assert all(actual[r]==value for r,value in expected.items()),(trial,expected,actual)
    binary=roundtrip((ROOT/'examples/arithmetic.s').read_text(),'example');tool('sim',binary,'--trace','--inspect')
    result=subprocess.run([str(TARGET/('ringisa-sim'+EXT)),str(binary),'--debug'],cwd=ROOT,input='step 1\nregs\npmem 0 4\npc\nquit\n',capture_output=True,text=True,check=True)
    assert 'R1=0x'+('0'*56)+'ffffffff' in result.stdout and 'PC=0x00000000000000000000000000000008' in result.stdout,result.stdout
    print(f'PASS all opcode round trips, invalid binary round trip, labels, {count} randomized ALU oracle cases, example')
if __name__=='__main__':main()
