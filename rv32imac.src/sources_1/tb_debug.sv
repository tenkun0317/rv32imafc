module tb_debug;
    logic clk, rst_n;
    logic [31:0] pc_debug, instr_debug;
    logic        ebreak_debug;

    top u_top (
        .clk(clk), .rst_n(rst_n),
        .meip_i(1'b0), .msip_i(1'b0),
        .pc_debug(pc_debug),
        .instr_debug(instr_debug),
        .ebreak_debug(ebreak_debug)
    );

    always #5 clk = ~clk;

    int cycle_count;
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;
            if ((u_top.u_ex.ex_ebreak || u_top.u_ex.ex_ebreak_q || u_top.u_mem.mem_ebreak) && cycle_count > 0)
                $display("cyc=%0d XXXX EBREAK ex_ebreak=%b ex_ebreak_q=%b mem_ebreak=%b | pc_if=0x%08x id_pc=0x%08x ex_pc=0x%08x",
                    cycle_count, u_top.ex_ebreak, u_top.u_ex.ex_ebreak_q, u_top.u_mem.mem_ebreak,
                    u_top.if_pc, u_top.id_pc_r, u_top.u_ex.ex_pc_q);
            if (cycle_count <= 800 || u_top.any_trap_taken || u_top.irq_taken || u_top.u_mem.mem_load_fault || u_top.u_mem.ex_mem_write)
                $display("cyc=%0d pc_if=0x%08x instr=0x%08x v=%b id_pc=0x%08x id_instr=0x%08x ex_pc=0x%08x trap=%b mepc=0x%08x mcause=0x%08x flush=%b btarget=0x%08x btaken=%b | EX: mw=%b mt=%b mr=%b alu=0x%08x rs1d=0x%08x rs2d=0x%08x | MEM: pc=0x%08x alu=0x%08x rd=%b mr=%b v=%b ldf=%b | mtvec=0x%08x",
                    cycle_count, u_top.if_pc, u_top.if_instr, u_top.u_if.data_valid,
                    u_top.id_pc_r, u_top.id_instr_r, u_top.u_ex.ex_pc_q,
                    u_top.any_trap_taken, u_top.u_csr.mepc_val, u_top.u_csr.mcause, u_top.ex_flush,
                    u_top.ex_branch_target, u_top.ex_branch_taken,
                    u_top.u_mem.ex_mem_write, u_top.u_mem.ex_mem_type, u_top.u_mem.ex_mem_read, u_top.ex_alu_result, u_top.u_ex.ex_rs1_data_q, u_top.u_ex.ex_rs2_data_q,
                    u_top.u_mem.mem_pc, u_top.u_mem.mem_alu_result, u_top.u_mem.mem_rd_we, u_top.u_mem.mem_mem_read, u_top.u_mem.mem_valid, u_top.u_mem.mem_load_fault,
                    u_top.u_csr.mtvec_val);
            if (u_top.u_ex.ex_ebreak_q &&
                u_top.u_mem.u_ram.mem[((u_top.u_ex.ex_pc_q + 32'd4) >> 2) & 32'h0000FFFF] == 32'h0000006f) begin
                $display("=== rvmodel_halt at cycle %0d ===", cycle_count);
                $display("PC: 0x%08x", pc_debug);
                $display("ebreak_pc: 0x%08x", u_top.u_ex.ex_pc_q);
                $display("mepc=0x%08x mcause=0x%08x", u_top.u_csr.mepc_val, u_top.u_csr.mcause);
                for (int i = 0; i < 8; i++) begin
                    $display("  x%0d=0x%08x x%0d=0x%08x x%0d=0x%08x x%0d=0x%08x",
                        i*4,   u_top.u_reg.rf[i*4],
                        i*4+1, u_top.u_reg.rf[i*4+1],
                        i*4+2, u_top.u_reg.rf[i*4+2],
                        i*4+3, u_top.u_reg.rf[i*4+3]);
                end
                $display("=== BRAM RESULTS (first 200) ===");
                for (int i = 0; i < 200; i++) begin
                    $display("BRAM[%0d] = 0x%08x", i, u_top.u_mem.u_ram.mem[i]);
                end
                $finish;
            end
            if (cycle_count >= 32'd10000) begin
                $display("=== TIMEOUT at cycle %0d ===", cycle_count);
                $display("IF: pc=0x%08x instr=0x%08x valid=%b", u_top.if_pc, u_top.if_instr, u_top.u_if.data_valid);
                $display("ID: instr=0x%08x pc=0x%08x", u_top.id_instr_r, u_top.id_pc_r);
                $display("EX: pc=0x%08x ex_ebreak_q=%b ex_valid=%b ex_branch_op=%b ex_branch_f3=%b ex_branch_taken=%b ex_branch_target=0x%08x",
                    u_top.u_ex.ex_pc_q, u_top.u_ex.ex_ebreak_q, u_top.ex_valid,
                    u_top.u_ex.ex_branch_op_q, u_top.u_ex.ex_branch_f3_q,
                    u_top.ex_branch_taken, u_top.ex_branch_target);
                $finish;
            end
        end
    end

    initial begin
        clk = 0; rst_n = 0;
        #15 rst_n = 1;
    end
endmodule
