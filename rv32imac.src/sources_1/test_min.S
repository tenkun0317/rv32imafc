nop
beq x0, x0, skip
addi x5, x0, 0xBAD
skip:
nop
ebreak
jal x0, halt
halt: