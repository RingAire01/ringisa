"""Run clang static analysis on project C sources; emit diagnostics to target."""
from pathlib import Path
import os
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def main():
    target=ROOT/'target/analysis';target.mkdir(parents=True,exist_ok=True)
    count=0
    sources=list((ROOT/'tools').rglob('*.c'))+list((ROOT/'tests/soc').rglob('*.c'))
    for source in sorted(sources):
        output=target/(str(source.relative_to(ROOT)).replace('\\','_').replace('/','_')+'.plist')
        result=subprocess.run([os.environ.get('CLANG','clang'),'--analyze','-std=c11','-Wall','-Wextra','-Wpedantic','-Werror',str(source),'-o',str(output)],cwd=ROOT,capture_output=True,text=True)
        if result.returncode or result.stderr:raise RuntimeError(result.stdout+result.stderr)
        count+=1
    print(f'PASS clang static analysis: {count} translation units, no diagnostics')
if __name__=='__main__':main()
