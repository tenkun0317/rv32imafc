module tb_first;

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

int c;
initial c = 0;
always @(posedge clk) begin
    if (rst_n) begin
        c <= c + 1;
        if (c <= 100000 && (c % 10000 == 0 || (c > 200 && c % 500 == 0))) begin
            $display("[%6d] pc=0x%08h stall=%b dv=%b mcause=%h trap=%b",
                     c, pc_debug, u_top.stall, u_top.u_if.data_valid,
                     u_top.u_csr.mcause != 0 ? u_top.u_csr.mcause : 32'h0,
                     u_top.u_csr.mcause != 0);
            $fflush();
        end
    end
end

always @(posedge clk) begin
    if (rst_n && u_top.u_ex.ex_ebreak_q &&
        u_top.u_mem.u_ram.mem[((u_top.u_ex.ex_pc_q + 32'd4) >> 2) & 32'h0000FFFF] == 32'h0000006f) begin
        $display("=== rvmodel_halt at cycle %0d ===", c);
        $fflush();
        $finish;
    end
end

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;
    #20000000;
    $display("TIMEOUT c=%0d pc=0x%08h", c, pc_debug);
    $fflush();
    $finish;
end

endmodule