.text
.align 2
.globl _start

_start:
    # ---- Test C.LI ----
    c.li    t0, 15
    addi    t1, x0, 15
    bne     t0, t1, fail

    # ---- Test C.ADDI ----
    c.addi  t0, -5
    addi    t1, x0, 10
    bne     t0, t1, fail

    # ---- Test C.NOP ----
    c.nop

    # ---- Test C.LUI ----
    c.lui   s0, 0x00005
    lui     t1, 0x00005
    bne     s0, t1, fail

    # ---- Test C.ADDI16SP ----
    mv      sp, x0
    c.addi16sp sp, 16
    addi    t1, x0, 16
    bne     sp, t1, fail

    # ---- Test C.LWSP / C.SWSP ----
    c.li    t2, 21
    c.swsp  t2, 4(sp)
    c.lwsp  t3, 4(sp)
    bne     t2, t3, fail

    # ---- Test C.JAL + C.JR ----
    c.jal   target_jal
    c.j     fail

target_jal:
    c.jr    ra

    # ---- Test C.BEQZ (x8-x15) ----
    c.li    a0, 0
    c.beqz  a0, beqz_ok
    c.j     fail
beqz_ok:

    # ---- Test C.BNEZ (x8-x15) ----
    c.li    a1, 1
    c.bnez  a1, bnez_ok
    c.j     fail
bnez_ok:

    # ---- Quadrant 0: addi4spn / lw / sw (x8-x15) ----
    c.addi  sp, -32
    c.li    a4, 21
    mv      a5, a4
    c.addi4spn a0, sp, 16
    c.sw    a5, 0(a0)
    c.lw    a2, 0(a0)
    bne     a4, a2, fail

    # ---- C.SRLI (x8-x15) ----
    li      a0, 0x10000000
    c.srli  a0, 28
    addi    t1, x0, 1
    bne     a0, t1, fail

    # ---- C.SRAI (x8-x15) ----
    li      a1, 0x80000000
    c.srai  a1, 31
    li      t1, 0xFFFFFFFF
    bne     a1, t1, fail

    # ---- C.SUB (x8-x15) ----
    c.li    a0, 22
    c.li    a1, 11
    c.sub   a2, a1
    addi    t1, x0, 11
    bne     a2, t1, fail

    # ---- C.XOR (x8-x15) ----
    c.li    a0, 15
    c.li    a1, 3
    c.xor   a2, a1
    addi    t1, x0, 12
    bne     a2, t1, fail

    # ---- C.OR (x8-x15) ----
    c.li    a0, 12
    c.li    a1, 3
    c.or    a2, a1
    addi    t1, x0, 15
    bne     a2, t1, fail

    # ---- C.AND (x8-x15) ----
    c.li    a0, 15
    c.li    a1, 3
    c.and   a2, a1
    addi    t1, x0, 3
    bne     a2, t1, fail

    # ---- C.SLLI ----
    c.li    t0, 1
    c.slli  t0, 5
    addi    t1, x0, 32
    bne     t0, t1, fail

    # ---- C.ANDI (x8-x15) ----
    c.li    a0, 15
    c.andi  a0, 3
    addi    t1, x0, 3
    bne     a0, t1, fail

    # ---- C.ADDI4SPN ----
    c.addi  sp, 0
    c.addi4spn a3, sp, 8
    addi    t1, sp, 8
    bne     a3, t1, fail

    # ---- C.MV / C.ADD tests ----
    c.li    t0, 7
    c.li    t1, 13
    c.add   t0, t1
    addi    t2, x0, 20
    bne     t0, t2, fail

    c.mv    t3, t0
    bne     t3, t2, fail

    # ---- All tests passed ----
    li      a7, 1
    ebreak

fail:
    li      a7, 0
    ebreak
