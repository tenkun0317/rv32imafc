module tb;

logic clk, rst_n;

logic [31:0] pc_debug;
logic [31:0] instr_debug;
logic        ebreak_debug;

logic [31:0] if_pc;
logic [31:0] if_instr;
logic [31:0] id_rs1_data, id_rs2_data;
logic [4:0]  id_rs1_addr, id_rs2_addr;
logic [4:0]  id_rd_addr;
logic       id_rd_we;
logic [31:0] ex_alu_result;
logic [4:0]  ex_rd_addr;
logic       ex_rd_we;
logic [31:0] mem_alu_result;
logic [4:0]  mem_rd_addr;
logic       mem_rd_we;
logic [31:0] wb_rd_data;
logic [4:0]  wb_rd_addr;
logic       wb_rd_we;

top u_top (
    .clk        (clk),
    .rst_n      (rst_n),
    .meip_i     (1'b0),
    .msip_i     (1'b0),
    .pc_debug   (pc_debug),
    .instr_debug(instr_debug),
    .ebreak_debug(ebreak_debug)
);

assign if_pc       = u_top.if_pc;
assign if_instr    = u_top.if_instr;
assign id_rs1_data = u_top.alu_rs1_data;
assign id_rs2_data = u_top.alu_rs2_data;
assign id_rs1_addr = u_top.id_rs1_addr;
assign id_rs2_addr = u_top.id_rs2_addr;
assign id_rd_addr  = u_top.id_rd_addr;
assign id_rd_we    = u_top.id_rd_we;
assign ex_alu_result = u_top.ex_alu_result;
assign ex_rd_addr  = u_top.ex_rd_addr;
assign ex_rd_we    = u_top.ex_rd_we;
assign mem_alu_result = u_top.mem_alu_result;
assign mem_rd_addr = u_top.mem_rd_addr;
assign mem_rd_we   = u_top.mem_rd_we;
assign wb_rd_data  = u_top.wb_rd_data;
assign wb_rd_addr  = u_top.wb_rd_addr;
assign wb_rd_we    = u_top.wb_rd_we;



always #5 clk = ~clk;

int cycle_count;
initial cycle_count = 0;
always @(posedge clk) begin
    if (rst_n) begin
        cycle_count <= cycle_count + 1;
        // Trace file disabled for speed
        if (cycle_count > 0 && cycle_count <= 0) begin
            $display("=== Cycle %0d ===", cycle_count);
            $display("  IF: pc=0x%08x bram=0x%08x instr=0x%08x dw=%b stall=%b",
                     if_pc, u_top.if_bram_addr, if_instr,
                     u_top.u_if.data_valid, u_top.stall);
            $display("  ID: rs1=x%0d(%08x) rs2=x%0d(%08x) rd=x%0d we=%b id_instr=0x%08x imm=0x%08x",
                     id_rs1_addr, id_rs1_data, id_rs2_addr, id_rs2_data,
                     id_rd_addr, id_rd_we, u_top.id_instr_r, u_top.id_imm);
            $display("  EX: alu_result=0x%08x rd=x%0d we=%b mem_read=%b a_sel=%d b_sel=%d",
                     ex_alu_result, ex_rd_addr, ex_rd_we, u_top.ex_mem_read,
                     u_top.u_ex.ex_alu_a_sel_q, u_top.u_ex.ex_alu_b_sel_q);
            $display("  EX_IN: rs1=0x%08x rs2=0x%08x imm=0x%08x alu_op=%b a_sel=%b b_sel=%b",
                     u_top.u_ex.ex_rs1_data_q, u_top.u_ex.ex_rs2_data_q, u_top.u_ex.ex_imm_q,
                     u_top.u_ex.ex_alu_op_q, u_top.u_ex.ex_alu_a_sel_q, u_top.u_ex.ex_alu_b_sel_q);
            $display("  MEM: alu_result=0x%08x rd=x%0d we=%b mem_read=%b",
                     mem_alu_result, mem_rd_addr, mem_rd_we, u_top.mem_mem_read);
            $display("  WB: rd_data=0x%08x rd=x%0d we=%b",
                     wb_rd_data, wb_rd_addr, wb_rd_we);
            $display("  RF[x6]=0x%08x x31=0x%08x",
                     u_top.u_reg.rf[6], u_top.u_reg.rf[31]);
        end
        
        
    end
end

always @(posedge clk) begin
    // EBREAK is normally an architectural exception.  The RV model's halt
    // routines uniquely encode `ebreak; jal x0, 0`; use the second word to
    // distinguish those from architectural EBREAK exception tests.
    if (rst_n && u_top.u_ex.ex_ebreak_q &&
        u_top.u_mem.u_ram.mem[((u_top.u_ex.ex_pc_q + 32'd4) >> 2) & 32'h0000FFFF] == 32'h0000006f) begin
        $display("=== rvmodel_halt at cycle %0d ===", cycle_count);
        $display("PC: 0x%08x", pc_debug);
        $display("mepc=0x%08x mcause=0x%08x mtval=0x%08x",
                 u_top.u_csr.mepc_val, u_top.u_csr.mcause, u_top.u_csr.mtval);
        $display("Registers at ebreak:");
        for (int i = 0; i < 8; i++) begin
            $display("  x%0d=0x%08x x%0d=0x%08x x%0d=0x%08x x%0d=0x%08x",
                     i*4,   u_top.u_reg.rf[i*4],
                     i*4+1, u_top.u_reg.rf[i*4+1],
                     i*4+2, u_top.u_reg.rf[i*4+2],
                     i*4+3, u_top.u_reg.rf[i*4+3]);
        end
        $display("=== BRAM RESULTS ===");
        for (int i = 0; i < 16384; i++) begin
            $display("BRAM[%0d] = 0x%08x", i, u_top.u_mem.u_ram.mem[i]);
        end
        $finish;
    end
end

// Safety timeout: prevent runaway simulations from hanging forever.
// Real arch tests finish in well under this; reaching it means a bug.
int trap_count;
int trap_cyc[10];
logic [31:0] trap_mepc[10];
logic [31:0] trap_mcause[10];
int branch_log_cnt;
int branch_log_cyc[200];
logic [31:0] branch_log_target[200];
logic [31:0] branch_log_pc[200];
logic [31:0] branch_log_imm[200];
logic [1:0]  branch_log_op[200];
int log_start;
always @(posedge clk) begin
    if (!rst_n) begin
        trap_count <= 0;
        branch_log_cnt <= 0;
    end else begin
        if (u_top.u_ex.ex_branch_taken) begin
            if (branch_log_cnt < 200) begin
                branch_log_cyc[branch_log_cnt] <= cycle_count;
                branch_log_target[branch_log_cnt] <= u_top.u_ex.ex_branch_target;
                branch_log_pc[branch_log_cnt] <= u_top.u_ex.ex_out_pc_q;
                branch_log_imm[branch_log_cnt] <= u_top.u_ex.ex_out_imm_q;
                branch_log_op[branch_log_cnt] <= u_top.u_ex.ex_out_branch_op_q;
                branch_log_cnt <= branch_log_cnt + 1;
            end
        end
        if (u_top.any_trap_taken) begin
            if (trap_count < 10) begin
                trap_cyc[trap_count] <= cycle_count;
                trap_mepc[trap_count] <= u_top.u_csr.mepc_val;
                trap_mcause[trap_count] <= u_top.u_csr.mcause;
            end
            if (trap_count == 0) begin
                $display("=== FIRST TRAP ===");
                $display("  cyc=%0d", cycle_count);
                $display("  ex_pc=0x%08x", u_top.u_ex.ex_out_pc_q);
                $display("  ex_valid=%b", u_top.ex_valid);
                $display("  ex_if_access_fault=%b", u_top.ex_if_access_fault);
                $display("  ex_ecall=%b ex_ebreak=%b ex_illegal=%b", u_top.ex_ecall, u_top.ex_ebreak, u_top.ex_illegal);
                $display("  ex_store_fault=%b mem_load_fault=%b", u_top.ex_store_fault, u_top.mem_load_fault);
                $display("  ex_branch_op=%b", u_top.u_ex.ex_out_branch_op_q);
                $display("  ex_pc=0x%08x ex_imm=0x%08x ex_rs1=0x%08x", u_top.u_ex.ex_out_pc_q, u_top.u_ex.ex_out_imm_q, u_top.u_ex.ex_out_rs1_q);
                $display("  ex_alu_result=0x%08x", u_top.u_ex.ex_alu_result);
            end
            trap_count <= trap_count + 1;
        end
    end
    if (rst_n && cycle_count >= 32'd200000) begin
        $display("=== TIMEOUT at cycle %0d ===", cycle_count);
        $display("PC: 0x%08x  instr: 0x%08x", pc_debug, instr_debug);
        $display("trap_count=%0d", trap_count);
        for (int i = 0; i < 10 && i < trap_count; i++) begin
            $display("  trap[%0d] cyc=%0d mepc=0x%08x mcause=0x%08x", i, trap_cyc[i], trap_mepc[i], trap_mcause[i]);
        end
        $display("Branch log (all %0d):", branch_log_cnt);
        for (int i = 0; i < branch_log_cnt; i++) begin
            $display("  br[%0d] cyc=%0d pc=0x%08x imm=0x%08x op=%0d target=0x%08x",
                     i, branch_log_cyc[i], branch_log_pc[i],
                     branch_log_imm[i], branch_log_op[i],
                     branch_log_target[i]);
        end
        $finish;
    end
end

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;

    // No fixed timeout — run_arch_test.py controls timeout.
    // Wait forever (until rvmodel_halt fires or the subprocess is killed).
    forever #100000000; // 10M ns per iteration, effectively infinite
end

// VCD dump disabled for speed

endmodule
