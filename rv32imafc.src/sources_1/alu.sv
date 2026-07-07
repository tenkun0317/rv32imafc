module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [4:0]  alu_op,
    output logic [31:0] result,
    output logic        zero,
    output logic        lt,
    output logic        ltu
);

    localparam ALU_ADD  = 5'b00000;
    localparam ALU_SUB  = 5'b00001;
    localparam ALU_SLL  = 5'b00100;
    localparam ALU_SLT  = 5'b00010;
    localparam ALU_SLTU = 5'b00011;
    localparam ALU_XOR  = 5'b00101;
    localparam ALU_SRL  = 5'b00110;
    localparam ALU_SRA  = 5'b00111;
    localparam ALU_OR   = 5'b01000;
    localparam ALU_AND  = 5'b01001;

    logic [31:0] shamt;

    assign shamt = b[4:0];

    always_comb begin
        case (alu_op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_SLL:  result = a << shamt;
            ALU_SLT:  result = $signed(a) < $signed(b);
            ALU_SLTU: result = a < b;
            ALU_XOR:  result = a ^ b;
            ALU_SRL:  result = a >> shamt;
            ALU_SRA:  result = $signed(a) >>> shamt;
            ALU_OR:   result = a | b;
            ALU_AND:  result = a & b;
            default:  result = '0;
        endcase
    end

    assign zero = (result == 32'b0);
    assign lt   = $signed(a) < $signed(b);
    assign ltu  = a < b;

endmodule
