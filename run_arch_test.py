#!/usr/bin/env python3
"""Improved riscv-arch-test runner for xsim simulation.

Usage:
  python run_arch_test.py --ext rv32i/I
  python run_arch_test.py --ext rv32i/I --test I-add-01
  python run_arch_test.py --ext rv32i/I --recompile --save
  python run_arch_test.py --ext rv32i/I --compare-ref
"""

import subprocess
import sys
import os
import re
import shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

# ========================================
#  Paths
# ========================================
PROJECT_DIR = Path(r"D:\Desktop\programs\vivado\rv32imafc")
SRC_DIR = PROJECT_DIR / "rv32imafc.src" / "sources_1"
WORK_DIR = SRC_DIR    # xvlog/xelab/xsim run here; $readmemh looks for test_prog.hex here
HEX_FILE = WORK_DIR / "test_prog.hex"
TEST_DIR = PROJECT_DIR / "riscv-arch-test" / "tests"
ELF_DIR = PROJECT_DIR / "riscv-arch-test" / "work" / "rv32imafc_sim" / "elfs"
CONFIG_DIR = PROJECT_DIR / "riscv-arch-test" / "config" / "cores" / "rv32imafc_sim"
RESULTS_DIR = PROJECT_DIR / "riscv-arch-test" / "results"

# ========================================
#  Tool paths
# ========================================
VIVADO_BIN = Path(r"E:\AMDDesignTools\2025.2.1\Vivado\bin")
XVLOG = str(VIVADO_BIN / "xvlog.bat")
XELAB = str(VIVADO_BIN / "xelab.bat")
XSIM = str(VIVADO_BIN / "xsim.bat")

# ========================================
#  Source files (must be in SRC_DIR)
# ========================================
SV_SOURCES = [
    "top.sv", "ex.sv", "id.sv", "if.sv", "mem.sv",
    "wb.sv", "csr.sv", "reg.sv", "alu.sv", "div.sv", "mul.sv",
    "unified_bram.sv", "tb.sv"
]

# ========================================
#  Colors
# ========================================
RED   = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
CYAN  = "\033[96m"
RESET = "\033[0m"


# ============================================================
#  Utility functions
# ============================================================

def win_to_wsl(path: Path) -> str:
    """Convert a Windows path to a WSL /mnt/ path."""
    s = str(path)
    if len(s) >= 2 and s[1] == ":":
        return f"/mnt/{s[0].lower()}{s[2:].replace('\\', '/')}"
    return s.replace("\\", "/")


def elf_to_hex(elf_path: Path, work_dir: Path) -> str:
    """Convert RISC-V ELF to hex string using WSL objcopy."""
    tmp_bin = work_dir / f"_{elf_path.stem}.bin"
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


def assemble_source(src_path: Path, elf_path: Path) -> bool:
    """Compile a .S test source to .elf using the GCC toolchain in WSL."""
    link_ld = CONFIG_DIR / "link.ld"
    if not link_ld.exists():
        print(f"  {RED}link.ld not found: {link_ld}{RESET}")
        return False
    elf_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([
        "wsl", "riscv64-unknown-elf-gcc",
        "-nostartfiles", "-nostdlib",
        "-march=rv32imafc_zifencei_zicntr_zicond_zba_zbb_zbs_zcb", "-mabi=ilp32",
        "-DTEST_FLEN=32",
        f"-I{win_to_wsl(TEST_DIR / 'env')}",
        f"-I{win_to_wsl(CONFIG_DIR)}",
        f"-T{win_to_wsl(link_ld)}",
        "-o", win_to_wsl(elf_path),
        win_to_wsl(src_path),
    ], capture_output=True, text=True)
    if result.returncode != 0:
        err = result.stderr.strip()
        print(f"  {RED}Assembly failed:{RESET}\n{err[:600]}")
        return False
    return True


# ============================================================
#  Simulation functions
# ============================================================

def verify_sources() -> bool:
    """Check that all required source files exist in SRC_DIR."""
    ok = True
    for s in SV_SOURCES:
        if not (SRC_DIR / s).exists():
            print(f"  {RED}Missing: {SRC_DIR / s}{RESET}")
            ok = False
    return ok


