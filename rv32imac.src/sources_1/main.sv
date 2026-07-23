module main;

    logic        clk;
    logic        rst_n;

    logic [31:0] a, b, result;
    logic [5:0]  alu_op;
    logic        zero, lt, ltu;

    alu u_alu (.a(a), .b(b), .alu_op(alu_op), .result(result), .zero(zero), .lt(lt), .ltu(ltu));

    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        rst_n = 0;
        #12 rst_n = 1;

        $display("=== RV32I ALU Test ===");

        a = 32'h12345678;
        b = 32'h00FF00FF;
        alu_op = 5'b00000;
        #1;
        $display("ADD: a=0x%08x b=0x%08x alu_op=%b result=0x%08x zero=%b lt=%b ltu=%b", a, b, alu_op, result, zero, lt, ltu);

        alu_op = 5'b00001;
        #1;
        $display("SUB: a=0x%08x b=0x%08x alu_op=%b result=0x%08x zero=%b lt=%b ltu=%b", a, b, alu_op, result, zero, lt, ltu);

        a = 32'hF0000000;
        b = 32'h00000001;
        alu_op = 5'b00100;
        #1;
        $display("SLL: a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        a = 32'h80000000;
        b = 32'h00000000;
        alu_op = 5'b00010;
        #1;
        $display("SLT (1): a=0x%08x b=0x%08x alu_op=%b result=0x%08x lt=%b", a, b, alu_op, result, lt);

        a = 32'h00000001;
        b = 32'h80000000;
        alu_op = 5'b00010;
        #1;
        $display("SLT (2): a=0x%08x b=0x%08x alu_op=%b result=0x%08x lt=%b", a, b, alu_op, result, lt);

        a = 32'h00000001;
        b = 32'h80000000;
        alu_op = 5'b00011;
        #1;
        $display("SLTU: a=0x%08x b=0x%08x alu_op=%b result=0x%08x ltu=%b", a, b, alu_op, result, ltu);

        a = 32'h12345678;
        b = 32'h00FF00FF;
        alu_op = 5'b00101;
        #1;
        $display("XOR: a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        alu_op = 5'b00110;
        #1;
        $display("SRL: a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        a = 32'hF0000000;
        b = 32'h00000004;
        alu_op = 5'b00111;
        #1;
        $display("SRA: a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        a = 32'h12345678;
        b = 32'h00FF00FF;
        alu_op = 5'b01000;
        #1;
        $display("OR:  a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        alu_op = 5'b01001;
        #1;
        $display("AND: a=0x%08x b=0x%08x alu_op=%b result=0x%08x", a, b, alu_op, result);

        #20;
        $display("=== Test Complete ===");
        $finish;
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, main);
    end

endmodule