#!/usr/bin/env python3
"""Run riscv-arch-test ELF files through xsim simulation."""

import subprocess
import sys
import os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

PROJECT_DIR = Path(r"C:\Users\teruc\Desktop\programs\vivado\rv32imafc")
SRC_DIR = PROJECT_DIR / "rv32imafc.src" / "sources_1"
HEX_FILE = SRC_DIR / "test_prog.hex"
ELF_DIR = PROJECT_DIR / "riscv-arch-test" / "work" / "rv32imafc_sim" / "elfs"
XSIM_DIR = PROJECT_DIR / "rv32imafc.sim" / "sim_1" / "behav" / "xsim"

RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"

VIVADO_BIN = Path(r"E:\AMDDesignTools\2025.2.1\Vivado\bin")
XVLOG = str(VIVADO_BIN / "xvlog.bat")
XELAB = str(VIVADO_BIN / "xelab.bat")
XSIM  = str(VIVADO_BIN / "xsim.bat")

SV_SOURCES = [
    "top.sv", "ex.sv", "id.sv", "if.sv", "mem.sv",
    "wb.sv", "csr.sv", "reg.sv", "alu.sv",
    "unified_bram.sv", "tb.sv"
]

def win_to_wsl(path: Path) -> str:
    """Convert a Windows path to a WSL /mnt/ path."""
    s = str(path)
    if len(s) >= 2 and s[1] == ":":
        return f"/mnt/{s[0].lower()}{s[2:].replace('\\', '/')}"
    return s.replace("\\", "/")

def elf_to_hex(elf_path: Path) -> str:
    """Convert RISC-V ELF to hex using WSL objcopy."""
    tmp_bin = XSIM_DIR / f"_{elf_path.stem}.bin"
    result = subprocess.run([
        "wsl", "riscv64-unknown-elf-objcopy", "-O", "binary",
        win_to_wsl(elf_path), win_to_wsl(tmp_bin)
    ], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"objcopy failed:\n{result.stderr}")
    bin_data = tmp_bin.read_bytes()
    tmp_bin.unlink(missing_ok=True)
    lines = []
    for i in range(0, len(bin_data), 4):
        chunk = bin_data[i:i+4]
        if len(chunk) < 4:
            chunk = chunk + b'\x00' * (4 - len(chunk))
        word = int.from_bytes(chunk, 'little')
        lines.append(f"{word:08x}")
    return "\n".join(lines) + "\n"

def compile_design() -> bool:
    """Run xvlog and xelab to compile the design."""
    src_files = [str(SRC_DIR / s) for s in SV_SOURCES]
    try:
        subprocess.run([XVLOG, "-sv", *src_files],
            cwd=str(XSIM_DIR), check=True, capture_output=True, timeout=120)
        subprocess.run([XELAB, "work.tb"],
            cwd=str(XSIM_DIR), check=True, capture_output=True, timeout=120)
        return True
    except subprocess.CalledProcessError as e:
        err = e.stderr.decode() if isinstance(e.stderr, bytes) else str(e.stderr)
        print(f"  {RED}Compile failed:{RESET}\n{err[:500]}")
        return False
    except FileNotFoundError as e:
        print(f"  {RED}{e}{RESET}")
        return False

def run_xsim(timeout: int = 120) -> tuple[bool, str]:
    """Run xsim simulation and return (ebreak_reached, output)."""
    try:
        result = subprocess.run(
            [XSIM, "work.tb", "--runall"],
            cwd=str(XSIM_DIR),
            capture_output=True, text=True, timeout=timeout)
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except FileNotFoundError:
        return False, "xsim not found"
    
    ebreak = "eBREAK" in output or "ebreak" in output.lower()
    return ebreak, output

def run_single_test(elf_path: Path) -> tuple[str, bool, str]:
    """Run one test. Returns (name, passed, detail)."""
    name = elf_path.stem
    try:
        hex_data = elf_to_hex(elf_path)
        HEX_FILE.write_text(hex_data)
        # xsim runs from XSIM_DIR, so copy hex there too for $readmemh
        (XSIM_DIR / "test_prog.hex").write_text(hex_data)
    except Exception as e:
        return name, False, f"hex conversion error: {e}"
    
    ebreak_reached, output = run_xsim()
    if ebreak_reached:
        return name, True, ""
    elif output == "TIMEOUT":
        return name, False, "TIMEOUT"
    else:
        lines = output.strip().splitlines()
        tail = "\n".join(lines[-5:]) if lines else "(empty)"
        return name, False, f"No eBREAK\n---tail---\n{tail}"

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Run riscv-arch-test ELFs through xsim")
    parser.add_argument("--ext", default="rv32i/I", help="Test subdirectory (default: rv32i/I)")
    parser.add_argument("-j", "--jobs", type=int, default=4, help="Parallel jobs")
    parser.add_argument("--recompile", action="store_true", help="Recompile before tests")
    parser.add_argument("--test", help="Run a single test by name (e.g. I-add-00)")
    args = parser.parse_args()
    
    elf_dir = ELF_DIR / args.ext
    if not elf_dir.exists():
        print(f"ELF directory not found: {elf_dir}")
        sys.exit(1)
    
    if args.test:
        elf_files = [elf_dir / f"{args.test}.elf"]
    else:
        elf_files = sorted(elf_dir.glob("*.elf"))
    
    if not elf_files:
        print(f"No .elf files found in {elf_dir}")
        sys.exit(1)
    
    print(f"Found {len(elf_files)} test(s) in {elf_dir}")
    
    if args.recompile:
        print("Compiling design...")
        if not compile_design():
            sys.exit(1)
    
    passed = 0
    failed = 0
    results = []
    
    # Serial execution for reliability
    for ef in elf_files:
        name, ok, detail = run_single_test(ef)
        results.append((name, ok))
        if ok:
            passed += 1
            msg = f"  {GREEN}PASS{RESET}  {name}"
        else:
            failed += 1
            msg = f"  {RED}FAIL{RESET}  {name}\n    {detail}"
        print(msg)
    
    total = len(elf_files)
    print(f"\n{'='*50}")
    if failed == 0:
        print(f"{GREEN}All {total} tests PASSED{RESET}")
    else:
        print(f"{RED}{failed} failed, {passed} passed out of {total} tests{RESET}")
    
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
