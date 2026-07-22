module tb_store;

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
int trap_count;
logic [31:0] last_mcause;
initial begin c = 0; trap_count = 0; last_mcause = 0; end

always @(posedge clk) begin
    if (rst_n) begin
        c <= c + 1;
        if (c <= 200000 && u_top.u_csr.mcause != last_mcause && u_top.u_csr.mcause != 0) begin
            trap_count <= trap_count + 1;
            last_mcause <= u_top.u_csr.mcause;
            $display("[%5d] TRAP #%0d: mcause=%h mepc=0x%08h",
                     c, trap_count + 1, u_top.u_csr.mcause, u_top.u_csr.mepc);
            $fflush();
        end
    end
end

initial begin
    clk   = 0;
    rst_n = 0;
    #15 rst_n = 1;
    #20000000;
    $display("TIMEOUT c=%0d traps=%0d", c, trap_count);
    $fflush();
    $finish;
end

endmodule