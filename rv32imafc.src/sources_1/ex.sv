module ex_stage (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] id_pc,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [31:0] id_imm,
    input  logic [5:0]  id_alu_op,
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
    input  logic        id_illegal,
    input  logic        id_if_access_fault,
    input  logic        id_mul_div,
    input  logic        id_amo,
    input  logic [4:0]  id_amo_op,
    input  logic [11:0] id_csr_addr,
    input  logic [2:0]  id_csr_op,
    input  logic [31:0] id_csr_rdata,
    input  logic [1:0]  id_branch_op,
    input  logic [2:0]  id_branch_f3,
    input  logic        ex_flush,
    input  logic        ex_stall_i,
    input  logic        ex_out_stall_i,

    output logic [31:0] ex_pc,
    output logic [31:0] ex_alu_result,
    output logic [31:0] ex_rs2_data,
    output logic [4:0]  ex_rd_addr,
    output logic        ex_rd_we,
    output logic        ex_mem_read,
    output logic        ex_mem_write,
    output logic [2:0]  ex_mem_type,
    output logic        ex_amo,
    output logic [4:0]  ex_amo_op,
    output logic        ex_valid,
    output logic        ex_ebreak,
    output logic        ex_ecall,
    output logic        ex_mret,
    output logic        ex_illegal,
    output logic        ex_if_access_fault,
    output logic        ex_done,
    output logic        ex_stall,

    output logic [11:0] ex_csr_addr,
    output logic [2:0]  ex_csr_op,
    output logic [31:0] ex_csr_rdata,
    output logic [31:0] ex_csr_wdata,

    output logic        ex_branch_taken,
    output logic [31:0] ex_branch_target,

    output logic [4:0]  ex_fwd_rd_addr,
    output logic        ex_fwd_rd_we,
    output logic        ex_fwd_mem_read,
    output logic        ex_fwd_valid,
    output logic [31:0] ex_alu_fwd
);

    // ================================================================
    //  Input registers (capture from ID on each clock edge)
    // ================================================================
    logic [31:0] ex_pc_q;
    logic [31:0] ex_rs1_data_q;
    logic [31:0] ex_rs2_data_q;
    logic [31:0] ex_imm_q;
    logic [5:0]  ex_alu_op_q;
    logic [1:0]  ex_alu_a_sel_q;
    logic [1:0]  ex_alu_b_sel_q;
    logic [4:0]  ex_rd_addr_q;
    logic        ex_rd_we_q;
    logic        ex_mem_read_q;
    logic        ex_mem_write_q;
    logic [2:0]  ex_mem_type_q;
    logic        ex_valid_q;
    logic        ex_ebreak_q;
    logic        ex_ecall_q;
    logic        ex_mret_q;
    logic        ex_illegal_q;
    logic        ex_if_access_fault_q;
    logic        ex_mul_div_q;
    logic        ex_amo_q;
    logic [4:0]  ex_amo_op_q;
    logic [11:0] ex_csr_addr_q;
    logic [2:0]  ex_csr_op_q;
    logic [31:0] ex_csr_rdata_q;
    logic [1:0]  ex_branch_op_q;
    logic [2:0]  ex_branch_f3_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc_q         <= 32'h0;
            ex_rs1_data_q   <= 32'h0;
            ex_rs2_data_q   <= 32'h0;
            ex_imm_q        <= 32'h0;
            ex_alu_op_q     <= 6'h0;
            ex_alu_a_sel_q  <= 2'h0;
            ex_alu_b_sel_q  <= 2'h0;
            ex_rd_addr_q    <= 5'h0;
            ex_rd_we_q      <= 1'b0;
            ex_mem_read_q   <= 1'b0;
            ex_mem_write_q  <= 1'b0;
            ex_mem_type_q   <= 3'h0;
            ex_valid_q      <= 1'b0;
            ex_ebreak_q     <= 1'b0;
            ex_ecall_q      <= 1'b0;
            ex_mret_q       <= 1'b0;
            ex_illegal_q    <= 1'b0;
            ex_if_access_fault_q <= 1'b0;
            ex_mul_div_q    <= 1'b0;
            ex_amo_q        <= 1'b0;
            ex_amo_op_q     <= 5'h0;
            ex_csr_addr_q   <= 12'h0;
            ex_csr_op_q     <= 3'h0;
            ex_csr_rdata_q  <= 32'h0;
            ex_branch_op_q  <= 2'h0;
            ex_branch_f3_q  <= 3'h0;
        end else if (ex_flush || (ex_branch_taken && ex_valid)) begin
            ex_pc_q         <= 32'h0;
            ex_rs1_data_q   <= 32'h0;
            ex_rs2_data_q   <= 32'h0;
            ex_imm_q        <= 32'h0;
            ex_alu_op_q     <= 6'h0;
            ex_alu_a_sel_q  <= 2'h0;
            ex_alu_b_sel_q  <= 2'h0;
            ex_rd_addr_q    <= 5'h0;
            ex_rd_we_q      <= 1'b0;
            ex_mem_read_q   <= 1'b0;
            ex_mem_write_q  <= 1'b0;
            ex_mem_type_q   <= 3'h0;
            ex_valid_q      <= 1'b0;
            ex_ebreak_q     <= 1'b0;
            ex_ecall_q      <= 1'b0;
            ex_mret_q       <= 1'b0;
            ex_illegal_q    <= 1'b0;
            ex_if_access_fault_q <= 1'b0;
            ex_mul_div_q    <= 1'b0;
            ex_amo_q        <= 1'b0;
            ex_amo_op_q     <= 5'h0;
            ex_csr_addr_q   <= 12'h0;
            ex_csr_op_q     <= 3'h0;
            ex_csr_rdata_q  <= 32'h0;
            ex_branch_op_q  <= 2'h0;
            ex_branch_f3_q  <= 3'h0;
        end else if (ex_stall_i) begin
        end else begin
            ex_pc_q         <= id_pc;
            ex_rs1_data_q   <= id_rs1_data;
            ex_rs2_data_q   <= id_rs2_data;
            ex_imm_q        <= id_imm;
            ex_alu_op_q     <= id_alu_op;
            ex_alu_a_sel_q  <= id_alu_a_sel;
            ex_alu_b_sel_q  <= id_alu_b_sel;
            ex_rd_addr_q    <= id_rd_addr;
            ex_rd_we_q      <= id_rd_we;
            ex_mem_read_q   <= id_mem_read;
            ex_mem_write_q  <= id_mem_write;
            ex_mem_type_q   <= id_mem_type;
            ex_valid_q      <= id_valid;
            ex_ebreak_q     <= id_ebreak;
            ex_ecall_q      <= id_ecall;
            ex_mret_q       <= id_mret;
            ex_illegal_q    <= id_illegal;
            ex_if_access_fault_q <= id_if_access_fault;
            ex_mul_div_q    <= id_mul_div;
            ex_amo_q        <= id_amo;
            ex_amo_op_q     <= id_amo_op;
            ex_csr_addr_q   <= id_csr_addr;
            ex_csr_op_q     <= id_csr_op;
            ex_csr_rdata_q  <= id_csr_rdata;
            ex_branch_op_q  <= id_branch_op;
            ex_branch_f3_q  <= id_branch_f3;
        end
    end

    // ================================================================
    //  ALU (combinational from input registers)
    // ================================================================
    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_result;
    logic        alu_zero, alu_lt, alu_ltu;

    always_comb begin
        case (ex_alu_a_sel_q)
            2'b00: alu_a = ex_rs1_data_q;
            2'b01: alu_a = 32'h0;
            2'b10: alu_a = ex_pc_q;
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

    // ================================================================
    //  Multi-cycle units (DIV, MUL)
    // ================================================================
    wire        is_div_rem;
    wire        div_busy;
    wire [31:0] div_quotient, div_remainder;
    logic       div_start;
    logic       stall_extra;

    wire        is_mul;
    wire        mul_busy;
    wire [31:0] mul_result;
    logic       mul_start;
    logic       mul_stall_extra;

    assign is_div_rem = ex_mul_div_q && (ex_alu_op_q inside {5'b01110, 5'b01111, 5'b10000, 5'b10001});
    assign div_start  = is_div_rem && ex_valid_q;

    assign is_mul     = ex_mul_div_q && (ex_alu_op_q inside {5'b01010, 5'b01011, 5'b01100, 5'b01101});
    assign mul_start  = is_mul && ex_valid_q;

    div u_div (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (div_start),
        .dividend (ex_rs1_data_q),
        .divisor  (ex_rs2_data_q),
        .is_signed(ex_alu_op_q inside {5'b01110, 5'b10000}),
        .quotient (div_quotient),
        .remainder(div_remainder),
        .busy     (div_busy)
    );

    mul u_mul (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (mul_start),
        .a           (ex_rs1_data_q),
        .b           (ex_rs2_data_q),
        .is_signed_a (ex_alu_op_q inside {5'b01010, 5'b01011, 5'b01100}),
        .is_signed_b (ex_alu_op_q inside {5'b01010, 5'b01011}),
        .sel_hi      (ex_alu_op_q inside {5'b01011, 5'b01100, 5'b01101}),
        .result      (mul_result),
        .busy        (mul_busy)
    );

    // ================================================================
    //  Stall tracking
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stall_extra <= 1'b0;
        else if (is_div_rem && div_busy)
            stall_extra <= 1'b1;
        else
            stall_extra <= 1'b0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mul_stall_extra <= 1'b0;
        else if (is_mul && mul_busy)
            mul_stall_extra <= 1'b1;
        else
            mul_stall_extra <= 1'b0;
    end

    // ================================================================
    //  Result selector (combinational)
    // ================================================================
    logic [31:0] alu_or_div_result;
    always_comb begin
        if (is_mul) begin
            alu_or_div_result = mul_result;
        end else begin
            unique case (ex_alu_op_q)
                5'b01110, 5'b01111:
                    alu_or_div_result = div_quotient;
                5'b10000, 5'b10001:
                    alu_or_div_result = div_remainder;
                default:
                    alu_or_div_result = alu_result;
            endcase
        end
    end

    // ================================================================
    //  Output registers (capture final results + control passthrough)
    // ================================================================
    logic        ex_out_valid_q, ex_out_ebreak_q, ex_out_ecall_q, ex_out_mret_q, ex_out_illegal_q, ex_out_if_access_fault_q;
    logic [31:0] ex_out_pc_q, ex_out_alu_result_q, ex_out_rs2_q;
    logic [4:0]  ex_out_rd_addr_q;
    logic        ex_out_rd_we_q, ex_out_mem_read_q, ex_out_mem_write_q;
    logic [2:0]  ex_out_mem_type_q;
    logic [11:0] ex_out_csr_addr_q;
    logic [2:0]  ex_out_csr_op_q;
    logic [31:0] ex_out_csr_rdata_q;
    logic [1:0]  ex_out_branch_op_q;
    logic [2:0]  ex_out_branch_f3_q;
    logic [31:0] ex_out_rs1_q, ex_out_imm_q;
    logic        ex_out_amo_q;
    logic [4:0]  ex_out_amo_op_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_out_pc_q          <= 32'h0;
            ex_out_alu_result_q  <= 32'h0;
            ex_out_rs1_q         <= 32'h0;
            ex_out_rs2_q         <= 32'h0;
            ex_out_imm_q         <= 32'h0;
            ex_out_rd_addr_q     <= 5'h0;
            ex_out_rd_we_q       <= 1'b0;
            ex_out_mem_read_q    <= 1'b0;
            ex_out_mem_write_q   <= 1'b0;
            ex_out_mem_type_q    <= 3'h0;
            ex_out_valid_q       <= 1'b0;
            ex_out_ebreak_q      <= 1'b0;
            ex_out_ecall_q       <= 1'b0;
            ex_out_mret_q        <= 1'b0;
            ex_out_illegal_q     <= 1'b0;
            ex_out_if_access_fault_q <= 1'b0;
            ex_out_csr_addr_q    <= 12'h0;
            ex_out_csr_op_q      <= 3'h0;
            ex_out_csr_rdata_q   <= 32'h0;
            ex_out_branch_op_q   <= 2'h0;
            ex_out_branch_f3_q   <= 3'h0;
            ex_out_amo_q        <= 1'b0;
            ex_out_amo_op_q     <= 5'h0;
        end else if (ex_flush) begin
            // External flush (older branch/jump squashed this instruction).
            // The branch/jump instruction itself is handled by the else
            // branch below so its link-register write and result advance
            // into MEM/WB normally.
            ex_out_pc_q          <= 32'h0;
            ex_out_alu_result_q  <= 32'h0;
            ex_out_rs1_q         <= 32'h0;
            ex_out_rs2_q         <= 32'h0;
            ex_out_imm_q         <= 32'h0;
            ex_out_rd_addr_q     <= 5'h0;
            ex_out_rd_we_q       <= 1'b0;
            ex_out_mem_read_q    <= 1'b0;
            ex_out_mem_write_q   <= 1'b0;
            ex_out_mem_type_q    <= 3'h0;
            ex_out_valid_q       <= 1'b0;
            ex_out_ebreak_q      <= 1'b0;
            ex_out_ecall_q       <= 1'b0;
            ex_out_mret_q        <= 1'b0;
            ex_out_illegal_q     <= 1'b0;
            ex_out_if_access_fault_q <= 1'b0;
            ex_out_csr_addr_q    <= 12'h0;
            ex_out_csr_op_q      <= 3'h0;
            ex_out_csr_rdata_q   <= 32'h0;
            ex_out_branch_op_q   <= 2'h0;
            ex_out_branch_f3_q   <= 3'h0;
            ex_out_amo_q        <= 1'b0;
            ex_out_amo_op_q     <= 5'h0;
        end else if (ex_out_stall_i) begin
            // Hold during AMO multi-cycle operation
        end else begin
            // Normal capture — also reached when THIS instruction is a
            // taken branch/jump, so its own link-register write (rd_we)
            // and ALU result (e.g. PC+4) proceed to MEM/WB.
            ex_out_pc_q          <= ex_pc_q;
            ex_out_alu_result_q  <= (ex_csr_op_q != 3'h0) ? ex_csr_rdata_q : alu_or_div_result;
            ex_out_rs1_q         <= ex_rs1_data_q;
            ex_out_rs2_q         <= ex_rs2_data_q;
            ex_out_imm_q         <= ex_imm_q;
            ex_out_rd_addr_q     <= ex_rd_addr_q;
            ex_out_rd_we_q       <= ex_rd_we_q;
            ex_out_mem_read_q    <= ex_mem_read_q;
            ex_out_mem_write_q   <= ex_mem_write_q;
            ex_out_mem_type_q    <= ex_mem_type_q;
            ex_out_valid_q       <= ex_valid_q && !(is_div_rem && div_busy) && !(is_mul && mul_busy);
            ex_out_ebreak_q      <= ex_ebreak_q;
            ex_out_ecall_q       <= ex_ecall_q;
            ex_out_mret_q        <= ex_mret_q;
            ex_out_illegal_q     <= ex_illegal_q;
            ex_out_if_access_fault_q <= ex_if_access_fault_q;
            ex_out_csr_addr_q    <= ex_csr_addr_q;
            ex_out_csr_op_q      <= ex_csr_op_q;
            ex_out_csr_rdata_q   <= ex_csr_rdata_q;
            ex_out_branch_op_q   <= ex_branch_op_q;
            ex_out_branch_f3_q   <= ex_branch_f3_q;
            ex_out_amo_q        <= ex_amo_q;
            ex_out_amo_op_q     <= ex_amo_op_q;
        end
    end

    // ================================================================
    //  Output assignments (from output registers)
    // ================================================================
    assign ex_pc        = ex_out_pc_q;
    assign ex_alu_result = ex_out_alu_result_q;
    assign ex_rs2_data  = ex_out_rs2_q;
    assign ex_rd_addr   = ex_out_rd_addr_q;
    // A taken JAL/JALR flushes only younger instructions.  Its own link
    // register write must still advance into MEM/WB so that a later `ret`
    // uses the return address produced by the call.
    assign ex_rd_we     = ex_out_rd_we_q;
    assign ex_mem_read  = ex_out_mem_read_q;
    assign ex_mem_write = ex_out_mem_write_q;
    assign ex_mem_type  = ex_out_mem_type_q;
    assign ex_amo       = ex_out_amo_q;
    assign ex_amo_op    = ex_out_amo_op_q;
    assign ex_valid     = ex_out_valid_q;
    assign ex_ebreak    = ex_out_ebreak_q;
    assign ex_ecall     = ex_out_ecall_q;
    assign ex_mret      = ex_out_mret_q;
    assign ex_illegal   = ex_out_illegal_q;
    assign ex_if_access_fault = ex_out_if_access_fault_q;
    assign ex_csr_addr  = ex_out_csr_addr_q;
    assign ex_csr_op    = ex_out_csr_op_q;
    assign ex_csr_rdata = ex_out_csr_rdata_q;

    // ================================================================
    //  Stall / done
    // ================================================================
    assign ex_stall = (is_div_rem && (div_start || div_busy || stall_extra)) || (is_mul && (mul_start || mul_busy || mul_stall_extra));
    assign ex_done  = is_mul    ? (mul_stall_extra && !mul_busy)
                    : is_div_rem ? (stall_extra && !div_busy)
                    : ex_valid_q;

    // ================================================================
    //  CSR write-data (combinational from output registers)
    // ================================================================
    always_comb begin
        unique case (ex_out_csr_op_q)
            3'b001: ex_csr_wdata = ex_out_rs1_q;
            3'b010: ex_csr_wdata = ex_out_csr_rdata_q | ex_out_rs1_q;
            3'b011: ex_csr_wdata = ex_out_csr_rdata_q & ~ex_out_rs1_q;
            3'b101: ex_csr_wdata = ex_out_imm_q;
            3'b110: ex_csr_wdata = ex_out_csr_rdata_q | ex_out_imm_q;
            3'b111: ex_csr_wdata = ex_out_csr_rdata_q & ~ex_out_imm_q;
            default: ex_csr_wdata = 32'h0;
        endcase
    end

    // ================================================================
    //  Branch logic (combinational from output registers)
    // ================================================================
    logic ex_zero_q, ex_lt_q, ex_ltu_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_zero_q <= 1'b0;
            ex_lt_q   <= 1'b0;
            ex_ltu_q  <= 1'b0;
        end else if (ex_flush || (ex_branch_taken && ex_valid)) begin
            ex_zero_q <= 1'b0;
            ex_lt_q   <= 1'b0;
            ex_ltu_q  <= 1'b0;
        end else if (ex_out_stall_i) begin
        end else begin
            ex_zero_q <= alu_zero;
            ex_lt_q   <= alu_lt;
            ex_ltu_q  <= alu_ltu;
        end
    end

    always_comb begin
        ex_branch_taken  = 1'b0;
        ex_branch_target = 32'h0;

        unique case (ex_out_branch_op_q)
            2'b01: begin
                ex_branch_target = ex_out_pc_q + ex_out_imm_q;
                unique case (ex_out_branch_f3_q)
                    3'b000: ex_branch_taken = ex_zero_q;
                    3'b001: ex_branch_taken = ~ex_zero_q;
                    3'b100: ex_branch_taken = ex_lt_q;
                    3'b101: ex_branch_taken = ~ex_lt_q;
                    3'b110: ex_branch_taken = ex_ltu_q;
                    3'b111: ex_branch_taken = ~ex_ltu_q;
                    default: ex_branch_taken = 1'b0;
                endcase
            end
            2'b10: begin
                ex_branch_taken  = 1'b1;
                ex_branch_target = ex_out_pc_q + ex_out_imm_q;
            end
            2'b11: begin
                ex_branch_taken  = 1'b1;
                ex_branch_target = (ex_out_rs1_q + ex_out_imm_q) & 32'hfffffffe;
            end
            default: ;
        endcase
    end

    // ================================================================
    //  Forwarding (combinational from input registers + ALU)
    // ================================================================
    assign ex_fwd_rd_addr  = ex_rd_addr_q;
    assign ex_fwd_rd_we    = ex_rd_we_q;
    assign ex_fwd_mem_read = ex_mem_read_q;
    assign ex_fwd_valid    = ex_valid_q;
    assign ex_alu_fwd      = alu_result;

endmodule
