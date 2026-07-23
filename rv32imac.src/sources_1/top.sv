module top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        meip_i,
    input  logic        msip_i,

    output logic [31:0] pc_debug,
    output logic [31:0] instr_debug,
    output logic        ebreak_debug
);

    logic [31:0] if_pc;
    logic [31:0] if_bram_addr;
    logic [31:0] if_instr;
    logic [31:0] if_instr_dout;
    logic        if_access_fault;

    logic [31:0] id_instr_r;
    logic [31:0] id_pc_r;
    logic        id_if_access_fault_r;

    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [31:0] id_imm;
    logic [5:0]  id_alu_op;
    logic [1:0]  id_alu_a_sel, id_alu_b_sel;
    logic        id_rd_we, id_mem_read, id_mem_write;
    logic [2:0]  id_mem_type;
    logic        id_valid, id_ebreak, id_ecall, id_mret, id_illegal, id_if_access_fault, id_fence_i;
    logic        id_ex_stall, id_mul_div;
    logic        id_amo;
    logic [4:0]  id_amo_op;
    wire         ex_stall_out;

    logic [31:0] ex_pc, ex_alu_result, ex_rs2_data;
    logic [4:0]  ex_rd_addr;
    logic        ex_rd_we, ex_mem_read, ex_mem_write, ex_valid, ex_done, ex_ebreak;
    logic        ex_ecall, ex_mret, ex_illegal, ex_if_access_fault, ex_fence_i;
    logic [2:0]  ex_mem_type;
    logic        ex_amo;
    logic [4:0]  ex_amo_op;
    logic        amo_stall;

    logic [31:0] mem_pc, mem_alu_result, mem_mem_data;
    logic [4:0]  mem_rd_addr;
    logic        mem_rd_we, mem_mem_read, mem_valid, mem_ebreak, mem_load_fault, mem_store_fault;

    logic [4:0]  wb_rd_addr;
    logic [31:0] wb_rd_data;
    logic        wb_rd_we, wb_valid, wb_ebreak;

    logic [31:0] reg_rs1_data, reg_rs2_data;
    logic [31:0] alu_rs1_data, alu_rs2_data;

    logic [11:0] id_csr_addr;
    logic [2:0]  id_csr_op;
    logic [31:0] id_csr_rdata, csr_file_rdata, id_csr_rdata_fwd;
    logic [11:0] ex_csr_addr;
    logic [2:0]  ex_csr_op;
    logic [31:0] ex_csr_rdata, ex_csr_wdata;
    logic [11:0] mem_csr_addr;
    logic        mem_csr_we;
    logic [31:0] mem_csr_wdata;

    logic [1:0]  id_branch_op;
    logic [2:0]  id_branch_f3;
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    logic        ex_flush;
    logic        ex_mem_flush;

    // Zcmp signals
    logic        id_zcmp;
    logic [1:0]  id_zcmp_op;
    logic [3:0]  id_zcmp_rlist;
    logic [9:0]  id_zcmp_stack_adj;
    logic [3:0]  id_zcmp_reg_count;
    logic        ex_zcmp;
    logic [1:0]  ex_zcmp_op;
    logic [3:0]  ex_zcmp_rlist;
    logic [9:0]  ex_zcmp_stack_adj;
    logic [3:0]  ex_zcmp_reg_count;

    // Zcmt signals
    logic        id_zcmt;
    logic [7:0]  id_zcmt_index;
    logic        id_zcmt_jalt;
    logic        ex_zcmt;
    logic [7:0]  ex_zcmt_index;
    logic        ex_zcmt_jalt;

    // EX ←→ top.sv
    logic [4:0]  ex_zc_rs_addr;
    logic        ex_zc_rs_addr_en;
    logic [31:0] ex_zcmt_addr;
    logic        ex_zcmt_addr_en;
    logic        ex_zc_out_stall;
    logic [31:0] zc_rs_data;

    logic [31:0] csr_mtvec, csr_mepc, csr_mie, csr_mip;
    logic        csr_illegal;
    logic [31:0] csr_jvt;
    logic [1:0]  priv_lvl;
    logic [31:0] pmpcfg_w   [0:3];
    logic [31:0] pmpaddr_w  [0:15];
    logic        pmp_fault_if, pmp_fault_ld, pmp_fault_st;

    logic [31:0] reg_zc_raw_data;

    // EX forwarding signals
    logic [4:0]  ex_fwd_rd_addr;
    logic        ex_fwd_rd_we, ex_fwd_mem_read, ex_fwd_valid;
    logic [31:0] ex_alu_fwd;

    // Load-use hazard detection
    // Load-use hazard: when a LW is in EX_IN and a dependent instruction is
    // in ID, we gate ID outputs to bubble so EX_IN captures a NOP (not the
    // dependent instruction) while the load advances EX_IN → EX_OUT → MEM.
    // ex_fwd_* reflect the EX_IN register.
    wire load_use_hazard =
        ((ex_fwd_mem_read && ex_fwd_valid &&
          (ex_fwd_rd_addr != 5'h0) &&
          (ex_fwd_rd_addr == id_rs1_addr || ex_fwd_rd_addr == id_rs2_addr)) ||
         (ex_mem_read && ex_valid &&
          (ex_rd_addr != 5'h0) &&
          (ex_rd_addr == id_rs1_addr || ex_rd_addr == id_rs2_addr)));

    wire         stall     = id_ex_stall | ex_stall_out | load_use_hazard;
    wire         ex_stall  = id_ex_stall | ex_stall_out;

    wire         hazard_bubble = load_use_hazard;
    wire [31:0] ex_id_pc          = hazard_bubble ? 32'h0            : id_pc_r;
    wire [31:0] ex_id_rs1_data    = hazard_bubble ? 32'h0            : alu_rs1_data;
    wire [31:0] ex_id_rs2_data    = hazard_bubble ? 32'h0            : alu_rs2_data;
    wire [31:0] ex_id_imm         = hazard_bubble ? 32'h0            : id_imm;
    wire [5:0]  ex_id_alu_op      = hazard_bubble ? 6'h0             : id_alu_op;
    wire [1:0]  ex_id_alu_a_sel   = hazard_bubble ? 2'h0             : id_alu_a_sel;
    wire [1:0]  ex_id_alu_b_sel   = hazard_bubble ? 2'h0             : id_alu_b_sel;
    wire [4:0]  ex_id_rd_addr     = hazard_bubble ? 5'h0             : id_rd_addr;
    wire        ex_id_rd_we       = hazard_bubble ? 1'b0             : id_rd_we;
    wire        ex_id_mem_read    = hazard_bubble ? 1'b0             : id_mem_read;
    wire        ex_id_mem_write   = hazard_bubble ? 1'b0             : id_mem_write;
    wire [2:0]  ex_id_mem_type    = hazard_bubble ? 3'h0             : id_mem_type;
    wire        ex_id_valid       = hazard_bubble ? 1'b0             : id_valid;
    wire        ex_id_ebreak      = hazard_bubble ? 1'b0             : id_ebreak;
    wire        ex_id_ecall       = hazard_bubble ? 1'b0             : id_ecall;
    wire        ex_id_mret        = hazard_bubble ? 1'b0             : id_mret;
    wire        ex_id_illegal     = hazard_bubble ? 1'b0             : id_illegal;
    wire        ex_id_if_access_fault = hazard_bubble ? 1'b0         : id_if_access_fault;
    wire        ex_id_mul_div     = hazard_bubble ? 1'b0             : id_mul_div;
    wire [11:0] ex_id_csr_addr    = hazard_bubble ? 12'h0            : id_csr_addr;
    wire [2:0]  ex_id_csr_op      = hazard_bubble ? 3'h0             : id_csr_op;
    wire [31:0] ex_id_csr_rdata   = hazard_bubble ? 32'h0            : id_csr_rdata_fwd;
    wire        ex_id_fence_i      = hazard_bubble ? 1'b0             : id_fence_i;
    wire [1:0]  ex_id_branch_op   = hazard_bubble ? 2'h0             : id_branch_op;
    wire [2:0]  ex_id_branch_f3   = hazard_bubble ? 3'h0             : id_branch_f3;
    wire        ex_id_amo         = hazard_bubble ? 1'b0             : id_amo;
    wire [4:0]  ex_id_amo_op      = hazard_bubble ? 5'h0             : id_amo_op;

    wire        ex_id_zcmp        = hazard_bubble ? 1'b0             : id_zcmp;
    wire [1:0]  ex_id_zcmp_op     = hazard_bubble ? 2'b0             : id_zcmp_op;
    wire [3:0]  ex_id_zcmp_rlist  = hazard_bubble ? 4'b0             : id_zcmp_rlist;
    wire [9:0]  ex_id_zcmp_stack_adj = hazard_bubble ? 10'b0          : id_zcmp_stack_adj;
    wire [3:0]  ex_id_zcmp_reg_count = hazard_bubble ? 4'b0          : id_zcmp_reg_count;
    wire        ex_id_zcmt        = hazard_bubble ? 1'b0             : id_zcmt;
    wire [7:0]  ex_id_zcmt_index  = hazard_bubble ? 8'b0             : id_zcmt_index;
    wire        ex_id_zcmt_jalt   = hazard_bubble ? 1'b0             : id_zcmt_jalt;

    reg_file u_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs2_addr (id_rs2_addr),
        .rs3_addr (ex_zc_rs_addr),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_rd_data),
        .rd_we    (wb_rd_we),
        .rs1_data (reg_rs1_data),
        .rs2_data (reg_rs2_data),
        .rs3_data (reg_zc_raw_data)
    );

    // ================================================================
    //  Trap and Interrupt logic
    // ================================================================
    logic        trap_trigger;
    logic [31:0] trap_cause_val, trap_tval_val;
    logic [31:0] trap_pc_val;
    logic        irq_pending;

    // Store access fault detection (MEM stage)
    wire ex_store_fault = mem_store_fault && mem_valid;

    // Exception sources (MEM stage = older instruction)
    wire mem_exception = (mem_load_fault || mem_store_fault) && mem_valid;

    // Exception sources (EX stage = younger instruction)
    wire ex_exception = (ex_ecall || ex_ebreak || ex_illegal || ex_if_access_fault || csr_illegal) && ex_valid;

    // MRET (not an exception)
    wire mret_taken = ex_mret && ex_valid;

    // Exception priority: MEM (older) > EX (younger)
    wire any_exception = mem_exception || ex_exception;
    wire irq_taken = irq_pending && !any_exception && !mret_taken && ex_valid;
    wire any_trap = any_exception || mret_taken;
    wire trap_or_irq = any_trap || irq_taken;
    wire any_trap_taken = trap_or_irq;

    // Trap target
    wire [31:0] ex_trap_target = mret_taken ? csr_mepc : csr_mtvec;

    always_comb begin
        trap_trigger   = 1'b0;
        trap_cause_val = 32'h0;
        trap_tval_val  = 32'h0;
        trap_pc_val    = ex_pc;

        if (any_exception) begin
            trap_trigger = 1'b1;
            if (mem_exception) begin
                trap_pc_val = mem_pc;
                if (mem_store_fault && mem_valid)
                    trap_cause_val = 32'd7;
                else
                    trap_cause_val = 32'd5;
                trap_tval_val  = mem_alu_result;
            end else if (ex_if_access_fault) begin
                trap_cause_val = 32'd1;
                trap_tval_val  = ex_pc;
            end else if (ex_illegal) begin
                trap_cause_val = 32'd2;
            end else if (csr_illegal) begin
                trap_cause_val = 32'd2;
            end else if (ex_ebreak) begin
                trap_cause_val = 32'd3;
            end else if (ex_ecall) begin
                trap_cause_val = (priv_lvl == 2'b00) ? 32'd8 : 32'd11;
            end
        end else if (irq_taken) begin
            trap_trigger   = 1'b1;
            trap_pc_val    = ex_pc;
            trap_tval_val  = 32'h0;
            if (csr_mie[11] && csr_mip[11]) // MEI
                trap_cause_val = 32'h8000000B;
            else if (csr_mie[3] && csr_mip[3]) // MSI
                trap_cause_val = 32'h80000003;
            else // MTI
                trap_cause_val = 32'h80000007;
        end
        // MRET: no CSR trap update needed (returns from existing trap)
    end

    assign ex_mem_flush = any_trap_taken;
    wire fence_i_flush = ex_fence_i && ex_valid;

    // ================================================================
    //  CSR
    // ================================================================
    logic        csr_we;
    assign csr_we = (ex_csr_op != 3'h0) && !csr_illegal && !any_trap_taken;

    csr_reg u_csr (
        .clk     (clk),
        .rst_n   (rst_n),
        .raddr   (id_csr_addr),
        .rdata   (csr_file_rdata),
        .we      (csr_we),
        .waddr   (ex_csr_addr),
        .wdata   (ex_csr_wdata),
        .instr_ret(wb_valid),
        .trap_trigger(trap_trigger),
        .trap_pc     (trap_pc_val),
        .trap_cause  (trap_cause_val),
        .trap_tval   (trap_tval_val),
        .mret_taken  (mret_taken),
        .meip_i      (meip_i),
        .msip_i      (msip_i),
        .mtvec_val(csr_mtvec),
        .mepc_val (csr_mepc),
        .irq_pending(irq_pending),
        .mie_val   (csr_mie),
        .mip_val   (csr_mip),
        .jvt_val   (csr_jvt),
        .csr_illegal(csr_illegal),
        .priv_lvl   (priv_lvl),
        .pmpcfg_o   (pmpcfg_w),
        .pmpaddr_o  (pmpaddr_w)
    );

    // PMP checker for instruction fetch
    pmp_check #(.NUM_PMP_ENTRIES(16), .PMP_GRANULARITY(0)) u_pmp_if (
        .priv_lvl (priv_lvl),
        .addr     (if_pc),
        .is_write (1'b0),
        .is_exec  (1'b1),
        .pmpcfg   (pmpcfg_w),
        .pmpaddr  (pmpaddr_w),
        .pmp_fault(pmp_fault_if)
    );

    // PMP checker for data loads
    pmp_check #(.NUM_PMP_ENTRIES(16), .PMP_GRANULARITY(0)) u_pmp_ld (
        .priv_lvl (priv_lvl),
        .addr     (mem_alu_result),
        .is_write (1'b0),
        .is_exec  (1'b0),
        .pmpcfg   (pmpcfg_w),
        .pmpaddr  (pmpaddr_w),
        .pmp_fault(pmp_fault_ld)
    );

    // PMP checker for data stores
    pmp_check #(.NUM_PMP_ENTRIES(16), .PMP_GRANULARITY(0)) u_pmp_st (
        .priv_lvl (priv_lvl),
        .addr     (mem_alu_result),
        .is_write (1'b1),
        .is_exec  (1'b0),
        .pmpcfg   (pmpcfg_w),
        .pmpaddr  (pmpaddr_w),
        .pmp_fault(pmp_fault_st)
    );

    // ================================================================
    //  Pipeline control
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_instr_r <= 32'h00000013; // nop, not 0 (0 would decode as illegal)
            id_pc_r    <= 32'h0;
            id_if_access_fault_r <= 1'b0;
            ex_flush   <= 1'b0;
        end else if (stall) begin
            ex_flush <= 1'b0;
        end else begin
            ex_flush <= any_trap_taken && ex_valid;
            if (any_trap_taken) begin
                id_instr_r <= 32'h00000013;
                id_pc_r    <= ex_trap_target;
                id_if_access_fault_r <= 1'b0;
            end else if (ex_branch_taken && ex_valid) begin
                id_instr_r <= 32'h00000013;
                id_pc_r    <= ex_branch_target;
                id_if_access_fault_r <= 1'b0;
            end else begin
                id_instr_r <= if_instr;
                id_pc_r    <= if_pc;
                id_if_access_fault_r <= if_access_fault;
            end
        end
    end

    always_comb begin
        alu_rs1_data = reg_rs1_data;
        alu_rs2_data = reg_rs2_data;

        if (id_rs1_addr != 5'h0) begin
            if (ex_fwd_rd_we && ex_fwd_valid && ex_fwd_rd_addr == id_rs1_addr && !ex_fwd_mem_read) begin
                alu_rs1_data = ex_alu_fwd;
            end else if (ex_rd_we && ex_valid && ex_rd_addr == id_rs1_addr && !ex_mem_read) begin
                alu_rs1_data = ex_alu_result;
            end else if (mem_rd_we && mem_valid && mem_rd_addr == id_rs1_addr) begin
                if (mem_mem_read)
                    alu_rs1_data = mem_mem_data;
                else
                    alu_rs1_data = mem_alu_result;
            end else if (wb_rd_we && wb_valid && wb_rd_addr == id_rs1_addr) begin
                alu_rs1_data = wb_rd_data;
            end
        end

        if (id_rs2_addr != 5'h0) begin
            if (ex_fwd_rd_we && ex_fwd_valid && ex_fwd_rd_addr == id_rs2_addr && !ex_fwd_mem_read) begin
                alu_rs2_data = ex_alu_fwd;
            end else if (ex_rd_we && ex_valid && ex_rd_addr == id_rs2_addr && !ex_mem_read) begin
                alu_rs2_data = ex_alu_result;
            end else if (mem_rd_we && mem_valid && mem_rd_addr == id_rs2_addr) begin
                if (mem_mem_read)
                    alu_rs2_data = mem_mem_data;
                else
                    alu_rs2_data = mem_alu_result;
            end else if (wb_rd_we && wb_valid && wb_rd_addr == id_rs2_addr) begin
                alu_rs2_data = wb_rd_data;
            end
        end

        id_csr_rdata_fwd = csr_file_rdata;
        if (id_csr_op != 3'h0) begin
            if (ex_csr_op != 3'h0 && ex_csr_addr == id_csr_addr) begin
                id_csr_rdata_fwd = ex_csr_wdata;
            end else if (mem_csr_we && mem_csr_addr == id_csr_addr) begin
                id_csr_rdata_fwd = mem_csr_wdata;
            end
        end

        // Zcmp alternate register read with forwarding
        zc_rs_data = reg_zc_raw_data;
        if (ex_zc_rs_addr_en && ex_zc_rs_addr != 5'h0) begin
            if (ex_fwd_rd_we && ex_fwd_valid && ex_fwd_rd_addr == ex_zc_rs_addr && !ex_fwd_mem_read) begin
                zc_rs_data = ex_alu_fwd;
            end else if (ex_rd_we && ex_valid && ex_rd_addr == ex_zc_rs_addr && !ex_mem_read) begin
                zc_rs_data = ex_alu_result;
            end else if (mem_rd_we && mem_valid && mem_rd_addr == ex_zc_rs_addr) begin
                zc_rs_data = mem_mem_read ? mem_mem_data : mem_alu_result;
            end else if (wb_rd_we && wb_valid && wb_rd_addr == ex_zc_rs_addr) begin
                zc_rs_data = wb_rd_data;
            end
        end
    end

    if_stage u_if (
        .clk          (clk),
        .rst_n        (rst_n),
        .instr_dout   (if_instr_dout),
        .branch_taken (ex_branch_taken && ex_valid),
        .branch_target(ex_branch_target),
        .trap_taken   (any_trap_taken),
        .trap_target   (ex_trap_target),
        .fence_i_flush (fence_i_flush),
        .stall_i      (stall),
        .priv_lvl     (priv_lvl),
        .pmp_fault_i  (pmp_fault_if),
        .if_pc        (if_pc),
        .if_bram_addr (if_bram_addr),
        .if_instr     (if_instr),
        .if_access_fault(if_access_fault)
    );

    id_stage u_id (
        .if_instr    (id_instr_r),
        .if_valid    (1'b1),
        .if_access_fault(id_if_access_fault_r),
        .priv_lvl    (priv_lvl),
        .rs1_data    (alu_rs1_data),
        .rs2_data    (alu_rs2_data),
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .id_imm      (id_imm),
        .id_alu_op   (id_alu_op),
        .id_alu_a_sel(id_alu_a_sel),
        .id_alu_b_sel(id_alu_b_sel),
        .id_rd_addr  (id_rd_addr),
        .id_rd_we    (id_rd_we),
        .id_mem_read (id_mem_read),
        .id_mem_write(id_mem_write),
        .id_mem_type (id_mem_type),
        .id_valid    (id_valid),
        .id_ebreak   (id_ebreak),
        .id_ecall    (id_ecall),
        .id_mret     (id_mret),
        .id_mul_div  (id_mul_div),
        .id_amo      (id_amo),
        .id_amo_op   (id_amo_op),
        .id_illegal  (id_illegal),
        .id_if_access_fault(id_if_access_fault),
        .id_fence_i (id_fence_i),
        .ex_stall    (id_ex_stall),
        .ex_done     (ex_done),
        .csr_rdata   (id_csr_rdata_fwd),
        .id_csr_addr (id_csr_addr),
        .id_csr_op   (id_csr_op),
        .id_csr_rdata(id_csr_rdata),
        .id_branch_op (id_branch_op),
        .id_branch_f3 (id_branch_f3),

        .id_zcmp        (id_zcmp),
        .id_zcmp_op     (id_zcmp_op),
        .id_zcmp_rlist  (id_zcmp_rlist),
        .id_zcmp_stack_adj(id_zcmp_stack_adj),
        .id_zcmp_reg_count(id_zcmp_reg_count),
        .id_zcmt        (id_zcmt),
        .id_zcmt_index  (id_zcmt_index),
        .id_zcmt_jalt   (id_zcmt_jalt)
    );

    ex_stage u_ex (
        .clk          (clk),
        .rst_n        (rst_n),

        .id_pc         (ex_id_pc),
        .id_rs1_data   (ex_id_rs1_data),
        .id_rs2_data   (ex_id_rs2_data),
        .id_imm        (ex_id_imm),
        .id_alu_op     (ex_id_alu_op),
        .id_alu_a_sel  (ex_id_alu_a_sel),
        .id_alu_b_sel  (ex_id_alu_b_sel),
        .id_rd_addr    (ex_id_rd_addr),
        .id_rd_we      (ex_id_rd_we),
        .id_mem_read   (ex_id_mem_read),
        .id_mem_write  (ex_id_mem_write),
        .id_mem_type   (ex_id_mem_type),
        .id_valid      (ex_id_valid),
        .id_ebreak     (ex_id_ebreak),
        .id_ecall      (ex_id_ecall),
        .id_mret       (ex_id_mret),
        .id_illegal    (ex_id_illegal),
        .id_if_access_fault(ex_id_if_access_fault),
        .id_fence_i   (ex_id_fence_i),
        .id_mul_div    (ex_id_mul_div),
        .id_amo        (ex_id_amo),
        .id_amo_op     (ex_id_amo_op),
        .id_csr_addr   (ex_id_csr_addr),
        .id_csr_op     (ex_id_csr_op),
        .id_csr_rdata  (ex_id_csr_rdata),
        .id_branch_op  (ex_id_branch_op),
        .id_branch_f3  (ex_id_branch_f3),
        .ex_flush      (ex_flush),

        .ex_pc         (ex_pc),
        .ex_alu_result (ex_alu_result),
        .ex_rs2_data   (ex_rs2_data),
        .ex_rd_addr    (ex_rd_addr),
        .ex_rd_we      (ex_rd_we),
        .ex_mem_read   (ex_mem_read),
        .ex_mem_write  (ex_mem_write),
        .ex_mem_type   (ex_mem_type),
        .ex_amo        (ex_amo),
        .ex_amo_op     (ex_amo_op),
        .ex_valid      (ex_valid),
        .ex_ebreak     (ex_ebreak),
        .ex_ecall      (ex_ecall),
        .ex_mret       (ex_mret),
        .ex_illegal    (ex_illegal),
        .ex_if_access_fault(ex_if_access_fault),
        .ex_fence_i   (ex_fence_i),
        .ex_done       (ex_done),
        .ex_stall      (ex_stall_out),

        .ex_csr_addr   (ex_csr_addr),
        .ex_csr_op     (ex_csr_op),
        .ex_csr_rdata  (ex_csr_rdata),
        .ex_csr_wdata  (ex_csr_wdata),

        .ex_branch_taken (ex_branch_taken),
        .ex_branch_target(ex_branch_target),

        .ex_stall_i      (ex_stall),
        .ex_out_stall_i  (ex_zc_out_stall),

        .ex_fwd_rd_addr  (ex_fwd_rd_addr),
        .ex_fwd_rd_we    (ex_fwd_rd_we),
        .ex_fwd_mem_read (ex_fwd_mem_read),
        .ex_fwd_valid    (ex_fwd_valid),
        .ex_alu_fwd      (ex_alu_fwd),

        // Zcmp signals
        .id_zcmp         (ex_id_zcmp),
        .id_zcmp_op      (ex_id_zcmp_op),
        .id_zcmp_rlist   (ex_id_zcmp_rlist),
        .id_zcmp_stack_adj(ex_id_zcmp_stack_adj),
        .id_zcmp_reg_count(ex_id_zcmp_reg_count),

        // Zcmt signals
        .id_zcmt         (ex_id_zcmt),
        .id_zcmt_index   (ex_id_zcmt_index),
        .id_zcmt_jalt    (ex_id_zcmt_jalt),

        // Zcmp register read via 3rd port + forwarding
        .zc_rs_data      (zc_rs_data),

        // Zcmt table data from IF BRAM port
        .zcmt_table_data (if_instr_dout),

        // Zcmp alternate register address (to regfile rs3)
        .ex_zc_rs_addr   (ex_zc_rs_addr),
        .ex_zc_rs_addr_en(ex_zc_rs_addr_en),

        // Zcmt address for IF BRAM port override
        .ex_zcmt_addr    (ex_zcmt_addr),
        .ex_zcmt_addr_en (ex_zcmt_addr_en),

        .ex_zc_out_stall (ex_zc_out_stall)
    );

    // Zcmt overrides the IF BRAM port to read the JVT table
    wire [31:0] bram_addr_b = ex_zcmt_addr_en ? ex_zcmt_addr : if_bram_addr;

    mem_stage #(
        .RAM_INIT_FILE("test_prog.hex")
    ) u_mem (
        .clk        (clk),
        .rst_n      (rst_n),
        .ex_pc      (ex_pc),
        .ex_alu_result(ex_alu_result),
        .ex_rs2_data (ex_rs2_data),
        .ex_mem_type (ex_mem_type),
        .ex_mem_read (ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_amo      (ex_amo),
        .ex_amo_op   (ex_amo_op),
        .ex_rd_addr (ex_rd_addr),
        .ex_rd_we   (ex_rd_we),
        .ex_valid   (ex_valid),
        .ex_ebreak  (ex_ebreak),
        .mem_pc     (mem_pc),
        .mem_alu_result(mem_alu_result),
        .mem_mem_data(mem_mem_data),
        .mem_rd_addr (mem_rd_addr),
        .mem_rd_we  (mem_rd_we),
        .mem_mem_read(mem_mem_read),
        .mem_valid  (mem_valid),
        .mem_ebreak (mem_ebreak),
        .mem_load_fault(mem_load_fault),
        .mem_store_fault(mem_store_fault),
        .amo_stall    (amo_stall),
        .ex_mem_flush (ex_mem_flush),
        .if_bram_addr  (bram_addr_b),
        .if_instr_dout(if_instr_dout),
        .ex_csr_addr (ex_csr_addr),
        .ex_csr_op   (ex_csr_op),
        .ex_csr_wdata(ex_csr_wdata),
        .mem_csr_addr(mem_csr_addr),
        .mem_csr_we  (mem_csr_we),
        .mem_csr_wdata(mem_csr_wdata),
        .priv_lvl     (priv_lvl),
        .pmp_fault_load (pmp_fault_ld),
        .pmp_fault_store(pmp_fault_st)
    );

    wb_stage u_wb (
        .clk        (clk),
        .rst_n      (rst_n),
        .ex_pc      (mem_pc),
        .ex_alu_result(mem_alu_result),
        .mem_mem_data(mem_mem_data),
        .ex_rd_addr (mem_rd_addr),
        .ex_rd_we   (mem_rd_we),
        .ex_mem_read (mem_mem_read),
        .ex_valid   (mem_valid),
        .ex_ebreak  (mem_ebreak),
        .wb_rd_addr (wb_rd_addr),
        .wb_rd_data (wb_rd_data),
        .wb_rd_we   (wb_rd_we),
        .wb_valid   (wb_valid),
        .wb_ebreak  (wb_ebreak)
    );

    assign pc_debug    = id_pc_r;
    assign instr_debug = id_instr_r;
    assign ebreak_debug = ex_ebreak;

endmodule
