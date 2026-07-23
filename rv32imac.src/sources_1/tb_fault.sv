module tb_fault;

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
        if (c > 2790 && c <= 2800) begin
            $display("[%4d] ex_pc=0x%08h ex_alu=0x%08h ex_mwr=%b ex_mrd=%b ex_v=%b idv=%b",
                     c,
                     u_top.u_ex.ex_pc_q,
                     u_top.u_ex.ex_alu_result,
                     u_top.u_ex.ex_mem_write_q,
                     u_top.u_ex.ex_mem_read_q,
                     u_top.u_ex.ex_valid_q,
                     u_top.id_valid);
            $fflush();
        end
    end
end

always @(posedge clk) begin
    if (rst_n && u_top.u_csr.mcause != 32'h0 && u_top.u_csr.mcause != u_top.u_csr.mcause) begin
    end else if (rst_n && u_top.u_csr.mcause != 32'h0) begin
        $display("[%4d] TRAP: mcause=%h mepc=0x%08h ex_alu=0x%08h ex_mwr=%b",
                 c, u_top.u_csr.mcause, u_top.u_csr.mepc,
                 u_top.u_ex.ex_alu_result, u_top.u_ex.ex_mem_write);
        $fflush();
    end
end

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;
    #20000000;
    $display("TIMEOUT");
    $fflush();
    $finish;
end

endmodule