module tb_diag;

logic clk, rst_n;
logic [31:0] pc_debug;
logic [31:0] instr_debug;
logic ebreak_debug;

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
int instr_count;
int stall_cycles_total;
initial begin cycle_count = 0; instr_count = 0; stall_cycles_total = 0; end

always @(posedge clk) begin
    if (rst_n) begin
        cycle_count <= cycle_count + 1;
        if (u_top.stall)
            stall_cycles_total <= stall_cycles_total + 1;
        if (!u_top.stall && u_top.id_valid)
            instr_count <= instr_count + 1;
        if (cycle_count % 500000 == 0) begin
            $display("DIAG: cycle=%0d pc=0x%08x stall=%b valid=%b dv=%b count_instr=%0d stall_pct=%0d%%",
                     cycle_count, pc_debug, u_top.stall, u_top.id_valid,
                     u_top.u_if.data_valid,
                     instr_count,
                     (stall_cycles_total * 100) / cycle_count);
            $fflush();
        end
    end
end

always @(posedge clk) begin
    if (rst_n && u_top.u_ex.ex_ebreak_q &&
        u_top.u_mem.u_ram.mem[((u_top.u_ex.ex_pc_q + 32'd4) >> 2) & 32'h0000FFFF] == 32'h0000006f) begin
        $display("DIAG: === rvmodel_halt at cycle %0d instr=%0d ===", cycle_count, instr_count);
        $fflush();
        $finish;
    end
end

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;
    #2000000000;
    $display("DIAG: TIMEOUT at cycle %0d pc=0x%08x instr=%0d stall_pct=%0d%%",
             cycle_count, pc_debug, instr_count,
             (cycle_count > 0 ? (stall_cycles_total * 100) / cycle_count : 0));
    $fflush();
    $finish;
end

endmodule