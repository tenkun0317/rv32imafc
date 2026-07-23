#!/bin/bash
cd "$(dirname "$0")"
mkdir -p riscv-arch-test/work/rv32imac_sim/elfs/rv32i/Zca

TESTDIR="riscv-arch-test/tests/rv32i/Zca"
LINKER="riscv-arch-test/config/cores/rv32imac_sim/link.ld"
OUTDIR="riscv-arch-test/work/rv32imac_sim/elfs/rv32i/Zca"

for src in "$TESTDIR"/*.S; do
    name=$(basename "$src" .S)
    riscv64-unknown-elf-gcc -nostartfiles -nostdlib \
        -march=rv32imac -mabi=ilp32 \
        -DTEST_FLEN=32 \
        -Iriscv-arch-test/tests/env \
        -Iriscv-arch-test/config/cores/rv32imac_sim \
        -T "$LINKER" \
        -o "$OUTDIR/$name.elf" "$src" 2>&1
done
echo "=== DONE ==="
