"""Build six reproducible bare-metal ROM images with the existing assembler.

Generated assembly is saved under examples/soc for review. No new instructions.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1];TARGET=ROOT/'target';EXT='.exe' if os.name=='nt' else ''
def assemble(source,dest):
    subprocess.run([str(TARGET/('ringisa-as'+EXT)),str(source),str(dest)],cwd=ROOT,check=True)
def main():
    subprocess.run([sys.executable,'tools/specgen/soc.py'],cwd=ROOT,check=True)
    spec=json.loads((ROOT/'spec/soc.json').read_text());regions={r['name']:r for r in spec['regions']}
    ram=regions['RAM']['base'];uart=regions['UART']['base'];timer=regions['TIMER']['base'];irq=regions['IRQ']['base']
    folder=ROOT/'examples/soc';folder.mkdir(exist_ok=True);out=TARGET/'soc';out.mkdir(exist_ok=True)
    prologue=f'; Generated reproducibly by scripts/boot.py from spec/soc.json\nCONST128 R62,0x{ram+regions["RAM"]["size"]:x}\nCONST128 R10,0x{ram:x}\nCONST128 R11,0x{uart:x}\nCONST128 R12,0x{timer:x}\nCONST128 R13,0x{irq:x}\n'
    memory='MOVI R20,305419896\nST.32 R20,R10,0\nLD.U32 R21,R10,0\nBNE R20,R21,fail\nCONST256 R22,0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\nCONST128 R23,0x10ffa\nST.256 R22,R23,0\nLD.256 R24,R23,0\nBNE R22,R24,fail\n'
    uart_code='MOVI R1,4\nST.32 R1,R11,16\nMOVI R3,1\n'
    for i,byte in enumerate(b'RingISA SoC boot OK\n'):
        uart_code+=f'uart_wait_{i}: LD.U32 R2,R11,8\nAND.32 R2,R2,R3\nBEQ R2,R0,uart_wait_{i}\nMOVI R1,{byte}\nST.32 R1,R11,0\n'
    uart_code+='uart_drain: LD.U32 R2,R11,8\nAND.32 R2,R2,R3\nBEQ R2,R0,uart_drain\n'
    polling='ST.32 R0,R12,0\nMOVI R1,100\nST.32 R1,R12,4\nMOVI R1,1\nST.32 R1,R12,8\npoll: LD.U32 R2,R12,12\nBEQ R2,R0,poll\nST.32 R0,R12,8\nST.32 R1,R12,12\nST.32 R1,R13,8\n'
    interrupt='MOVI R30,0\nMOVI R1,4096\nCSRW R1,3\nMOVI R1,1\nST.32 R1,R13,4\nCSRW R1,7\nCSRW R1,4\nST.32 R0,R12,0\nMOVI R2,500\nST.32 R2,R12,4\nST.32 R1,R12,8\nirq_wait: BEQ R30,R0,irq_wait\nCSRW R0,4\nLD.U32 R2,R10,4\nMOVI R3,14\nBNE R2,R3,fail\n'
    handler='; Machine interrupt handler, only R40/R41 and R30/R31 modified.\nCSRR R31,1\nMOVI R40,0\nST.32 R40,R12,8\nMOVI R40,1\nST.32 R40,R12,12\nST.32 R40,R13,8\nADDI R30,R30,1\nST.32 R31,R10,4\nERET\n'
    finish='MOVI R60,24589\nST.32 R60,R10,32\nWFI\nfail: MOVI R60,-1\nST.32 R60,R10,32\nWFI\n'
    programs={'rom_boot':'','ram_test':memory,'uart_test':uart_code,'timer_poll':polling,'timer_interrupt':interrupt,'combined':memory+uart_code+polling+interrupt}
    handler_source=folder/'interrupt_handler.s';handler_binary=out/'interrupt_handler.bin'
    handler_source.write_text(handler,newline='\n');assemble(handler_source,handler_binary)
    manifest={}
    for name,body in programs.items():
        source=folder/(name+'.s');binary=out/(name+'.bin');source.write_text(prologue+body+finish,newline='\n');assemble(source,binary)
        length=binary.stat().st_size
        if length>4096:raise ValueError('boot code overlaps trap vector')
        data=binary.read_bytes()+bytes(4096-length)+handler_binary.read_bytes()
        binary.write_bytes(data)
        if len(data)>regions['ROM']['size']:raise ValueError('ROM overflow')
        data+=bytes(regions['ROM']['size']-len(data));(out/(name+'.hex')).write_text('\n'.join(f'{b:02x}' for b in data)+'\n',newline='\n')
        manifest[name]={'uart':name in ('uart_test','combined'),'interrupt':name in ('timer_interrupt','combined'),'memory':name in ('ram_test','combined')}
    # Real native128-bit instruction fetch and data access through15 table levels.
    va=0xffff0123456789ab0000000000000000
    page_setup=prologue+'MOVI R1,4096\nCSRW R1,3\n'
    for level in range(14,0,-1):
        index=(va>>(12+8*level))&(15 if level==14 else 255)
        table=ram+(14-level)*4096;next_table=table+4096
        page_setup+=f'CONST128 R4,0x{table+index*16:x}\nCONST128 R5,0x{((next_table>>12)<<44)|3:x}\nST.128 R5,R4,0\n'
    leaf=ram+14*4096+((va>>12)&255)*16
    for i,physical in enumerate([8192,131072]):
        page_setup+=f'CONST128 R4,0x{leaf+i*16:x}\nCONST128 R5,0x{((physical>>12)<<44)|0x19d:x}\nST.128 R5,R4,0\n'
    page_setup+=f'CONST128 R4,0x{leaf+32:x}\nST.128 R0,R4,0\n'
    page_setup+=f'MOVI R6,{ram+1}\nCSRW R6,5\nCONST128 R7,0x{va:x}\nCSRW R7,0\nMOVI R8,18\nCSRW R8,4\nERET\n'
    fault_handler='CSRR R28,1\nCSRR R40,0\nADDI R40,R40,4\nCSRW R40,0\nERET\n'
    for name,do_fault in [('high128_mmu',False),('high128_fault',True)]:
        source=folder/(name+'.s');binary=out/(name+'.bin');source.write_text(page_setup,newline='\n');assemble(source,binary)
        data=binary.read_bytes();data+=bytes(4096-len(data))
        hs=folder/(name+'-handler.s');hb=out/(name+'-handler.bin');hs.write_text(fault_handler,newline='\n');assemble(hs,hb);data+=hb.read_bytes();data+=bytes(8192-len(data))
        body=f'CONST128 R10,0x{va+4096:x}\nMOVI R20,305419896\nST.32 R20,R10,0\nLD.U32 R21,R10,0\nBNE R20,R21,fail\n'
        if do_fault:body+=f'CONST128 R25,0x{va+8192:x}\nLD.U8 R26,R25,0\nMOVI R27,7\nBNE R28,R27,fail\n'
        body+=finish;ps=folder/(name+'-payload.s');pb=out/(name+'-payload.bin');ps.write_text(body,newline='\n');assemble(ps,pb);data+=pb.read_bytes();binary.write_bytes(data)
        if len(data)>regions['ROM']['size']:raise ValueError('paged ROM overflow')
        data+=bytes(regions['ROM']['size']-len(data));(out/(name+'.hex')).write_text('\n'.join(f'{b:02x}' for b in data)+'\n',newline='\n')
        manifest[name]={'uart':False,'interrupt':False,'memory':False,'privilege':1,'signature':65568,'fault':7 if do_fault else 0}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Built eight RingISA bare-metal ROM programs, including native128 MMU/faults')
if __name__=='__main__':main()
