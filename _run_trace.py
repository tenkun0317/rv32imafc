#!/usr/bin/env python3
import sys
sys.path.insert(0, r'D:\Desktop\programs\vivado\rv32imac')
from run_arch_test import *

print("Recompiling design...")
if not compile_design():
    print("Compilation failed!")
    sys.exit(1)

elf_path = ELF_DIR / 'rv32i' / 'I' / 'I-beq-00.elf'
name, status, detail = run_single_test(elf_path, timeout=120, save_output=False, compare_ref=False, dump_trace=True)
print(f"Status: {status}")
d = detail[:2000] if detail else "(empty)"
print(f"Detail: {d}")
