"""Apply the standard C formatter; generated decoder metadata is excluded."""
from pathlib import Path
import os
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def main():
    sources=[p for folder in ('tools','tests') for p in (ROOT/folder).rglob('*') if p.suffix in ('.c','.h') and p.name not in ('generated.c','generated.h')]
    subprocess.run([os.environ.get('CLANG_FORMAT','clang-format'),'-i',*map(str,sorted(sources))],cwd=ROOT,check=True)
    print(f'Formatted {len(sources)} C source/header files')
if __name__=='__main__':main()