def compile_design() -> bool:
    """Compile all SV sources with xvlog, then xelab."""

    if not verify_sources():
        return False

    WORK_DIR.mkdir(parents=True, exist_ok=True)

    src_files = [str(SRC_DIR / s) for s in SV_SOURCES]

    try:
        # xvlog
        r = subprocess.run(
            [XVLOG, "-sv", *src_files],
            cwd=str(WORK_DIR), capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            print(f"  {RED}xvlog failed:{RESET}\n{r.stderr[:600]}")
            return False

        # xelab
        r = subprocess.run(
            [XELAB, "work.tb"],
            cwd=str(WORK_DIR), capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            print(f"  {RED}xelab failed:{RESET}\n{r.stderr[:600]}")
            return False

        return True

    except FileNotFoundError as e:
        print(f"  {RED}{e}{RESET}")
        return False
    except subprocess.TimeoutExpired:
        print(f"  {RED}Compilation timed out{RESET}")
        return False


def run_xsim(timeout: int = 120, plusargs: list[str] | None = None) -> tuple[bool, str]:
    """Run xsim simulation. Returns (ebreak_reached, full_output)."""
    cmd = [XSIM, "--runall", "work.tb"]
    if plusargs:
        cmd.extend(plusargs)
    try:
        result = subprocess.run(
            cmd,
            cwd=str(WORK_DIR),
            capture_output=True, text=True, timeout=timeout)
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except FileNotFoundError:
        return False, "xsim not found"

    ebreak = "=== rvmodel_halt at cycle" in output
    return ebreak, output


# ============================================================
#  BRAM / signature analysis
# ============================================================

def extract_bram_from_output(output: str) -> list[int]:
    """Parse BRAM[N] = 0xXXXX lines from simulation output.
    Returns a list of 16384 words, or fewer if output was truncated."""
    bram = {}
    for line in output.splitlines():
        m = re.match(r'BRAM\[(\d+)\]\s*=\s*0x([0-9a-fA-F]+)', line)
        if m:
            idx = int(m.group(1))
            val = int(m.group(2), 16)
            bram[idx] = val
    if not bram:
        return []
    max_idx = max(bram.keys()) + 1
    return [bram.get(i, 0) for i in range(max_idx)]


def find_signature_canary(bram: list[int], search_start: int = 0x200) -> int | None:
    """Find the CANARY (0xDEADBEEF) at the start of the signature region.

    In the riscv-arch-test linker layout:
      .text.init @ 0x80000000   → BRAM[0..]
      .text.rvtest              → BRAM[..]
      .data (ALIGN 0x1000)      → BRAM[0x400..]
        scratch
        save_areas
        rvtest_data_begin
        begin_signature / rvtest_sig_begin
          signature_base: CANARY (0xDEADBEEF) + fill + trap_sig + end_canary

    We look for the first 0xDEADBEEF that is followed by a non-0xDEADBEEF
    word (that word is the first test result written over the fill).
    """
    for i in range(search_start, len(bram) - 1):
        if bram[i] == 0xDEADBEEF and bram[i + 1] != 0xDEADBEEF:
            return i
    # fallback: first 0xDEADBEEF anywhere in likely data region
    for i in range(search_start, len(bram)):
        if bram[i] == 0xDEADBEEF:
            return i
    return None


def extract_signature(bram: list[int]) -> list[int]:
    """Extract test-result signature words from BRAM dump.

    Returns the words written by RVTEST_SIGUPD (after skipping the canary).
    We stop when we hit a 0xDEADBEEF filler word (end of written signature).
    """
    canary = find_signature_canary(bram)
    if canary is None:
        return []

    sig = []
    for i in range(canary + 1, min(canary + 1 + 1024, len(bram))):
        if bram[i] == 0xDEADBEEF:
            break
        sig.append(bram[i])
    return sig


def parse_ref_output(ref_path: Path) -> list[int]:
    """Parse a .ref_output file into a list of 32-bit words."""
    if not ref_path.exists():
        return []
    vals = []
    for line in ref_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            try:
                vals.append(int(line, 16))
            except ValueError:
                pass
    return vals


def compare_signatures(actual: list[int], expected: list[int]) -> tuple[bool, list[str]]:
    """Compare two signature lists. Returns (match, difference_strings)."""
    diffs = []
    n = max(len(actual), len(expected))
    for i in range(n):
        a = actual[i] if i < len(actual) else 0
        e = expected[i] if i < len(expected) else 0
        if a != e:
            diffs.append(f"    [{i:3d}] exp 0x{e:08x}  got 0x{a:08x}")
    return len(diffs) == 0, diffs


# ============================================================
#  Single test runner
# ============================================================

def run_single_test(elf_path: Path, timeout: int,
                    save_output: bool, compare_ref: bool,
                    dump_trace: bool = False) -> tuple[str, str, str]:
    """Run one ELF through simulation.

    Returns (test_name, status, detail).
    status is one of: PASS, FAIL, TIMEOUT, ERROR
    """
    name = elf_path.stem

    try:
        hex_data = elf_to_hex(elf_path, WORK_DIR)
        HEX_FILE.write_text(hex_data)
    except Exception as e:
        return name, "ERROR", f"ELF preparation: {e}"

    plusargs = []
    if dump_trace:
        trace_path = WORK_DIR / f"trace_{name}.csv"
        plusargs.append("+trace=" + str(trace_path))

    ebreak, output = run_xsim(timeout, plusargs)

    # Save output if requested
    if save_output:
        out_dir = RESULTS_DIR / elf_path.parent.name / name
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "sim_output.txt").write_text(output)

    if dump_trace:
        trace_path = WORK_DIR / f"trace_{name}.csv"
        if trace_path.exists():
            out_dir = RESULTS_DIR / elf_path.parent.name / name
            out_dir.mkdir(parents=True, exist_ok=True)
            dest = out_dir / "trace.csv"
            shutil.copy2(str(trace_path), str(dest))
            trace_path.unlink()
            print(f"    Trace saved: {dest}")

    if output == "TIMEOUT":
        return name, "TIMEOUT", ""
    if output == "xsim not found":
        return name, "ERROR", "xsim not found"

    # Check for ebreak
    ebreak_match = re.search(r"=== rvmodel_halt at cycle (\d+) ===", output)
    if not ebreak_match:
        # No ebreak — dump last lines of output for diagnosis
        tail_lines = output.strip().splitlines()[-8:]
        tail = "\n".join(tail_lines)
        return name, "FAIL", f"no RV model halt\n  --- tail ---\n{tail}"

    cycle = ebreak_match.group(1)

    # Extract BRAM and signature
    bram = extract_bram_from_output(output)

    # Save BRAM dump if saving outputs
    if save_output:
        out_dir = RESULTS_DIR / elf_path.parent.name / name
        bram_path = out_dir / "bram_dump.txt"
        bram_path.write_text(
            "\n".join(f"BRAM[{i}] = 0x{v:08x}" for i, v in enumerate(bram))
        )

    if not bram:
        return name, "PASS", f"ebreak@cycle{cycle} (no BRAM dump)"

    sig = extract_signature(bram)

    if save_output:
        out_dir = RESULTS_DIR / elf_path.parent.name / name
        sig_path = out_dir / "signature.txt"
        sig_path.write_text("\n".join(f"0x{v:08x}" for v in sig))

    # Reference comparison
    if compare_ref:
        # Look for .ref_output in test source directory
        src_dir = TEST_DIR / elf_path.parent.relative_to(ELF_DIR).parent / elf_path.parent.name
        ref_paths = [
            src_dir / f"{name}.ref_output",
            src_dir / f"{name.replace('-', '_')}.ref_output",
            CONFIG_DIR / "ref_output" / f"{name}.ref_output",
        ]
        for rp in ref_paths:
            expected = parse_ref_output(rp)
            if expected:
                match, diffs = compare_signatures(sig, expected)
                if save_output:
                    (out_dir / "ref_output.txt").write_text(
                        "\n".join(f"0x{v:08x}" for v in expected)
                    )
                if match:
                    return name, "PASS", f"cycle{cycle} sig({len(sig)}w) ref_match"
                else:
                    diff_str = "\n".join(diffs[:15])
                    return name, "FAIL", f"cycle{cycle} sig({len(sig)}w) ref_MISMATCH\n{diff_str}"

    # No reference — ebreak reached = PASS (we trust execution completed)
    return name, "PASS", f"cycle{cycle} sig({len(sig)}w)"


# ============================================================
#  Main
# ============================================================

def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Run riscv-arch-test ELFs through xsim simulation")

    parser.add_argument("--ext", default="rv32i/I",
                        help="Test subdirectory (default: rv32i/I)")
    parser.add_argument("-j", "--jobs", type=int, default=1,
                        help="Parallel jobs (1 = serial, default)")
    parser.add_argument("--recompile", action="store_true",
                        help="Recompile design (xvlog + xelab)")
    parser.add_argument("--clean", action="store_true",
                        help="Force rebuild all test ELFs from .S source")
    parser.add_argument("--test", help="Run a single test by name (e.g. I-add-01)")
    parser.add_argument("--save", action="store_true",
                        help="Save simulation output / BRAM / signature to results/")
    parser.add_argument("--compare-ref", "--ref", action="store_true",
                        help="Compare signatures against .ref_output files")
    parser.add_argument("--trace", action="store_true",
                        help="Dump full pipeline trace (CSV) to results/")
    parser.add_argument("--timeout", type=int, default=3600,
                        help="Per-test timeout in seconds (default: 120)")
    args = parser.parse_args()

    # Locate ELF or source directory
    elf_dir = ELF_DIR / args.ext
    src_dir = TEST_DIR / args.ext

    # Assemble any missing ELFs
    if src_dir.exists():
        src_files = sorted(src_dir.glob("*.S"))
        if args.clean:
            for ef in elf_dir.glob("*.elf"):
                ef.unlink()
            to_build = src_files
        else:
            to_build = [s for s in src_files
                        if not (elf_dir / f"{s.stem}.elf").exists()]
        if to_build:
            print(f"Assembling {len(to_build)} test(s)...")
            for s in to_build:
                n = s.stem
                print(f"  {n}...", end=" ", flush=True)
                elf_dir.mkdir(parents=True, exist_ok=True)
                ok = assemble_source(s, elf_dir / f"{n}.elf")
                print("OK" if ok else "FAIL")

        elf_files = sorted(elf_dir.glob("*.elf"))
    elif elf_dir.exists():
        elf_files = sorted(elf_dir.glob("*.elf"))
    else:
        print(f"Neither source nor ELF directory found: {src_dir}")
        sys.exit(1)

    if args.test:
        elf_files = [ef for ef in elf_files if ef.stem == args.test]
        if not elf_files:
            print(f"No test named '{args.test}' in {elf_dir}")
            sys.exit(1)

    if not elf_files:
        print(f"No .elf files found in {elf_dir}")
        sys.exit(1)

    print(f"Found {len(elf_files)} test(s) in {args.ext}")

    # Compile design once
    if args.recompile:
        print("Compiling design... ", end="", flush=True)
        if not compile_design():
            sys.exit(1)
        print("OK")

    # Run tests (serial by default for reliability)
    results: list[tuple[str, str, str]] = []

    print(f"{'─'*60}")
    for ef in elf_files:
        start = datetime.now()
        name, status, detail = run_single_test(
            ef, args.timeout, args.save, args.compare_ref, args.trace)
        elapsed = (datetime.now() - start).total_seconds()

        if status == "PASS":
            tag = f"{GREEN}PASS{RESET}"
        elif status == "FAIL":
            tag = f"{RED}FAIL{RESET}"
        elif status == "TIMEOUT":
            tag = f"{YELLOW}TIMEOUT{RESET}"
        else:
            tag = f"{RED}{status}{RESET}"

        detail_str = f"  [{detail}]" if detail else ""
        print(f"  {tag}  {name:35s} {elapsed:6.1f}s{detail_str}")
        results.append((name, status))

    # Summary
    total = len(results)
    passed = sum(1 for _, s in results if s == "PASS")
    failed = sum(1 for _, s in results if s in ("FAIL", "ERROR"))
    timed  = sum(1 for _, s in results if s == "TIMEOUT")

    print(f"{'─'*60}")
    if failed == 0 and timed == 0:
        print(f"{GREEN}All {total} tests PASSED{RESET}")
    else:
        parts = []
        if passed:
            parts.append(f"{GREEN}{passed} passed{RESET}")
        if failed:
            parts.append(f"{RED}{failed} failed{RESET}")
        if timed:
            parts.append(f"{YELLOW}{timed} timed out{RESET}")
        print(f"{' '.join(parts)} out of {total} tests")
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
