module perf_tb;

logic clk, rst_n;

logic [31:0] pc_debug;
logic [31:0] instr_debug;
logic        ebreak_debug;

top u_top (
    .clk        (clk),
    .rst_n      (rst_n),
    .meip_i     (1'b0),
    .msip_i     (1'b0),
    .pc_debug   (pc_debug),
    .instr_debug(instr_debug),
    .ebreak_debug(ebreak_debug)
);

always #5 clk = ~clk;

int cycle_count;
initial cycle_count = 0;
always @(posedge clk) begin
    if (rst_n) begin
        cycle_count <= cycle_count + 1;
    end
end

logic halt_detected;
always @(posedge clk) begin
    if (rst_n && u_top.u_ex.ex_ebreak_q &&
        u_top.u_mem.u_ram.mem[((u_top.u_ex.ex_pc_q + 32'd4) >> 2) & 32'h0000FFFF] == 32'h0000006f) begin
        if (!halt_detected) begin
            halt_detected <= 1'b1;
            $display("=== rvmodel_halt at cycle %0d ===", cycle_count);
            $display("PC: 0x%08x", pc_debug);
            $display("=== BRAM RESULTS ===");
            for (int i = 0; i < 16384; i++) begin
                $display("BRAM[%0d] = 0x%08x", i, u_top.u_mem.u_ram.mem[i]);
            end
            $finish;
        end
    end
end

initial begin
    halt_detected = 1'b0;
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;
    // 200,000,000 ns = 20M cycles
    #200000000;
    $display("=== Timeout at cycle %0d, PC=0x%08x ===", cycle_count, pc_debug);
    $display("mtvec=0x%08x mepc=0x%08x mcause=0x%08x mtval=0x%08x",
             u_top.u_csr.mtvec_val, u_top.u_csr.mepc_val,
             u_top.u_csr.mcause, u_top.u_csr.mtval);
    $finish;
end

endmodule