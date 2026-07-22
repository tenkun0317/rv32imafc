#!/usr/bin/env python3
"""Analyze RISC-V core pipeline trace CSV.

Usage:
  python analyze_trace.py trace.csv
  python analyze_trace.py trace.csv --verbose
"""

import sys
import csv
import re

REGS = ['zero','ra','sp','gp','tp','t0','t1','t2',
        's0','s1','a0','a1','a2','a3','a4','a5',
        'a6','a7','s2','s3','s4','s5','s6','s7',
        's8','s9','s10','s11','t3','t4','t5','t6']

def parse_trace(path):
    rows = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) < 20:
                continue
            row = {
                'cycle': int(parts[0]),
                'if_pc': int(parts[1], 16),
                'if_instr': int(parts[2], 16),
                'id_pc': int(parts[3], 16),
                'id_instr': int(parts[4], 16),
                'ex_pc': int(parts[5], 16),
                'ex_alu_result': int(parts[6], 16),
                'ex_branch_taken': parts[7] == '1',
                'ex_zero_q': parts[8] == '1',
                'ex_out_branch_op_q': int(parts[9]),
                'ex_mem_write': parts[10] == '1',
                'ex_mem_read': parts[11] == '1',
                'ex_store_fault': parts[12] == '1',
                'mem_load_fault': parts[13] == '1',
                'stall': parts[14] == '1',
                'ex_flush': parts[15] == '1',
                'any_trap_taken': parts[16] == '1',
            }
            regs = {}
            for i, name in enumerate(REGS):
                if 17 + i < len(parts):
                    regs[name] = int(parts[17 + i], 16)
            row['regs'] = regs
            rows.append(row)
    return rows

def reg_name(n):
    return REGS[n] if n < 32 else f'x{n}'

def main():
    verbose = '--verbose' in sys.argv
    path = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != '--verbose' else None
    if not path:
        print("Usage: python analyze_trace.py trace.csv [--verbose]")
        sys.exit(1)

    rows = parse_trace(path)
    print(f"Loaded {len(rows)} cycle entries from {path}")

    # --- Find epilogue execution (PC around 0x80000040) ---
    epi_entries = [r for r in rows if 0x80000040 <= r['ex_pc'] < 0x80000060]
    if not epi_entries:
        print("\n*** No epilogue execution found (EX_PC in 0x80000040-0x80000060) ***")
        # Check if program got stuck elsewhere
        print("Searching for any execution after cycle 100...")
        active = [r for r in rows if r['cycle'] > 100 and r['ex_pc'] != 0]
        if active:
            # Find repeated PCs (infinite loop detection)
            from collections import Counter
            pc_counts = Counter(r['ex_pc'] for r in active[-200:])
            top_pcs = pc_counts.most_common(5)
            print(f"  Most frequent PCs in last 200 active cycles:")
            for pc, cnt in top_pcs:
                print(f"    0x{pc:08x} x{cnt}")
        sys.exit(1)

    epi_start = epi_entries[0]['cycle']
    epi_end = epi_entries[-1]['cycle']
    print(f"\nEpilogue execution: cycles {epi_start} - {epi_end}")
    print(f"  ({len(epi_entries)} cycles)")

    # --- Find the BEQ at 0x8000004e ---
    beq_rows = [r for r in rows if r['ex_pc'] == 0x8000004e]
    print(f"\nBEQ at 0x8000004e observed in EX stage: {len(beq_rows)} times")
    for br in beq_rows:
        print(f"  Cycle {br['cycle']}: ex_branch_taken={int(br['ex_branch_taken'])} "
              f"ex_zero_q={int(br['ex_zero_q'])} "
              f"ex_out_branch_op_q={br['ex_out_branch_op_q']} "
              f"ex_mem_write={int(br['ex_mem_write'])} "
              f"ex_store_fault={int(br['ex_store_fault'])} "
              f"mem_load_fault={int(br['mem_load_fault'])} "
              f"stall={int(br['stall'])} ex_flush={int(br['ex_flush'])} "
              f"any_trap={int(br['any_trap_taken'])} "
              f"sp=0x{br['regs']['sp']:08x} gp=0x{br['regs']['gp']:08x}")

    # --- Analyze cycles around the BEQ ---
    if beq_rows:
        beq_cycle = beq_rows[0]['cycle']
        window_start = max(0, beq_cycle - 10)
        window_end = min(len(rows), beq_cycle + 5)
        print(f"\nCycle-by-cycle around first BEQ (cycle {beq_cycle}):")
        for r in rows[window_start:window_end]:
            marker = " <<< BEQ" if r['ex_pc'] == 0x8000004e else ""
            print(f"  C{r['cycle']:5d}: EX_PC=0x{r['ex_pc']:08x} "
                  f"IF_PC=0x{r['if_pc']:08x} ID_PC=0x{r['id_pc']:08x} "
                  f"br_taken={int(r['ex_branch_taken'])} "
                  f"zero_q={int(r['ex_zero_q'])} "
                  f"branch_op={r['ex_out_branch_op_q']} "
                  f"ex_stall={int(r['stall'])} ex_flush={int(r['ex_flush'])} "
                  f"any_trap={int(r['any_trap_taken'])}"
                  f"{marker}")

    # --- Check for access faults ---
    print("\nAccess faults:")
    faults = [r for r in rows if r['ex_store_fault'] or r['mem_load_fault']]
    if faults:
        for f in faults[:10]:
            kinds = []
            if f['ex_store_fault']: kinds.append('STORE')
            if f['mem_load_fault']: kinds.append('LOAD')
            print(f"  Cycle {f['cycle']}: {'+'.join(kinds)} fault "
                  f"PC=0x{f['ex_pc']:08x} "
                  f"sp=0x{f['regs']['sp']:08x}")
        if len(faults) > 10:
            print(f"  ... and {len(faults)-10} more")
    else:
        print("  None detected")

    # --- Check for exceptions / traps ---
    print("\nTraps (any_trap_taken=1):")
    traps = [r for r in rows if r['any_trap_taken']]
    if traps:
        for t in traps[:10]:
            print(f"  Cycle {t['cycle']}: PC=0x{t['ex_pc']:08x} "
                  f"ex_branch_taken={int(t['ex_branch_taken'])} "
                  f"ex_store_fault={int(t['ex_store_fault'])} "
                  f"mem_load_fault={int(t['mem_load_fault'])}")
        if len(traps) > 10:
            print(f"  ... and {len(traps)-10} more")
    else:
        print("  None detected")

    # --- Check for ebreak ---
    print("\nEBREAK detection:")
    # Look for ebreak instruction (0x00100073) in any pipeline stage
    ebreaks = [(r, s) for r in rows for s in ['if_instr','id_instr']
                if r[s] == 0x00100073]
    if ebreaks:
        for r, s in ebreaks[:5]:
            print(f"  Cycle {r['cycle']}: {s}=0x00100073 (ebreak) "
                  f"PC=0x{r['ex_pc']:08x}")
    else:
        print("  Not found in trace")

    # --- Summary ---
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Total cycles: {len(rows)}")
    print(f"  Epilogue reached: {'YES' if epi_entries else 'NO'}")
    print(f"  BEQ at 0x8000004e executed: {len(beq_rows)} times")
    if beq_rows:
        taken = sum(1 for r in beq_rows if r['ex_branch_taken'])
        print(f"  BEQ taken: {taken}/{len(beq_rows)}")
    print(f"  Access faults: {len(faults)}")
    print(f"  Traps: {len(traps)}")
    print(f"  EBREAK found: {'YES' if ebreaks else 'NO'}")


if __name__ == '__main__':
    main()
