module tb_check491;
    logic [31:0] if_instr;
    logic        if_valid;
    logic [31:0] rs1_data, rs2_data;
    logic        ex_done;
    logic [31:0] csr_rdata;
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr, id_alu_op;
    logic [1:0]  id_alu_a_sel, id_alu_b_sel, id_branch_op;
    logic [2:0]  id_mem_type, id_csr_op, id_branch_f3;
    logic        id_rd_we, id_mem_read, id_mem_write, id_valid;
    logic        id_ebreak, id_ecall, id_mret, id_mul_div, ex_stall;
    logic [31:0] id_imm, id_csr_rdata;
    logic [11:0] id_csr_addr;

    id_stage dut (.*);

    initial begin
        if_valid = 1;
        rs1_data = 32'h0;
        rs2_data = 32'h0;
        ex_done  = 1;
        csr_rdata = 32'h0;

        // Test: C.ADDI x9, 2 = 0x0491
        if_instr = 32'h00000491;
        #1;
        $display("if_instr = 0x%08h", if_instr);
        $display("id_imm   = 0x%08h (%0d)", id_imm, id_imm);
        $display("id_rs1_addr = %0d", id_rs1_addr);
        $display("id_rd_addr  = %0d", id_rd_addr);
        $display("id_alu_op   = 0x%01h", id_alu_op);
        $display("id_rd_we    = %0d", id_rd_we);

        // Also check the expanded_instr via internal
        $display("expanded_instr = 0x%08h", dut.expanded_instr);
        $display("opcode = 0x%02h", dut.opcode);
        $display("expanded_instr[31:20] = 0x%03h", dut.expanded_instr[31:20]);

        $finish;
    end
endmodule
