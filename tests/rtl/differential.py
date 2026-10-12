"""Executable C-versus-SystemVerilog final-state differential regressions."""
from pathlib import Path
import os
import random
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2];TARGET=ROOT/'target';EXT='.exe' if os.name=='nt' else ''
def call(args):return subprocess.run(list(map(str,args)),cwd=ROOT,check=True,capture_output=True,text=True).stdout
def state(output):
    return {name:int(value,16) for name,value in re.findall(r'^(R\d+|CSR\d+)=(0x[0-9a-fA-F]+)$',output,re.M)}
def test(source,name,vvp,image_patch=None,handle=False):
    s=TARGET/(name+'.s');b=TARGET/(name+'.bin');s.write_text(source)
    call([TARGET/('ringisa-as'+EXT),s,b]);data=bytearray(b.read_bytes());data+=bytes(1048576-len(data))
    if image_patch:image_patch(data)
    b.write_bytes(data);h=TARGET/(name+'.hex');h.write_text('\n'.join(f'{x:02x}' for x in data)+'\n')
    c=call([TARGET/('ringisa-sim'+EXT),b,'--inspect',*(['--handle-traps'] if handle else [])])
    rtl=call([vvp,TARGET/'core_tb.vvp',f'+image={h}',f'+size={len(data)}'])
    (TARGET/(name+'.rtl.log')).write_text(rtl);(TARGET/(name+'.c.log')).write_text(c)
    expected,actual=state(c),state(rtl)
    assert len(expected)==73 and len(actual)==73,(name,len(expected),len(actual))
    assert expected==actual,(name,{k:(expected[k],actual[k]) for k in expected if expected[k]!=actual[k]})
    cm=re.search(r'^MEM=(\w+)$',c,re.M);rm=re.search(r'^MEM=(\w+)$',rtl,re.M)
    assert cm and rm and cm[1].lower()==rm[1].lower(),(name,'memory mismatch')
    cp=re.search(r'pc=([0-9a-f]+)',c);rp=re.search(r'FINAL pc=([0-9a-f]+)',rtl)
    assert cp[1]==rp[1],(name,'PC mismatch',cp[1],rp[1])
    print('PASS differential',name,flush=True)
