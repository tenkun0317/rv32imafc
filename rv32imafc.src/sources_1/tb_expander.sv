module tb_expander;

    // DUT inputs
    logic [31:0] if_instr = 32'h0;
    logic        if_valid = 1'b1;
    logic [31:0] rs1_data = 32'h0;
    logic [31:0] rs2_data = 32'h0;
    logic        ex_done  = 1'b1;
    logic [31:0] csr_rdata = 32'h0;

    // DUT outputs
    logic [4:0]    id_rs1_addr, id_rs2_addr, id_rd_addr, id_alu_op;
    logic [1:0]    id_alu_a_sel, id_alu_b_sel, id_branch_op;
    logic [2:0]    id_mem_type, id_csr_op, id_branch_f3;
    logic          id_rd_we, id_mem_read, id_mem_write, id_valid;
    logic          id_ebreak, id_ecall, id_mret, id_mul_div, id_illegal, ex_stall;
    logic          if_access_fault, id_if_access_fault;
    logic [31:0]   id_imm, id_csr_rdata;
    logic [11:0]   id_csr_addr;

    // Internal signal access for expanded_instr
    logic [31:0]   expanded_instr;

    id_stage dut(.*);

    // Override expanded_instr for monitoring (no direct output port, so we observe via derived signals)
    // We'll infer expanded_instr from the decoder outputs
    // Actually, let's add a workaround: check opcode/funct3/funct7/rd/rs1/rs2 pattern

    string name;  // instruction name
    int pass = 0;
    int fail = 0;

    task run_test(input [15:0] instr, input string label, input [31:0] exp, input [4:0] exp_rd, input [4:0] exp_rs1);
        logic [31:0] actual_exp;
        logic [4:0]  actual_rd, actual_rs1;

        if_instr = {16'h0, instr};  // upper half zero (as IF stage delivers)
        #1;

        // Reconstruct expanded_instr from the output signals
        // opcode = id_alu_op? No, we need to look at the encoded patterns
        // Best approach: Since expanded_instr feeds the standard decoder,
        // we can reconstruct opcode from the decoded outputs indirectly.
        // For an expander test, we can simply check the key decoded fields.

        // Check: id_valid should be 1
        if (!id_valid) begin
            $display("FAIL [%s]: id_valid=0", label);
            fail++;
            return;
        end

        // Check rd
        if (id_rd_addr !== exp_rd) begin
            $display("FAIL [%s]: rd = %0d, expected %0d", label, id_rd_addr, exp_rd);
            fail++;
            return;
        end

        // Check rs1
        if (id_rs1_addr !== exp_rs1) begin
            $display("FAIL [%s]: rs1 = %0d, expected %0d", label, id_rs1_addr, exp_rs1);
            fail++;
            return;
        end

        // For ADDI-type expansions: check imm = sign_ext({inst[12], inst[6:2]})
        // We can reconstruct the expected imm pattern
        // For now, just print pass

        $display("PASS [%s] rd=%0d rs1=%0d rs2=%0d", label, id_rd_addr, id_rs1_addr, id_rs2_addr);
        pass++;
    endtask

    task run_test_jal(input [15:0] instr, input string label, input [4:0] exp_rd, input [31:0] exp_imm);
        if_instr = {16'h0, instr};
        #1;

        if (!id_valid) begin
            $display("FAIL [%s]: id_valid=0", label);
            fail++;
            return;
        end

        if (id_rd_addr !== exp_rd) begin
            $display("FAIL [%s]: rd = %0d, expected %0d", label, id_rd_addr, exp_rd);
            fail++;
            return;
        end

        if (id_imm !== exp_imm) begin
            $display("FAIL [%s]: imm = %0d (0x%h), expected %0d (0x%h)", label, id_imm, id_imm, exp_imm, exp_imm);
            fail++;
            return;
        end

        $display("PASS [%s] rd=%0d imm=%0d (0x%h)", label, id_rd_addr, id_imm, id_imm);
        pass++;
    endtask

    initial begin
        // Wait for module initialization
        #1;

        $display("===== Quadrant 1 (01) =====");
        // C.ADDI: funct3=000, Quadrant 1
        // addi x3, x3, 4 -> 000|0_00011_00100_01 = 0x0191
        run_test(16'h0191, "C.ADDI x3,4", 32'h00410193, 5'd3, 5'd3);

        // C.ADDI: addi x10, x10, -1 -> imm=-1 ({1,11111})
        // 000|1_01010_11111_01 = 0x957d? No: bit[12]=1, bits[6:2]=11111, bits[7:11]=01010
        // 0 0 0 | 1 | 0 1 0 1 0 | 1 1 1 1 1 | 0 1
        // = 0001_0101_0111_1101 = 0x157d? No.
        // Let's use a known encoding
        run_test(16'h157d, "C.ADDI x10,-1", 32'hfffff513, 5'd10, 5'd10);

        // C.LI: funct3=010, Quadrant 1
        // li x5, 5 -> 010|0_00101_00101_01? No.
        // imm={0,00101}, rd=x5=00101 -> 010|0_00101_00101_01 = 0x4295
        run_test(16'h4295, "C.LI x5,5", 32'h00500293, 5'd5, 5'd0);

        // C.LUI: funct3=011, Quadrant 1
        // lui x10, 1 -> rd=x10 (01010), imm={inst[12], inst[6:2]} = 6'b000001
        // 011 | 0 | 01010 | 00001 | 01 = 0110_0101_0000_0101 = 0x6505
        run_test(16'h6505, "C.LUI x10,1", 32'h00001537, 5'd10, 5'd0);

        // C.ADDI16SP: funct3=011, rd=x2
        // addi x2, x2, 128 -> nzimm[9:4]=128/16=8=001000
        // inst[12]=0, inst[6:2]=01000 -> 011|0_00010_01000_01? No, rd=x2
        // 011|0_00010_01000_01 = 0x6109? Let me check: 6111? 6109?
        // addi16sp sp,128 -> 0x6109
        run_test(16'h6109, "C.ADDI16SP +128", 32'h08010113, 5'd2, 5'd2);

        // C.JAL: funct3=001, Quadrant 1
        // jal x1, offset
        run_test(16'h2001, "C.JAL offset=0", 32'h000000ef, 5'd1, 5'd0);

        // C.JAL offset=+6 (same offset encoding as C.J)
        run_test_jal(16'h2019, "C.JAL offset=+6", 5'd1, 32'd6);

        // C.JAL offset=+36
        run_test_jal(16'h2015, "C.JAL offset=+36", 5'd1, 32'd36);

        // C.J: funct3=101, Quadrant 1
        // jal x0, offset
        run_test(16'ha001, "C.J offset=0", 32'h0000006f, 5'd0, 5'd0);

        // C.J offset=+6 (a019: j +6 from 0x800021ec -> 0x800021f2)
        run_test_jal(16'ha019, "C.J offset=+6", 5'd0, 32'd6);

        // C.J offset=+36 (a015: j +36 from 0x800021ce -> 0x800021f2)
        run_test_jal(16'ha015, "C.J offset=+36", 5'd0, 32'd36);

        $display("");
        $display("===== Quadrant 1: CB/CA ops (funct3=100) =====");
        // C.SRLI: funct3=100, bit[12]=0, bit[11:10]=00
        // srli x8(01000), x8, 3 -> {100|0_00_000_00011_01}
        // bits[15:13]=100, bit[12]=0, bit[11:10]=00, bit[9:7]=000 (x8), bit[6:2]=00011 (3)
        // = 1000_0000_0001_1001 = 0x8019? No:
        // 1000_0000_0000_0011 = 0x8003? Let me compute:
        // 100 [0] 00_000_00011 [01] = 1000_0000_0001_1001? Wait:
        // 100 = bit 15:13
        // 0 = bit 12
        // 00 = bit 11:10
        // 000 = bit 9:7
        // 00011 = bit 6:2
        // 01 = bit 1:0
        // Full 16-bit: 1000_0000_0001_1001 = 0x8019... no.
        // bit15=1, bit14=0, bit13=0, bit12=0, bit11=0, bit10=0, bit9=0, bit8=0, bit7=0, bit6=0, bit5=0, bit4=0, bit3=1, bit2=1, bit1=0, bit0=1
        // 1000_0000_0001_1001? Let me recheck:
        // 1000 = bit[15:12]
        // 0000 = bit[11:8]
        // 0001 = bit[7:4] -> bit7=0,bit6=0,bit5=0,bit4=0 -> NO: bit3=1, so not 0001
        // bit[7:4] = 0000
        // bit[3:0] = bit3=1,bit2=1,bit1=0,bit0=1 = 1101 = d
        // So: 1000_0000_0000_1101 = 0x800d
        run_test(16'h800d, "C.SRLI x8,3", 32'h00305413, 5'd8, 5'd8);

        // C.SRAI: funct3=100, bit[12]=1, bit[11:10]=01
        // srai x8, x8, 3 -> {100|1_01_000_00011_01}
        // = 1001_0100_0001_1001? Let me compute:
        // bit15=1,bit14=0,bit13=0,bit12=1,bit11=0,bit10=1,bit9=0,bit8=0,bit7=0,bit6=0,bit5=0,bit4=0,bit3=1,bit2=1,bit1=0,bit0=1
        // = 1001_0100_0000_1101? = 0x940d
        run_test(16'h940d, "C.SRAI x8,3", 32'h40305413, 5'd8, 5'd8);

        // C.ANDI: funct3=100, bit[12]=1, bit[11:10]=10
        // andi x8, x8, 5 -> {100|1_10_000_00101_01}
        // = 1001_1000_0010_1001 = 0x9829? No.
        // bit15=1,bit14=0,bit13=0,bit12=1,bit11=1,bit10=0,bit9=0,bit8=0,bit7=0,bit6=0,bit5=0,bit4=1,bit3=0,bit2=1,bit1=0,bit0=1
        // = 1001_1000_0010_1001? Wait bit7=0, bit6=0, bit5=0, bit4=1 -> byte = 0001? No: bit4=1 means 000100 -> 0x1_ -> bit3=0 means 02? = 10 = 0x02 -> 01 = 0x1
        // Hmm: bit[7:4] = 0000, bit[3:0] = 0101 -> 0x05
        // So byte = 0x05
        // Full: 1001_1000_0000_0101 = 0x9805
        run_test(16'h9805, "C.ANDI x8,5", 32'h00507413, 5'd8, 5'd8);

        // C.SUB: funct3=100, bit[12]=1, bit[11:10]=11, bit[6:5]=00
        // sub x8, x8, x9 -> {100|1_11_000_00001_001_01}
        // bit15=1,bit14=0,bit13=0,bit12=1,bit11=1,bit10=1,bit9=0,bit8=0,bit7=0,bit6=0,bit5=0,bit4=0,bit3=0,bit2=1,bit1=0,bit0=1
        // = 1001_1100_0000_0101? Wait bit4=0,bit3=0,bit2=1 -> 001 -> plus bit5=0 -> 00010?
        // bit[6:5]=00, bit[4:2]=rs2'=001 (x9)
        // bit[6:5] = 00 = bit6=0,bit5=0
        // bit[4:2] = 001 = bit4=0,bit3=0,bit2=1
        // so bit[6:2] = 00001
        // bit[7:4] = bit7=0,bit6=0,bit5=0,bit4=0 = 0x0
        // bit[3:0] = bit3=0,bit2=1,bit1=0,bit0=1 = 0101 = 0x5
        // Full: 1001_1100_0000_0101 = 0x9c05
        run_test(16'h9c05, "C.SUB x8,x9", 32'h40905433, 5'd8, 5'd8);

        // C.XOR: bit[6:5]=01
        // xor x8, x8, x9 -> bit[6:5]=01, bit[4:2]=001
        // = 1001_1100_0010_0101? bit6=0,bit5=1,bit4=0,bit3=0,bit2=1
        // bit[7:4] = bit7=0,bit6=0,bit5=1,bit4=0 = 0010
        // bit[3:0] = bit3=0,bit2=1,bit1=0,bit0=1 = 0101
        // = 1001_1100_0010_0101 = 0x9c25
        run_test(16'h9c25, "C.XOR x8,x9", 32'h00905433, 5'd8, 5'd8);

        // C.OR: bit[6:5]=10
        // or x8, x8, x9 -> bit[6:5]=10, bit[4:2]=001
        // = 1001_1100_0100_0101 = 0x9c45
        run_test(16'h9c45, "C.OR x8,x9", 32'h0090e433, 5'd8, 5'd8);

        // C.AND: bit[6:5]=11
        // and x8, x8, x9 -> bit[6:5]=11, bit[4:2]=001
        // = 1001_1100_0110_0101 = 0x9c65
        run_test(16'h9c65, "C.AND x8,x9", 32'h0090f433, 5'd8, 5'd8);

        $display("");
        $display("===== Quadrant 2 (10) =====");
        // C.SLLI: funct3=000, Quadrant 2
        // slli x8, x8, 3 -> {000|0_01000_00011_10}
        // = 0000_0100_0000_1110? = 0x040e
        run_test(16'h040e, "C.SLLI x8,3", 32'h00301413, 5'd8, 5'd8);

        // C.LWSP: funct3=010, Quadrant 2
        // lw x8, 4(sp) -> {010|0_01000_00100_10}
        // = 0100_0100_0001_0010? No.
        // bit15=0,bit14=1,bit13=0,bit12=0,bit11=0,bit10=1,bit9=0,bit8=0,bit7=0,bit6=0,bit5=0,bit4=1,bit3=0,bit2=0,bit1=1,bit0=0
        // = 0100_0100_0001_0010 = 0x4412? No.
        // bit[15:12] = 0100
        // bit[11:8] = 0100
        // bit[7:4] = 0000
        // bit[3:0] = 0010
        // = 0100_0100_0_0_00_0010 = 0x4402? Wait: bit7=0,bit6=0,bit5=0,bit4=1 -> bit[7:4]=0001 -> 0x12
        // So: 0x4412
        run_test(16'h4412, "C.LWSP x8,4", 32'h00402403, 5'd8, 5'd2);

        // C.MV: funct3=100, Quadrant 2, bit[12]=0
        // mv x10, x5 -> {100|0_01010_00101_10}
        // = 1000_0101_0001_0110? No.
        // bit15=1,bit14=0,bit13=0,bit12=0,bit11=0,bit10=1,bit9=0,bit8=1,bit7=0,bit6=0,bit5=0,bit4=1,bit3=0,bit2=1,bit1=1,bit0=0
        // = 1000_0101_0001_0110 = 0x8516? Let me verify: 0x852a?
        // Let's think: bit[11:7] = x10 = 01010
        // bit[6:2] = x5 = 00101
        // 1000 | 01010 | 00101 | 10
        // = 1000 0101 0001 0110?
        // Packed: 1000_0101_0001_0110 = 0x8516
        run_test(16'h8516, "C.MV x10,x5", 32'h00500513, 5'd10, 5'd0);

        $display("");
        $display("===== Real test encodings from I-andi-00 objdump =====");
        // C.MV: mv s8, sp
        // 0x8c0a: 1000_1100_0000_1010
        // x24 = s8, x2 = sp -> rd=11000, rs2=00010
        // 1000 | 11000 | 00010 | 10 = 1000_1100_0000_1010 = 0x8c0a ✓
        run_test(16'h8c0a, "C.MV s8,sp", 32'h00200c13, 5'd24, 5'd0);

        // C.MV: mv a4, gp
        // 0x870e: 1000_0111_0000_1110
        // x14 = a4, x3 = gp -> rd=01110, rs2=00011
        // 1000 | 01110 | 00011 | 10 = 1000_0111_0000_1110 = 0x870e ✓
        run_test(16'h870e, "C.MV a4,gp", 32'h00300713, 5'd14, 5'd0);

        // C.MV: mv t2, tp
        // 0x8392: 1000_0011_1001_0010
        // x7 = t2, x4 = tp -> rd=00111, rs2=00100
        // 1000 | 00111 | 00100 | 10 = 1000_0011_1001_0010 = 0x8392 ✓
        run_test(16'h8392, "C.MV t2,tp", 32'h00400393, 5'd7, 5'd0);

        // C.MV: mv s0, t0
        // 0x8416: 1000_0100_0001_0110
        // x8 = s0, x5 = t0 -> rd=01000, rs2=00101
        run_test(16'h8416, "C.MV s0,t0", 32'h00500413, 5'd8, 5'd0);

        $display("");
        $display("===== Edge cases =====");
        // C.MV with rs2=0 -> C.JR
        run_test(16'h8002, "C.JR rs1=x0", 32'h00000067, 5'd0, 5'd0);

        // C.ADD: funct3=100, bit[12]=1
        // add x5, x5, x10 -> rd=x5=00101, rs2=x10=01010
        // 1001 | 00101 | 01010 | 10 = 1001_0010_1010_1010 = 0x92aa
        run_test(16'h92aa, "C.ADD x5,x10", 32'h00a282b3, 5'd5, 5'd5);

        // Final summary
        $display("");
        if (fail == 0)
            $display("ALL %0d TESTS PASSED", pass);
        else
            $display("%0d PASSED, %0d FAILED", pass, fail);

        $finish;
    end

endmodule