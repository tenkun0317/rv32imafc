// Minimal halt test — verifies ebreak detection in large binary context
.section .text, "ax"
.globl _start
_start:
    // Jump to rvmodel_halt_pass (ebreak; j .)
    // Use offset-based approach like the real test
    auipc ra, %hi(rvmodel_halt_pass)
    jalr ra, %lo(rvmodel_halt_pass)(ra)

    // Should never reach here
    j .

// Minimal dummy halt function
rvmodel_halt_pass:
    ebreak
    j .