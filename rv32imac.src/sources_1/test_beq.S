nop
nop
addi x1, x0, 3
addi x1, x1, 1
sub x3, x1, x1
addi x3, x1, 0
addi x1, x0, 0
beq x1, x0, skip
addi x5, x0, 3
skip:
addi x5, x0, 5
addi x1, x1, 1
nop
ebreak