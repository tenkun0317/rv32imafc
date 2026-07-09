module id_stage (
    input  logic [31:0] if_instr,
    input  logic        if_valid,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,

    output logic [4:0]  id_rs1_addr,
    output logic [4:0]  id_rs2_addr,
    output logic [31:0] id_imm,
    output logic [4:0]  id_alu_op,
    output logic [1:0]  id_alu_a_sel,
    output logic [1:0]  id_alu_b_sel,
    output logic [4:0]  id_rd_addr,
    output logic        id_rd_we,
    output logic        id_mem_read,
    output logic        id_mem_write,
    output logic [2:0]  id_mem_type,
    output logic        id_valid,
    output logic        id_ebreak,
    output logic        id_ecall,
    output logic        id_mret,

    output logic        ex_stall,
    input  logic        ex_done,

    input  logic [31:0] csr_rdata,
    output logic [11:0] id_csr_addr,
    output logic [2:0]  id_csr_op,
    output logic [31:0] id_csr_rdata,

    output logic [1:0]  id_branch_op,
    output logic [2:0]  id_branch_f3
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [11:0] funct12;
    logic [4:0] rd, rs1, rs2;

    assign opcode = if_instr[6:0];
    assign funct3 = if_instr[14:12];
    assign funct7 = if_instr[31:25];
    assign funct12 = if_instr[31:20];
    assign rd  = if_instr[11:7];
    assign rs1 = if_instr[19:15];
    assign rs2 = if_instr[24:20];

    assign id_rs2_addr = rs2;
    assign id_rd_addr  = rd;

    assign id_csr_rdata = csr_rdata;

    always_comb begin
        id_imm = 32'h0;
        id_alu_op = 5'b0;
        id_alu_a_sel = 2'b00;
        id_alu_b_sel = 2'b00;
        id_rd_we = 1'b0;
        id_mem_read = 1'b0;
        id_mem_write = 1'b0;
        id_mem_type = 3'b0;
        id_valid = if_valid;
        id_ebreak = 1'b0;
        id_ecall = 1'b0;
        id_mret = 1'b0;
        ex_stall = 1'b0;
        id_rs1_addr = rs1;
        id_csr_addr = 12'h0;
        id_csr_op = 3'h0;
        id_branch_op = 2'h0;
        id_branch_f3 = 3'h0;

        case (opcode)
            7'b0110111: begin
                id_imm = {if_instr[31:12], 12'h0};
                id_alu_a_sel = 2'b01;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
            end
            7'b0010111: begin
                id_imm = {if_instr[31:12], 12'h0};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
            end
             7'b1101111: begin
                id_imm = {{12{if_instr[31]}}, if_instr[19:12], if_instr[20], if_instr[30:21], 1'b0};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b10;
                id_rd_we = 1'b1;
                id_branch_op = 2'b10;
            end
             7'b1100111: begin
                id_imm = {{20{if_instr[31]}}, if_instr[31:20]};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b10;
                id_rd_we = 1'b1;
                id_branch_op = 2'b11;
            end
            7'b0000011: begin
                id_imm = {{20{if_instr[31]}}, if_instr[31:20]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
                id_mem_read = 1'b1;
                id_mem_type = funct3;
            end
            7'b0100011: begin
                id_imm = {{20{if_instr[31]}}, if_instr[31:25], if_instr[11:7]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_mem_write = 1'b1;
                id_mem_type = funct3;
            end
             7'b1100011: begin
                id_imm = {{20{if_instr[31]}}, if_instr[31], if_instr[7], if_instr[30:25], if_instr[11:8], 1'b0};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b00;
                id_alu_op = 5'b00001;
                id_branch_op = 2'b01;
                id_branch_f3 = funct3;
            end
            7'b0010011: begin
                id_imm = {{20{if_instr[31]}}, if_instr[31:20]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
                case (funct3)
                    3'b000: id_alu_op = 5'b00000;
                    3'b010: id_alu_op = 5'b00010;
                    3'b011: id_alu_op = 5'b00011;
                    3'b100: id_alu_op = 5'b00101;
                    3'b110: id_alu_op = 5'b01000;
                    3'b111: id_alu_op = 5'b01001;
                    3'b001: id_alu_op = 5'b00100;
                    3'b101: begin
                        if (funct7[5]) id_alu_op = 5'b00111;
                        else id_alu_op = 5'b00110;
                    end
                    default: id_alu_op = 5'b0;
                endcase
            end
            7'b0110011: begin
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b00;
                id_rd_we = 1'b1;
                case (funct3)
                    3'b000: begin
                        if (funct7[5]) id_alu_op = 5'b00001;
                        else id_alu_op = 5'b00000;
                    end
                    3'b001: id_alu_op = 5'b00100;
                    3'b010: id_alu_op = 5'b00010;
                    3'b011: id_alu_op = 5'b00011;
                    3'b100: id_alu_op = 5'b00101;
                    3'b101: begin
                        if (funct7[5]) id_alu_op = 5'b00111;
                        else id_alu_op = 5'b00110;
                    end
                    3'b110: id_alu_op = 5'b01000;
                    3'b111: id_alu_op = 5'b01001;
                    default: id_alu_op = 5'b0;
                endcase
            end
            7'b1110011: begin
                if (funct3 == 3'b000) begin
                    if (funct12 == 12'h000)
                        id_ecall = 1'b1;
                    else if (funct12 == 12'h001)
                        id_ebreak = 1'b1;
                    else if (funct12 == 12'h302)
                        id_mret = 1'b1;
                end else if (funct3[2]) begin
                    // CSR immediate-variant: CSRRWI (101), CSRRSI (110), CSRRCI (111)
                    id_csr_addr = if_instr[31:20];
                    id_csr_op   = funct3;
                    id_rd_we    = 1'b1;
                    id_rs1_addr = 5'h0;
                    id_imm      = {27'h0, rs1};
                end else begin
                    // CSR register-variant: CSRRW (001), CSRRS (010), CSRRC (011)
                    id_csr_addr = if_instr[31:20];
                    id_csr_op   = funct3;
                    id_rd_we    = 1'b1;
                end
            end
        endcase
    end

endmodule