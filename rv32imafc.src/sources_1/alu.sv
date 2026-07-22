module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [5:0]  alu_op,
    output logic [31:0] result,
    output logic        zero,
    output logic        lt,
    output logic        ltu
);

    localparam ALU_ADD      = 6'b00_0000;
    localparam ALU_SUB      = 6'b00_0001;
    localparam ALU_SLL      = 6'b00_0100;
    localparam ALU_SLT      = 6'b00_0010;
    localparam ALU_SLTU     = 6'b00_0011;
    localparam ALU_XOR      = 6'b00_0101;
    localparam ALU_SRL      = 6'b00_0110;
    localparam ALU_SRA      = 6'b00_0111;
    localparam ALU_OR       = 6'b00_1000;
    localparam ALU_AND      = 6'b00_1001;
    localparam ALU_CZERO_EQZ = 6'b00_1010;
    localparam ALU_CZERO_NEZ = 6'b00_1011;

    // Zba
    localparam ALU_SH1ADD   = 6'b01_0000;
    localparam ALU_SH2ADD   = 6'b01_0001;
    localparam ALU_SH3ADD   = 6'b01_0010;

    // Zbb logic-neg
    localparam ALU_ANDN     = 6'b01_0011;
    localparam ALU_ORN      = 6'b01_0100;
    localparam ALU_XNOR     = 6'b01_0101;

    // Zbb min/max
    localparam ALU_MIN      = 6'b01_0110;
    localparam ALU_MINU     = 6'b01_0111;
    localparam ALU_MAX      = 6'b01_1000;
    localparam ALU_MAXU     = 6'b01_1001;

    // Zbb rotates
    localparam ALU_ROL      = 6'b01_1010;
    localparam ALU_ROR      = 6'b01_1011;

    // Zbb unary
    localparam ALU_CLZ      = 6'b01_1100;
    localparam ALU_CTZ      = 6'b01_1101;
    localparam ALU_CPOP     = 6'b01_1110;
    localparam ALU_SEXT_B   = 6'b01_1111;
    localparam ALU_SEXT_H   = 6'b10_0000;
    localparam ALU_ZEXT_H   = 6'b10_0001;
    localparam ALU_ORC_B    = 6'b10_0010;
    localparam ALU_REV8     = 6'b10_0011;

    // Zbs
    localparam ALU_BSET     = 6'b10_0100;
    localparam ALU_BCLR     = 6'b10_0101;
    localparam ALU_BINV     = 6'b10_0110;
    localparam ALU_BEXT     = 6'b10_0111;

    logic [31:0] shamt;
    assign shamt = b[4:0];

    always_comb begin
        case (alu_op)
            ALU_ADD:   result = a + b;
            ALU_SUB:   result = a - b;
            ALU_SLL:   result = a << shamt;
            ALU_SLT:   result = $signed(a) < $signed(b);
            ALU_SLTU:  result = a < b;
            ALU_XOR:   result = a ^ b;
            ALU_SRL:   result = a >> shamt;
            ALU_SRA:   result = $signed(a) >>> shamt;
            ALU_OR:    result = a | b;
            ALU_AND:   result = a & b;
            ALU_CZERO_EQZ: result = (b == 32'b0) ? a : 32'b0;
            ALU_CZERO_NEZ: result = (b != 32'b0) ? a : 32'b0;

            // Zba
            ALU_SH1ADD: result = b + (a << 1);
            ALU_SH2ADD: result = b + (a << 2);
            ALU_SH3ADD: result = b + (a << 3);

            // Zbb logic-neg
            ALU_ANDN:   result = a & ~b;
            ALU_ORN:    result = a | ~b;
            ALU_XNOR:   result = ~(a ^ b);

            // Zbb min/max
            ALU_MIN:    result = ($signed(a) < $signed(b)) ? a : b;
            ALU_MINU:   result = (a < b) ? a : b;
            ALU_MAX:    result = ($signed(a) < $signed(b)) ? b : a;
            ALU_MAXU:   result = (a < b) ? b : a;

            // Zbb rotates
            ALU_ROL:    result = (a << shamt) | (a >> (32'd32 - shamt));
            ALU_ROR:    result = (a >> shamt) | (a << (32'd32 - shamt));

            // Zbb unary
            ALU_CLZ: begin
                result = 32'd32;
                for (int i = 0; i < 32; i++)
                    if (a[31-i]) result = 32'(i);
            end
            ALU_CTZ: begin
                result = 32'd32;
                for (int i = 0; i < 32; i++)
                    if (a[i]) result = 32'(i);
            end
            ALU_CPOP: begin
                result = 32'd0;
                for (int i = 0; i < 32; i++)
                    if (a[i]) result = result + 32'd1;
            end
            ALU_SEXT_B: result = {{24{a[7]}}, a[7:0]};
            ALU_SEXT_H: result = {{16{a[15]}}, a[15:0]};
            ALU_ZEXT_H: result = {16'h0, a[15:0]};
            ALU_ORC_B:  result = {|a[31:24] ? 8'hFF : 8'h00,
                                  |a[23:16] ? 8'hFF : 8'h00,
                                  |a[15:8]  ? 8'hFF : 8'h00,
                                  |a[7:0]   ? 8'hFF : 8'h00};
            ALU_REV8:   result = {a[7:0], a[15:8], a[23:16], a[31:24]};

            // Zbs
            ALU_BSET:   result = a | (32'd1 << shamt);
            ALU_BCLR:   result = a & ~(32'd1 << shamt);
            ALU_BINV:   result = a ^ (32'd1 << shamt);
            ALU_BEXT:   result = (a >> shamt) & 32'd1;

            default:   result = '0;
        endcase
    end

    assign zero = (result == 32'b0);
    assign lt   = $signed(a) < $signed(b);
    assign ltu  = a < b;

endmodule
