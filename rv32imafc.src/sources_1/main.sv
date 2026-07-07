module main;

    logic        clk;
    logic        rst_n;

    logic [31:0] a, b, result;
    logic [4:0]  alu_op;
    logic        zero, lt, ltu;

    alu u_alu (.*);

    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        rst_n = 0;
        #12 rst_n = 1;

        $display("=== RV32I ALU Test ===");

        a <= 32'h12345678;
        b <= 32'h00FF00FF;

        @(posedge clk);
        alu_op <= 5'b00000;
        @(posedge clk);
        $display("ADD: 0x%08x", result);

        alu_op <= 5'b00001;
        @(posedge clk);
        $display("SUB: 0x%08x", result);

        a <= 32'hF0000000;
        b <= 32'h00000001;
        alu_op <= 5'b00100;
        @(posedge clk);
        $display("SLL: 0x%08x", result);

        a <= 32'h80000000;
        b <= 32'h00000000;
        alu_op <= 5'b00010;
        @(posedge clk);
        $display("SLT (1): 0x%08x", result);

        a <= 32'h00000001;
        b <= 32'h80000000;
        alu_op <= 5'b00010;
        @(posedge clk);
        $display("SLT (2): 0x%08x", result);

        a <= 32'h00000001;
        b <= 32'h80000000;
        alu_op <= 5'b00011;
        @(posedge clk);
        $display("SLTU: 0x%08x", result);

        a <= 32'h12345678;
        b <= 32'h00FF00FF;
        alu_op <= 5'b00101;
        @(posedge clk);
        $display("XOR: 0x%08x", result);

        alu_op <= 5'b00110;
        @(posedge clk);
        $display("SRL: 0x%08x", result);

        a <= 32'hF0000000;
        b <= 32'h00000004;
        alu_op <= 5'b00111;
        @(posedge clk);
        $display("SRA: 0x%08x", result);

        a <= 32'h12345678;
        b <= 32'h00FF00FF;
        alu_op <= 5'b01000;
        @(posedge clk);
        $display("OR:  0x%08x", result);

        alu_op <= 5'b01001;
        @(posedge clk);
        $display("AND: 0x%08x", result);

        #20;
        $display("=== Test Complete ===");
        $finish;
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, main);
    end

endmodule
