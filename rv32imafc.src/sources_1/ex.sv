module ex_stage (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] id_pc,
    input  logic [4:0]  id_rs1_addr,
    input  logic [4:0]  id_rs2_addr,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [31:0] id_imm,
    input  logic [4:0]  id_alu_op,
    input  logic [1:0]  id_alu_a_sel,
    input  logic [1:0]  id_alu_b_sel,
    input  logic [4:0]  id_rd_addr,
    input  logic        id_rd_we,
    input  logic        id_mem_read,
    input  logic        id_mem_write,
    input  logic [2:0]  id_mem_type,
    input  logic        id_valid,
    input  logic        id_ebreak,
    input  logic        id_ecall,
    input  logic        id_mret,

    output logic [31:0] ex_pc,
    output logic [31:0] ex_alu_result,
    output logic [31:0] ex_rs2_data,
    output logic [4:0]  ex_rd_addr,
    output logic        ex_rd_we,
    output logic        ex_mem_read,
    output logic        ex_mem_write,
    output logic [2:0]  ex_mem_type,
    output logic        ex_valid,
    output logic        ex_ebreak,
    output logic        ex_ecall,
    output logic        ex_mret,
    output logic        ex_done,

    input  logic [11:0] id_csr_addr,
    input  logic [2:0]  id_csr_op,
    input  logic [31:0] id_csr_rdata,
    output logic [11:0] ex_csr_addr,
    output logic [2:0]  ex_csr_op,
    output logic [31:0] ex_csr_rdata,
    output logic [31:0] ex_csr_wdata,

    input  logic [1:0]  id_branch_op,
    input  logic [2:0]  id_branch_f3,
    output logic        ex_branch_taken,
    output logic [31:0] ex_branch_target,
    input  logic        ex_flush
);

    logic [31:0] alu_a, alu_b;
    logic        alu_zero, alu_lt, alu_ltu;

    logic [31:0] ex_rs1_data_q, ex_rs2_data_q, ex_imm_q;
    logic [4:0]  ex_alu_op_q;
    logic [1:0]  ex_alu_a_sel_q, ex_alu_b_sel_q;

    logic [31:0] alu_result;
    logic [11:0] ex_csr_addr_q;
    logic [2:0]  ex_csr_op_q;
    logic [31:0] ex_csr_rdata_q;

    logic [1:0]  ex_branch_op_q;
    logic [2:0]  ex_branch_f3_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc          <= 32'h0;
            ex_rs2_data    <= 32'h0;
            ex_rd_addr     <= 5'h0;
            ex_rd_we       <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_mem_type    <= 3'h0;
            ex_valid       <= 1'b0;
            ex_ebreak      <= 1'b0;
            ex_ecall       <= 1'b0;
            ex_mret        <= 1'b0;
            ex_done        <= 1'b0;
            ex_rs1_data_q  <= 32'h0;
            ex_rs2_data_q  <= 32'h0;
            ex_imm_q       <= 32'h0;
            ex_alu_op_q    <= 5'h0;
            ex_alu_a_sel_q <= 2'h0;
            ex_alu_b_sel_q <= 2'h0;
            ex_csr_addr_q  <= 12'h0;
            ex_csr_op_q    <= 3'h0;
            ex_csr_rdata_q <= 32'h0;
            ex_branch_op_q <= 2'h0;
            ex_branch_f3_q <= 3'h0;
        end else if (ex_flush || (ex_branch_taken && ex_valid)) begin
            ex_pc          <= 32'h0;
            ex_valid       <= 1'b0;
            ex_rd_we       <= 1'b0;
            ex_rd_addr     <= 5'h0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_ebreak      <= 1'b0;
            ex_ecall       <= 1'b0;
            ex_mret        <= 1'b0;
            ex_rs1_data_q  <= 32'h0;
            ex_rs2_data_q  <= 32'h0;
            ex_imm_q       <= 32'h0;
            ex_alu_op_q    <= 5'h0;
            ex_alu_a_sel_q <= 2'h0;
            ex_alu_b_sel_q <= 2'h0;
            ex_csr_addr_q  <= 12'h0;
            ex_csr_op_q    <= 3'h0;
            ex_csr_rdata_q <= 32'h0;
            ex_branch_op_q <= 2'h0;
            ex_branch_f3_q <= 3'h0;
        end else begin
            ex_pc          <= id_pc;
            ex_rs2_data    <= id_rs2_data;
            ex_rd_addr     <= id_rd_addr;
            ex_rd_we       <= id_rd_we;
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
            ex_mem_type    <= id_mem_type;
            ex_valid       <= id_valid;
            ex_ebreak      <= id_ebreak;
            ex_ecall       <= id_ecall;
            ex_mret        <= id_mret;
            ex_done        <= id_valid;
            ex_rs1_data_q  <= id_rs1_data;
            ex_rs2_data_q  <= id_rs2_data;
            ex_imm_q       <= id_imm;
            ex_alu_op_q    <= id_alu_op;
            ex_alu_a_sel_q <= id_alu_a_sel;
            ex_alu_b_sel_q <= id_alu_b_sel;
            ex_csr_addr_q  <= id_csr_addr;
            ex_csr_op_q    <= id_csr_op;
            ex_csr_rdata_q <= id_csr_rdata;
            ex_branch_op_q <= id_branch_op;
            ex_branch_f3_q <= id_branch_f3;
        end
    end

    always_comb begin
        case (ex_alu_a_sel_q)
            2'b00: alu_a = ex_rs1_data_q;
            2'b01: alu_a = 32'h0;
            2'b10: alu_a = ex_pc;
            default: alu_a = 32'h0;
        endcase

        case (ex_alu_b_sel_q)
            2'b00: alu_b = ex_rs2_data_q;
            2'b01: alu_b = ex_imm_q;
            2'b10: alu_b = 32'h4;
            default: alu_b = 32'h0;
        endcase
    end

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .alu_op (ex_alu_op_q),
        .result (alu_result),
        .zero   (alu_zero),
        .lt     (alu_lt),
        .ltu    (alu_ltu)
    );

    always_comb begin
        unique case (ex_csr_op_q)
            3'b001: ex_csr_wdata = ex_rs1_data_q;
            3'b010: ex_csr_wdata = ex_csr_rdata_q | ex_rs1_data_q;
            3'b011: ex_csr_wdata = ex_csr_rdata_q & ~ex_rs1_data_q;
            3'b101: ex_csr_wdata = ex_imm_q;
            3'b110: ex_csr_wdata = ex_csr_rdata_q | ex_imm_q;
            3'b111: ex_csr_wdata = ex_csr_rdata_q & ~ex_imm_q;
            default: ex_csr_wdata = 32'h0;
        endcase
    end

    assign ex_csr_addr  = ex_csr_addr_q;
    assign ex_csr_op    = ex_csr_op_q;
    assign ex_csr_rdata = ex_csr_rdata_q;

    assign ex_alu_result = (ex_csr_op_q != 3'h0) ? ex_csr_rdata_q : alu_result;

    // Branch/jump target and condition
    always_comb begin
        ex_branch_taken  = 1'b0;
        ex_branch_target = 32'h0;

        unique case (ex_branch_op_q)
            2'b01: begin
                ex_branch_target = ex_pc + ex_imm_q;
                unique case (ex_branch_f3_q)
                    3'b000: ex_branch_taken = alu_zero;
                    3'b001: ex_branch_taken = ~alu_zero;
                    3'b100: ex_branch_taken = alu_lt;
                    3'b101: ex_branch_taken = ~alu_lt;
                    3'b110: ex_branch_taken = alu_ltu;
                    3'b111: ex_branch_taken = ~alu_ltu;
                    default: ex_branch_taken = 1'b0;
                endcase
            end
            2'b10: begin
                ex_branch_taken  = 1'b1;
                ex_branch_target = ex_pc + ex_imm_q;
            end
            2'b11: begin
                ex_branch_taken  = 1'b1;
                ex_branch_target = (ex_rs1_data_q + ex_imm_q) & 32'hfffffffe;
            end
            default: ;
        endcase
    end

endmodule