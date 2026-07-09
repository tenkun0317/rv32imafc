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
        if (cycle_count > 0 && (cycle_count <= 15 || 
            (cycle_count >= 110 && cycle_count <= 160))) begin
            $display("=== Cycle %0d ===", cycle_count);
            $display("  IF: pc=0x%08x instr=0x%08x", if_pc, if_instr);
            $display("  ID: rs1=x%0d(%08x) rs2=x%0d(%08x) rd=x%0d we=%b",
                     id_rs1_addr, id_rs1_data, id_rs2_addr, id_rs2_data,
                     id_rd_addr, id_rd_we);
            $display("  EX: alu_result=0x%08x rd=x%0d we=%b",
                     ex_alu_result, ex_rd_addr, ex_rd_we);
            $display("  MEM: alu_result=0x%08x rd=x%0d we=%b",
                     mem_alu_result, mem_rd_addr, mem_rd_we);
            $display("  WB: rd_data=0x%08x rd=x%0d we=%b",
                     wb_rd_data, wb_rd_addr, wb_rd_we);
            $display("  RF[x6]=0x%08x", u_top.u_reg.rf[6]);
        end
    end
end

always @(posedge clk) begin
    if (rst_n && ebreak_debug) begin
        $display("=== eBREAK at cycle %0d ===", cycle_count);
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

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;

    #200000;
    $display("=== Timeout - Simulation Complete ===");
    $display("Final PC: 0x%08x", pc_debug);
    $finish;
end

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb);
end

endmodule