def main():
    vvp=sys.argv[1];rng=random.Random(0x52495341)
    test((ROOT/'examples/arithmetic.s').read_text(),'rtl-example',vvp)
    lines=[]
    for r in range(1,64):lines.append(f'MOVI R{r},{r*3}')
    lines+=['MOVI R0,99','MOVI R5,0','BEQ R0,R5,skip','MOVI R3,99','skip: ADDI R4,R4,999','JAL R63,R0,subroutine','WFI','subroutine: ADDI R7,R7,4','JAL R0,R63,0']
    test('\n'.join(lines),'rtl-registers-branches',vvp)
    for trial in range(3):
        lines=[]
        for n in range(24):
            a=rng.getrandbits(256);b=rng.getrandbits(256);simd=n%3==0;op=rng.choice(['VADD','VSUB','VAND','VOR','VXOR','VMUL','VEQ'] if simd else ['ADD','SUB','AND','OR','XOR','SHL','SHR','SAR','SLTU','SLTS','MUL']);width=rng.choice([8,16,32,64] if simd else [8,16,32,64,128,256]);r=3+n
            lines += [f'CONST256 R1,0x{a:x}',f'CONST256 R2,0x{b:x}',f'{op}.{width} R{r},R1,R2']
        lines+=['CONST128 R50,0x80000','ST.256 R26,R50,0','LD.256 R51,R50,0','ST.8 R1,R50,31','LD.S8 R52,R50,31','WFI']
        test('\n'.join(lines),f'rtl-random-{trial}',vvp)
    test('MOVI R1,256\nCSRW R1,3\nSVC 7\nWFI\n'+('FENCE\n'*60)+'CSRR R2,0\nADDI R2,R2,4\nCSRW R2,0\nERET\n','rtl-trap-return',vvp,handle=True)
    # Enter S at high128 VA using EPC/STATUS/ERET and native15-level tables.
    va=0xffff0123456789abfedcba9876543000
    bootstrap=f'CONST128 R1,0x{va:x}\nCSRW R1,0\nMOVI R2,18\nCSRW R2,4\nMOVI R3,65537\nCSRW R3,5\nERET\n'
    program='CONST128 R10,0x'+f'{va+4090:x}'+'\nCONST256 R11,0x123456789abcdef\nST.256 R11,R10,0\nLD.256 R12,R10,0\nWFI\n'
    ps=TARGET/'high-program.s';pb=TARGET/'high-program.bin';ps.write_text(program);call([TARGET/('ringisa-as'+EXT),ps,pb]);highcode=pb.read_bytes()
    def patch(data):
        for level in range(14,0,-1):
            index=(va>>(12+8*level))&(15 if level==14 else 255);table=0x10000+(14-level)*4096;next_table=table+4096
            pte=((next_table>>12)<<44)|3;data[table+index*16:table+index*16+16]=pte.to_bytes(16,'little')
        leaf=0x10000+14*4096+((va>>12)&255)*16
        for i,physical in enumerate([0x40000,0x80000]):data[leaf+i*16:leaf+i*16+16]=(((physical>>12)<<44)|0x19d).to_bytes(16,'little')
        data[0x40000:0x40000+len(highcode)]=highcode
    test(bootstrap,'rtl-high128-paging',vvp,patch)
    loads=['LD.U8','LD.U16','LD.U32','LD.U64','LD.U128','LD.S8','LD.S16','LD.S32','LD.S64','LD.S128','LD.256']
    lines=['CONST256 R1,0x'+('80'*32),'CONST128 R2,0x80000','ST.256 R1,R2,0']
    for i,name in enumerate(loads):lines.append(f'{name} R{i+3},R2,0')
    for i,width in enumerate([8,16,32,64,128,256]):lines += [f'ST.{width} R1,R2,{32+i*32}',f'LD.U8 R{i+20},R2,{32+i*32}']
    lines+=['CONST256 R40,0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff','MOVI R41,1','ADD.256 R42,R40,R41','SUB.256 R43,R0,R41','SHL.256 R44,R41,R40','SAR.128 R45,R40,R41','MOVI R46,9','BNE R0,R41,next','MOVI R46,0','next: BLTU R41,R40,next2','MOVI R46,0','next2: BLTS R40,R41,next3','MOVI R46,0','next3: FENCE','TLBI','WFI']
    test('\n'.join(lines),'rtl-widths-memory-carry',vvp)
    handler='CSRR R2,0\nCSRR R3,1\nCSRR R4,2\nADDI R2,R2,4\nCSRW R2,0\nERET\n'
    def with_handler(main,handler):
        # Force handler to physical256 using assembler-measured lengths.
        path=TARGET/'handler-layout.s';out=TARGET/'handler-layout.bin';path.write_text(main);call([TARGET/('ringisa-as'+EXT),path,out]);length=out.stat().st_size
        assert length<=256 and length%4==0
        return main+'FENCE\n'*((256-length)//4)+handler
    test(with_handler('MOVI R1,256\nCSRW R1,3\n.word 0xffffffff\nWFI\n',handler),'rtl-illegal',vvp,handle=True)
    test(with_handler('MOVI R1,256\nCSRW R1,3\nCONST128 R10,0xffffffffffffffffffffffffffffffff\nLD.U8 R11,R10,1\nWFI\n',handler),'rtl-address-overflow',vvp,handle=True)
    test(with_handler('MOVI R1,256\nCSRW R1,3\nMOVI R10,1048575\nST.256 R1,R10,0\nWFI\n',handler),'rtl-physical-atomic-fault',vvp,handle=True)
    irq_handler='CSRR R2,0\nCSRW R0,8\nERET\n'
    test(with_handler('MOVI R1,256\nCSRW R1,3\nMOVI R5,1\nCSRW R5,7\nCSRW R5,8\nCSRW R5,4\nWFI\n',irq_handler),'rtl-interrupt-return',vvp,handle=True)
    # Faulting cross-page store/load must preserve destinations and the first
    # page's bytes. M-mode handler advances EPC using full128-bit arithmetic.
    fault_boot='MOVI R60,256\nCSRW R60,3\n'+bootstrap
    fault_boot=with_handler(fault_boot,handler)
    def fault_patch(data):
        patch(data);leaf=0x10000+14*4096+((va>>12)&255)*16;data[leaf+16:leaf+32]=bytes(16)
    test(fault_boot,'rtl-high128-page-fault',vvp,fault_patch,handle=True)
    def device_patch(data):
        patch(data);leaf=0x10000+14*4096+((va>>12)&255)*16
        data[leaf:leaf+16]=(((0x40000>>12)<<44)|0x1000|0x19d).to_bytes(16,'little')
    test(fault_boot,'rtl-device-alignment',vvp,device_patch,handle=True)
    test('MOVI R1,7\nMOVI R2,1\nloop: SUB.256 R1,R1,R2\nBNE R1,R0,loop\nCONST128 R10,0x80020\nMOVI R11,42\nST.256 R11,R10,-32\nLD.256 R12,R10,-32\nWFI\n','rtl-negative-offset-loop',vvp)
    test(with_handler('MOVI R1,256\nCSRW R1,3\nLD.U8 R11,R0,-1\nWFI\n',handler),'rtl-address-underflow',vvp,handle=True)
    print('PASS 16 core differential programs (73 register/CSR values, PC, memory), including 72 random ALU/SIMD operations, all memory widths, carry/borrow, negative address/branch offsets, traps, interrupts, native128 paging/faults and device alignment; randomized bus stalls')
if __name__=='__main__':main()
