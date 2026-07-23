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
    input  logic        id_fence_i,
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

    // Zcmp signals from ID
    input  logic        id_zcmp,
    input  logic [1:0]  id_zcmp_op,
    input  logic [3:0]  id_zcmp_rlist,
    input  logic [9:0]  id_zcmp_stack_adj,
    input  logic [3:0]  id_zcmp_reg_count,

    // Zcmt signals from ID
    input  logic        id_zcmt,
    input  logic [7:0]  id_zcmt_index,
    input  logic        id_zcmt_jalt,

    // Combinational register data for Zcmp push
    input  logic [31:0] zc_rs_data,

    // Zcmt table data from IF BRAM port
    input  logic [31:0] zcmt_table_data,

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
    output logic        ex_fence_i,
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
    output logic [31:0] ex_alu_fwd,

    // Zcmp alternate register read address
    output logic [4:0]  ex_zc_rs_addr,
    output logic        ex_zc_rs_addr_en,

    // Zcmt table read address + active (to IF BRAM port)
    output logic [31:0] ex_zcmt_addr,
    output logic        ex_zcmt_addr_en,

    // Stall EX_OUT during Zcmt wait
    output logic        ex_zc_out_stall
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
    logic        ex_fence_i_q;
    logic        ex_mul_div_q;
    logic        ex_amo_q;
    logic [4:0]  ex_amo_op_q;
    logic [11:0] ex_csr_addr_q;
    logic [2:0]  ex_csr_op_q;
    logic [31:0] ex_csr_rdata_q;
    logic [1:0]  ex_branch_op_q;
    logic [2:0]  ex_branch_f3_q;

    logic        ex_zcmp_q;
    logic [1:0]  ex_zcmp_op_q;
    logic [3:0]  ex_zcmp_rlist_q;
    logic [9:0]  ex_zcmp_stack_adj_q;
    logic [3:0]  ex_zcmp_reg_count_q;
    logic        ex_zcmt_q;
    logic [7:0]  ex_zcmt_index_q;
    logic        ex_zcmt_jalt_q;

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
            ex_fence_i_q    <= 1'b0;
            ex_mul_div_q    <= 1'b0;
            ex_amo_q        <= 1'b0;
            ex_amo_op_q     <= 5'h0;
            ex_csr_addr_q   <= 12'h0;
            ex_csr_op_q     <= 3'h0;
            ex_csr_rdata_q  <= 32'h0;
            ex_branch_op_q  <= 2'h0;
            ex_branch_f3_q  <= 3'h0;
            ex_zcmp_q       <= 1'b0;
            ex_zcmp_op_q    <= 2'b0;
            ex_zcmp_rlist_q <= 4'b0;
            ex_zcmp_stack_adj_q <= 10'b0;
            ex_zcmp_reg_count_q <= 4'b0;
            ex_zcmt_q       <= 1'b0;
            ex_zcmt_index_q <= 8'b0;
            ex_zcmt_jalt_q  <= 1'b0;
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
            ex_fence_i_q    <= 1'b0;
            ex_mul_div_q    <= 1'b0;
            ex_amo_q        <= 1'b0;
            ex_amo_op_q     <= 5'h0;
            ex_csr_addr_q   <= 12'h0;
            ex_csr_op_q     <= 3'h0;
            ex_csr_rdata_q  <= 32'h0;
            ex_branch_op_q  <= 2'h0;
            ex_branch_f3_q  <= 3'h0;
            ex_zcmp_q       <= 1'b0;
            ex_zcmp_op_q    <= 2'b0;
            ex_zcmp_rlist_q <= 4'b0;
            ex_zcmp_stack_adj_q <= 10'b0;
            ex_zcmp_reg_count_q <= 4'b0;
            ex_zcmt_q       <= 1'b0;
            ex_zcmt_index_q <= 8'b0;
            ex_zcmt_jalt_q  <= 1'b0;
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
            ex_fence_i_q    <= id_fence_i;
            ex_mul_div_q    <= id_mul_div;
            ex_amo_q        <= id_amo;
            ex_amo_op_q     <= id_amo_op;
            ex_csr_addr_q   <= id_csr_addr;
            ex_csr_op_q     <= id_csr_op;
            ex_csr_rdata_q  <= id_csr_rdata;
            ex_branch_op_q  <= id_branch_op;
            ex_branch_f3_q  <= id_branch_f3;
            ex_zcmp_q       <= id_zcmp;
            ex_zcmp_op_q    <= id_zcmp_op;
            ex_zcmp_rlist_q <= id_zcmp_rlist;
            ex_zcmp_stack_adj_q <= id_zcmp_stack_adj;
            ex_zcmp_reg_count_q <= id_zcmp_reg_count;
            ex_zcmt_q       <= id_zcmt;
            ex_zcmt_index_q <= id_zcmt_index;
            ex_zcmt_jalt_q  <= id_zcmt_jalt;
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
    //  Zcmp state machine (multi-cycle push/pop)
    // ================================================================
    typedef enum logic [2:0] {
        ZC_IDLE = 3'd0,
        ZC_STORE = 3'd1,    // push: one register store per cycle
        ZC_LOAD = 3'd2,     // pop: issue register load
        ZC_LOAD_WAIT = 3'd3, // pop: wait for load to clear MEM
        ZC_UPD_SP = 3'd4,   // update SP after all regs processed
        ZC_UPD_WAIT = 3'd5, // wait for MEM to capture SP update
        ZC_RET = 3'd6       // popret/popretz: return handling
    } zc_state_t;
    zc_state_t zc_state, zc_state_next;
    logic [3:0] zc_cnt, zc_cnt_next;
    logic       zcmp_stall, zcmp_done, zcmp_done_q;

    // Register number for current counter index
    // Zcmp saved register list (highest number first):
    //  rlist=4 (5 regs): s3,s2,s1,s0,ra
    //  rlist=5 (6 regs): s4,s3,s2,s1,s0,ra
    //  rlist=6 (7 regs): s5,s4,s3,s2,s1,s0,ra
    //  rlist=7 (13 regs): s11..s2,s1,s0,ra
    // Reg mapping: s0=x8, s1=x9, s2=x18, s3=x19, ..., s11=x27
    // Formula:  for cnt = reg_count-3 → s1 (x9)
    //           for cnt = reg_count-2 → s0 (x8)
    //           for cnt = reg_count-1 → ra (x1)
    //           else → 5'd14 + reg_count - cnt  (s2...s11 range x18..x27)
    logic [4:0] zc_curr_reg;
    always_comb begin
        if (zc_cnt == ex_zcmp_reg_count_q - 4'd3)
            zc_curr_reg = 5'd9;  // s1
        else if (zc_cnt == ex_zcmp_reg_count_q - 4'd2)
            zc_curr_reg = 5'd8;  // s0
        else if (zc_cnt == ex_zcmp_reg_count_q - 4'd1)
            zc_curr_reg = 5'd1;  // ra
        else
            zc_curr_reg = 5'd14 + ex_zcmp_reg_count_q - zc_cnt;
    end

    // Store/load address for current counter index
    logic [31:0] zc_base_addr;
    assign zc_base_addr = (ex_zcmp_op_q == 2'b00)   // push
                        ? ex_rs1_data_q               // SP
                        : ex_rs1_data_q + {24'b0, ex_zcmp_stack_adj_q}; // SP + stack_adj

    logic [31:0] zc_mem_addr;
    assign zc_mem_addr = zc_base_addr - 32'd4 - {28'b0, zc_cnt, 2'b00};

    // Zcmp state machine (combinational next-state)
    always_comb begin
        zc_state_next = zc_state;
        zc_cnt_next   = zc_cnt;
        zcmp_stall    = 1'b0;
        zcmp_done     = 1'b0;

        unique case (zc_state)
            ZC_IDLE: begin
                if (ex_zcmp_q && ex_valid_q && !zcmp_done_q) begin
                    zcmp_stall = 1'b1;
                    if (ex_zcmp_op_q == 2'b00) begin       // push
                        zc_state_next = ZC_STORE;
                    end else begin                          // pop/popret/popretz
                        zc_state_next = ZC_LOAD;
                    end
                    zc_cnt_next = 4'd0;
                end
            end

            ZC_STORE: begin
                // Push: store one register per cycle
                // ex_out_stall_i is always 0 for Zcmp, so EX_OUT captures every cycle
                zcmp_stall = 1'b1;
                if (zc_cnt == ex_zcmp_reg_count_q - 4'd1) begin
                    zc_state_next = ZC_UPD_SP;
                end else begin
                    zc_cnt_next = zc_cnt + 4'd1;
                end
            end

            ZC_LOAD: begin
                // Pop: issue load for current register
                zcmp_stall = 1'b1;
                zc_state_next = ZC_LOAD_WAIT;
            end

            ZC_LOAD_WAIT: begin
                // Wait for MEM to consume the load before issuing next
                zcmp_stall = 1'b1;
                if (!ex_out_stall_i) begin
                    if (zc_cnt == ex_zcmp_reg_count_q - 4'd1) begin
                        zc_state_next = ZC_UPD_SP;
                    end else begin
                        zc_cnt_next = zc_cnt + 4'd1;
                        zc_state_next = ZC_LOAD;
                    end
                end
            end

            ZC_UPD_SP: begin
                // Write SP update to EX_OUT, then wait one cycle for MEM capture
                zcmp_stall = 1'b1;
                zc_state_next = ZC_UPD_WAIT;
            end

            ZC_UPD_WAIT: begin
                // Hold stall while MEM captures SP_update from EX_OUT
                zcmp_stall = 1'b1;
                if (!ex_out_stall_i) begin
                    if (ex_zcmp_op_q inside {2'b10, 2'b11}) // popret/popretz
                        zc_state_next = ZC_RET;
                    else begin
                        zc_state_next = ZC_IDLE;
                        zcmp_done = 1'b1;
                    end
                end
            end

            ZC_RET: begin
                // Return (and optionally zero a0 for popretz)
                zc_state_next = ZC_IDLE;
                zcmp_done = 1'b1;
            end

            default: begin
                zc_state_next = ZC_IDLE;
                zcmp_done = 1'b1;
            end
        endcase
    end

    // zcmp_done_q: stays high after completion until pipeline actually advances
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            zcmp_done_q <= 1'b0;
        else if (zcmp_done)
            zcmp_done_q <= 1'b1;
        else if (!ex_stall)
            zcmp_done_q <= 1'b0;
    end

    // Zcmp registered state (advances independently of pipeline stall)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zc_state <= ZC_IDLE;
            zc_cnt   <= 4'd0;
        end else if (ex_flush || (ex_branch_taken && ex_valid)) begin
            zc_state <= ZC_IDLE;
            zc_cnt   <= 4'd0;
        end else begin
            zc_state <= zc_state_next;
            zc_cnt   <= zc_cnt_next;
        end
    end

    // Zcmp control signals (combinational, override ex_* for state machine)
    logic zc_alu_result, zc_rd_we, zc_mem_write, zc_mem_read, zc_valid;
    logic [4:0] zc_rd_addr;
    always_comb begin
        zc_rd_addr   = 5'h0;
        zc_rd_we     = 1'b0;
        zc_mem_write = 1'b0;
        zc_mem_read  = 1'b0;
        zc_valid     = 1'b0;
        ex_zc_rs_addr    = 5'h0;
        ex_zc_rs_addr_en = 1'b0;

        unique case (zc_state)
            ZC_IDLE: ;
            ZC_STORE: begin
                // Push: store current register
                ex_zc_rs_addr    = zc_curr_reg;
                ex_zc_rs_addr_en = 1'b1;
                zc_mem_write     = 1'b1;
                zc_valid         = 1'b1;
            end
            ZC_LOAD: begin
                // Pop: load current register
                zc_rd_addr = zc_curr_reg;
                zc_rd_we   = 1'b1;
                zc_mem_read = 1'b1;
                zc_valid    = 1'b1;
            end
            ZC_LOAD_WAIT: ;
            ZC_UPD_SP: begin
                // Update SP: SP = SP +/- stack_adj
                zc_rd_addr = 5'd2; // SP
                zc_rd_we   = 1'b1;
                zc_valid   = 1'b1;
            end
            ZC_UPD_WAIT: begin
                // Hold: no new control signals needed
            end
            ZC_RET: begin
                // Read x1 (ra) for return branch
                ex_zc_rs_addr    = 5'd1;  // ra
                ex_zc_rs_addr_en = 1'b1;
                if (ex_zcmp_op_q == 2'b10) begin // popretz: zero a0
                    zc_rd_addr = 5'd10; // a0
                    zc_rd_we   = 1'b1;
                end
                zc_valid = 1'b1;
            end
        endcase
    end

    // ================================================================
    //  Zcmt state machine (table jump via IF BRAM port)
    // ================================================================
    typedef enum logic [2:0] {
        ZCMT_IDLE  = 3'd0,
        ZCMT_SEND  = 3'd1,   // send table address to BRAM
        ZCMT_WAIT0 = 3'd2,   // BRAM latency cycle 1
        ZCMT_WAIT1 = 3'd3,   // BRAM latency cycle 2 (data ready at posedge)
        ZCMT_BRANCH = 3'd4   // execute branch
    } zcmt_state_t;
    zcmt_state_t zcmt_state, zcmt_state_next;
    logic        zcmt_stall, zcmt_done;
    logic [31:0] zcmt_jvt_base;

    assign zcmt_jvt_base = ex_csr_rdata_q;

    // Zcmt table read address
    logic [31:0] zcmt_read_addr;
    assign zcmt_read_addr = (zcmt_jvt_base & 32'hFFFFFFC0) + {24'b0, ex_zcmt_index_q, 2'b00};

    // Zcmt state machine
    always_comb begin
        zcmt_state_next = zcmt_state;
        zcmt_stall      = 1'b0;
        zcmt_done       = 1'b0;

        unique case (zcmt_state)
            ZCMT_IDLE: begin
                if (ex_zcmt_q && ex_valid_q) begin
                    zcmt_stall = 1'b1;
                    zcmt_state_next = ZCMT_SEND;
                end
            end
            ZCMT_SEND: begin
                zcmt_stall = 1'b1;
                zcmt_state_next = ZCMT_WAIT0;
            end
            ZCMT_WAIT0: begin
                zcmt_stall = 1'b1;
                zcmt_state_next = ZCMT_WAIT1;
            end
            ZCMT_WAIT1: begin
                zcmt_stall = 1'b1;
                // Data should be ready at posedge
                zcmt_state_next = ZCMT_BRANCH;
            end
            ZCMT_BRANCH: begin
                zcmt_state_next = ZCMT_IDLE;
                zcmt_done = 1'b1;
            end
            default: begin
                zcmt_state_next = ZCMT_IDLE;
                zcmt_done = 1'b1;
            end
        endcase
    end

    // Zcmt registered state (advances independently of pipeline stall)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zcmt_state <= ZCMT_IDLE;
        end else if (ex_flush || (ex_branch_taken && ex_valid)) begin
            zcmt_state <= ZCMT_IDLE;
        end else begin
            zcmt_state <= zcmt_state_next;
        end
    end

    // Zcmt control signals (combinational)
    wire        zcmt_sending  = (zcmt_state == ZCMT_SEND);
    wire        zcmt_branching = (zcmt_state == ZCMT_BRANCH);
    wire        zcmt_waiting  = (zcmt_state inside {ZCMT_WAIT0, ZCMT_WAIT1});

    // ex_zc_out_stall: hold EX_OUT during Zcmt wait
    assign ex_zc_out_stall = zcmt_waiting;

    // Zcmt address output to IF BRAM port
    assign ex_zcmt_addr     = zcmt_read_addr;
    assign ex_zcmt_addr_en  = zcmt_sending || zcmt_waiting;

    // ================================================================
    //  Stall / done override for Zcmp + Zcmt
    // ================================================================
    wire zcmp_or_zcmt_active = (zc_state != ZC_IDLE) || (zcmt_state != ZCMT_IDLE) || ex_zcmp_q || ex_zcmt_q;

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
            // Normal capture with Zcmp/Zcmt overrides
            ex_out_pc_q          <= ex_pc_q;
            ex_out_rs1_q         <= ex_rs1_data_q;
            ex_out_imm_q         <= ex_imm_q;
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

            // Zcmp overrides
            if (zc_state == ZC_STORE) begin
                ex_out_alu_result_q  <= zc_mem_addr;
                ex_out_rs2_q         <= zc_rs_data;
                ex_out_rd_addr_q     <= 5'h0;
                ex_out_rd_we_q       <= 1'b0;
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b1;
                ex_out_mem_type_q    <= 3'b010;  // word
                ex_out_valid_q       <= zc_valid;
            end else if (zc_state == ZC_LOAD) begin
                ex_out_alu_result_q  <= zc_mem_addr;
                ex_out_rd_addr_q     <= zc_rd_addr;
                ex_out_rd_we_q       <= 1'b1;
                ex_out_mem_read_q    <= 1'b1;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b010;  // word
                ex_out_valid_q       <= zc_valid;
                ex_out_rs2_q         <= ex_rs2_data_q;
            end else if (zc_state == ZC_UPD_SP) begin
                if (ex_zcmp_op_q == 2'b00)  // push
                    ex_out_alu_result_q <= ex_rs1_data_q - {24'b0, ex_zcmp_stack_adj_q};
                else                        // pop
                    ex_out_alu_result_q <= ex_rs1_data_q + {24'b0, ex_zcmp_stack_adj_q};
                ex_out_rd_addr_q     <= 5'd2;  // SP
                ex_out_rd_we_q       <= 1'b1;
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b0;
                ex_out_valid_q       <= zc_valid;
                ex_out_rs2_q         <= ex_rs2_data_q;
            end else if (zc_state == ZC_UPD_WAIT) begin
                // Hold EX_OUT values while MEM captures SP update
                ex_out_valid_q <= 1'b0;
            end else if (zc_state == ZC_RET) begin
                if (ex_zcmp_op_q == 2'b10) begin // popretz: zero a0
                    ex_out_alu_result_q <= 32'h0;
                    ex_out_rd_addr_q     <= 5'd10;  // a0
                    ex_out_rd_we_q       <= 1'b1;
                end else begin
                    ex_out_alu_result_q <= 32'h0;
                    ex_out_rd_addr_q     <= 5'h0;
                    ex_out_rd_we_q       <= 1'b0;
                end
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b0;
                ex_out_valid_q       <= 1'b1;
                ex_out_rs2_q         <= ex_rs2_data_q;
                ex_out_rs1_q         <= zc_rs_data;  // x1 value for return
                ex_out_branch_op_q   <= 2'b11;       // JALR-like
                ex_out_imm_q         <= 32'h0;
            end else if (zc_state == ZC_IDLE && zcmp_done_q) begin
                // Suppress spurious EX_OUT capture on the completion cycle
                ex_out_alu_result_q <= 32'h0;
                ex_out_rd_addr_q     <= 5'h0;
                ex_out_rd_we_q       <= 1'b0;
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b0;
                ex_out_valid_q       <= 1'b0;
                ex_out_rs2_q         <= ex_rs2_data_q;
            end else if (zcmt_branching) begin
                // Zcmt table jump
                if (ex_zcmt_jalt_q) begin
                    ex_out_alu_result_q <= ex_pc_q + 32'd2;    // link: PC+2
                    ex_out_rd_addr_q     <= 5'd1;               // ra
                    ex_out_rd_we_q       <= 1'b1;
                end else begin
                    ex_out_alu_result_q <= 32'h0;
                    ex_out_rd_addr_q     <= 5'h0;
                    ex_out_rd_we_q       <= 1'b0;
                end
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b0;
                ex_out_valid_q       <= 1'b1;
                ex_out_rs2_q         <= ex_rs2_data_q;
                ex_out_rs1_q         <= zcmt_table_data; // table entry → target
                ex_out_branch_op_q   <= 2'b11;            // JALR-like
                ex_out_imm_q         <= 32'h0;
            end else if (zcmt_sending) begin
                // Zcmt: sends address via ex_zcmt_addr (IF BRAM port), not MEM
                ex_out_alu_result_q  <= ex_pc_q;
                ex_out_rd_addr_q     <= 5'h0;
                ex_out_rd_we_q       <= 1'b0;
                ex_out_mem_read_q    <= 1'b0;
                ex_out_mem_write_q   <= 1'b0;
                ex_out_mem_type_q    <= 3'b0;
                ex_out_valid_q       <= 1'b1;
                ex_out_rs2_q         <= ex_rs2_data_q;
            end else begin
                ex_out_alu_result_q  <= (ex_csr_op_q != 3'h0) ? ex_csr_rdata_q : alu_or_div_result;
                ex_out_rs2_q         <= ex_rs2_data_q;
                ex_out_rd_addr_q     <= ex_rd_addr_q;
                ex_out_rd_we_q       <= ex_rd_we_q;
                ex_out_mem_read_q    <= ex_mem_read_q;
                ex_out_mem_write_q   <= ex_mem_write_q;
                ex_out_mem_type_q    <= ex_mem_type_q;
                ex_out_valid_q <= ex_valid_q && !((is_div_rem || is_mul) && !ex_done)
                                && !(zcmp_stall && !(|{zc_state == ZC_STORE, zc_state == ZC_LOAD, zc_state == ZC_UPD_SP, zc_state == ZC_RET}));
            end
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
    assign ex_fence_i    = ex_fence_i_q && ex_valid_q;
    assign ex_csr_addr  = ex_out_csr_addr_q;
    assign ex_csr_op    = ex_out_csr_op_q;
    assign ex_csr_rdata = ex_out_csr_rdata_q;

    // ================================================================
    //  Stall / done
    // ================================================================
    assign ex_stall = ((is_div_rem || is_mul) && !ex_done)
                    || zcmp_stall
                    || zcmt_stall;
    assign ex_done  = is_mul    ? (mul_stall_extra && !mul_busy)
                    : is_div_rem ? (stall_extra && !div_busy)
                    : zcmp_done ? 1'b1
                    : zcmt_done ? 1'b1
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
    assign ex_alu_fwd      = (ex_csr_op_q != 3'h0) ? ex_csr_rdata_q : alu_or_div_result;

endmodule
