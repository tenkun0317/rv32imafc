nop
nop
addi x1, x0, 3
addi x1, x1, 1
jal x3, skip
addi x5, x0, 3
skip:
addi x5, x0, 5
addi x1, x1, 1
nop
ebreak
jal x0, halt
halt: