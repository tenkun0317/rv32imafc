addi x2, x0, 0
addi x2, x2, 4
beq x0, x0, skip
addi x5, x0, 99
skip:
addi x5, x0, 1
nop
ebreak
jal x0, self
self: