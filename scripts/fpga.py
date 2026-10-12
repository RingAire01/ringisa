"""ECP5 feasibility experiment, not a qualified board configuration.

--map attempts full SoC technology mapping; --pnr requires the generated mapped
netlist. A pinless experiment uses --lpf-allow-unconstrained and is NOT deployable.
"""
import argparse
import json
from rtl import ROOT,TARGET,find,run
def main():
    p=argparse.ArgumentParser();p.add_argument('--map',action='store_true');p.add_argument('--pnr',action='store_true');p.add_argument('--peripherals',action='store_true');args=p.parse_args()
    sources=sorted(str(f.relative_to(ROOT)).replace('\\','/') for f in (ROOT/'rtl').rglob('*.sv'))
    config=json.loads((ROOT/'fpga/ecp5/target.json').read_text());top='ringisa_peripherals' if args.peripherals else config['top'];name='peripherals' if args.peripherals else 'soc'
    if args.map:
        out=run([find('yosys'),'-Q','-T','-p',f'read_verilog -sv -Irtl/decode -Irtl/soc {" ".join(sources)}; synth_ecp5 -top {top} -json target/{name}-ecp5.json; check -assert; stat'],'fpga-'+name+'-mapping.log')
        print(out[-2500:]);print('PASS ECP5 technology mapping only; place/route not implied')
    if args.pnr:
        if args.peripherals:raise ValueError('PNR target is the complete SoC only')
        out=run([find('nextpnr-ecp5'),'--85k','--package',config['package'],'--speed',str(config['speed']),'--freq',str(config['clock_mhz']),'--json',TARGET/'soc-ecp5.json','--textcfg',TARGET/'soc-ecp5.config','--report',TARGET/'soc-ecp5-timing.json','--lpf-allow-unconstrained','--seed','52495341'],'fpga-soc-pnr.log')
        print(out[-2500:]);print('Pinless feasibility PNR completed; no board or hardware validation')
if __name__=='__main__':main()
