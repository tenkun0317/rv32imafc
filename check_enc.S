.text
mv t0, sp
mv t1, gp
c.mv t0, sp
c.mv t1, gp
c.slli s0, 3
c.srli s0, 3
c.srai s0, 3
c.andi s0, -1
c.sub s0, s1
c.xor s0, s1
c.or  s0, s1
c.and s0, s1
c.addi16sp sp, 128
c.addi4spn s0, sp, 16
c.lw s0, 4(s0)
c.sw s0, 4(s1)
c.lwsp t0, 8(sp)
c.swsp t0, 8(sp)
nop
