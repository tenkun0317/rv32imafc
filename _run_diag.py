#!/usr/bin/env python3
import sys, subprocess
sys.path.insert(0, r'D:\Desktop\programs\vivado\rv32imafc')
from run_arch_test import *

print('Recompiling...')
compile_design()

elf_path = ELF_DIR / 'rv32i' / 'I' / 'I-beq-00.elf'
hex_data = elf_to_hex(elf_path, WORK_DIR)
HEX_FILE.write_text(hex_data)
print(f'Hex: {len(hex_data)} chars')

cmd = [XSIM, '--runall', 'work.tb']
result = subprocess.run(cmd, cwd=str(WORK_DIR), capture_output=True, text=True, timeout=40)
output = result.stdout + result.stderr
keywords = ['TRAP', 'TIMEOUT', 'BRAM', 'halt', '===', 'trap[']
for l in output.strip().splitlines():
    if any(kw in l for kw in keywords):
        print(l)
