module if_stage (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] instr_dout,

    input  logic        branch_taken,
    input  logic [31:0] branch_target,

    input  logic        trap_taken,
    input  logic [31:0] trap_target,

    output logic [31:0] if_pc,
    output logic [31:0] if_instr
);

    logic [31:0] pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h80000000;
        end else if (trap_taken) begin
            pc <= trap_target;
        end else if (branch_taken) begin
            pc <= branch_target;
        end else begin
            pc <= pc + 4;
        end
    end

    assign if_pc    = pc;
    assign if_instr = instr_dout;

endmodule
