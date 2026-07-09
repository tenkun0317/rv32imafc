module top (
    input  logic        clk,
    input  logic        rst_n,

    output logic [31:0] pc_debug,
    output logic [31:0] instr_debug,
    output logic        ebreak_debug
);

    logic [31:0] if_pc;
    logic [31:0] if_instr;
    logic [31:0] if_instr_dout;

    logic [31:0] id_instr_r;
    logic [31:0] id_pc_r;

    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [31:0] id_imm;
    logic [4:0]  id_alu_op;
    logic [1:0]  id_alu_a_sel, id_alu_b_sel;
    logic        id_rd_we, id_mem_read, id_mem_write;
    logic [2:0]  id_mem_type;
    logic        id_valid, id_ebreak;
    logic        ex_stall;

    logic [31:0] ex_pc, ex_alu_result, ex_rs2_data;
    logic [4:0]  ex_rd_addr;
    logic        ex_rd_we, ex_mem_read, ex_mem_write, ex_valid, ex_done, ex_ebreak;
    logic [2:0]  ex_mem_type;

    logic [31:0] mem_pc, mem_alu_result, mem_mem_data;
    logic [4:0]  mem_rd_addr;
    logic        mem_rd_we, mem_mem_read, mem_valid, mem_ebreak;

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

    logic        id_ecall, id_mret;
    logic        ex_ecall, ex_mret;
    logic        ex_trap_taken;
    logic [31:0] ex_trap_target;
    logic [31:0] csr_mtvec, csr_mepc;

    reg_file u_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs2_addr (id_rs2_addr),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_rd_data),
        .rd_we    (wb_rd_we),
        .rs1_data (reg_rs1_data),
        .rs2_data (reg_rs2_data)
    );

    logic        trap_trigger;
    logic [31:0] trap_cause_val, trap_tval_val;

    csr_reg u_csr (
        .clk   (clk),
        .rst_n (rst_n),
        .raddr (id_csr_addr),
        .rdata (csr_file_rdata),
        .we    (ex_csr_op != 3'h0),
        .waddr (ex_csr_addr),
        .wdata (ex_csr_wdata),
        .trap_trigger(trap_trigger),
        .trap_pc     (ex_pc),
        .trap_cause  (trap_cause_val),
        .trap_tval   (trap_tval_val),
        .mtvec_val(csr_mtvec),
        .mepc_val (csr_mepc)
    );

    // Trap control
    assign ex_trap_taken = (ex_ecall && ex_valid) && !ex_mret;
    assign ex_trap_target = ex_mret ? csr_mepc : csr_mtvec;

    // Trap CSR values (combinational)
    always_comb begin
        trap_trigger   = 1'b0;
        trap_cause_val = 32'h0;
        trap_tval_val  = 32'h0;
        if (ex_trap_taken) begin
            trap_trigger   = 1'b1;
            trap_tval_val  = 32'h0;
            if (ex_ecall)        trap_cause_val = 32'd11;
            else if (ex_ebreak)  trap_cause_val = 32'd3;
        end
    end

    // Trap taken or mret: redirect PC and flush IF/ID
    wire any_trap_taken = (ex_trap_taken || (ex_mret && ex_valid)) && ex_valid;

    // MEM flush on trap only (NOT on branch — branch must complete to write link register)
    assign ex_mem_flush = any_trap_taken;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_instr_r <= 32'h0;
            id_pc_r    <= 32'h0;
            ex_flush   <= 1'b0;
        end else begin
            ex_flush <= (ex_branch_taken || any_trap_taken) && ex_valid;
            if (any_trap_taken) begin
                id_instr_r <= 32'h00000013;
                id_pc_r    <= ex_trap_target;
            end else if (ex_branch_taken && ex_valid) begin
                id_instr_r <= 32'h00000013;
                id_pc_r    <= ex_branch_target;
            end else begin
                id_instr_r <= if_instr;
                id_pc_r    <= if_pc;
            end
        end
    end

    always_comb begin
        alu_rs1_data = reg_rs1_data;
        alu_rs2_data = reg_rs2_data;

        if (id_rs1_addr != 5'h0) begin
            if (ex_rd_we && ex_valid && ex_rd_addr == id_rs1_addr && !ex_mem_read) begin
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
            if (ex_rd_we && ex_valid && ex_rd_addr == id_rs2_addr && !ex_mem_read) begin
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

        // CSR forwarding
        id_csr_rdata_fwd = csr_file_rdata;
        if (id_csr_op != 3'h0) begin
            if (ex_csr_op != 3'h0 && ex_csr_addr == id_csr_addr) begin
                id_csr_rdata_fwd = ex_csr_wdata;
            end else if (mem_csr_we && mem_csr_addr == id_csr_addr) begin
                id_csr_rdata_fwd = mem_csr_wdata;
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
        .trap_target  (ex_trap_target),
        .if_pc        (if_pc),
        .if_instr     (if_instr)
    );

    id_stage u_id (
        .if_instr    (id_instr_r),
        .if_valid    (1'b1),
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
        .ex_stall    (ex_stall),
        .ex_done     (ex_done),
        .csr_rdata   (id_csr_rdata_fwd),
        .id_csr_addr (id_csr_addr),
        .id_csr_op   (id_csr_op),
        .id_csr_rdata(id_csr_rdata),
        .id_branch_op (id_branch_op),
        .id_branch_f3 (id_branch_f3)
    );

    ex_stage u_ex (
        .clk        (clk),
        .rst_n      (rst_n),
        .id_pc      (id_pc_r),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rs1_data(alu_rs1_data),
        .id_rs2_data(alu_rs2_data),
        .id_imm     (id_imm),
        .id_alu_op  (id_alu_op),
        .id_alu_a_sel(id_alu_a_sel),
        .id_alu_b_sel(id_alu_b_sel),
        .id_rd_addr (id_rd_addr),
        .id_rd_we   (id_rd_we),
        .id_mem_read (id_mem_read),
        .id_mem_write(id_mem_write),
        .id_mem_type (id_mem_type),
        .id_valid   (id_valid),
        .id_ebreak  (id_ebreak),
        .ex_pc      (ex_pc),
        .ex_alu_result(ex_alu_result),
        .ex_rs2_data (ex_rs2_data),
        .ex_rd_addr (ex_rd_addr),
        .ex_rd_we   (ex_rd_we),
        .ex_mem_read (ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_mem_type (ex_mem_type),
        .ex_valid   (ex_valid),
        .ex_ebreak  (ex_ebreak),
        .ex_ecall   (ex_ecall),
        .ex_mret    (ex_mret),
        .ex_done    (ex_done),
        .id_ecall   (id_ecall),
        .id_mret    (id_mret),
        .id_csr_addr (id_csr_addr),
        .id_csr_op   (id_csr_op),
        .id_csr_rdata(id_csr_rdata),
        .ex_csr_addr (ex_csr_addr),
        .ex_csr_op   (ex_csr_op),
        .ex_csr_rdata(ex_csr_rdata),
        .ex_csr_wdata(ex_csr_wdata),
        .id_branch_op  (id_branch_op),
        .id_branch_f3  (id_branch_f3),
        .ex_branch_taken(ex_branch_taken),
        .ex_branch_target(ex_branch_target),
        .ex_flush      (ex_flush)
    );

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
        .ex_mem_flush (ex_mem_flush),
        .if_pc       (if_pc),
        .if_instr_dout(if_instr_dout),
        .ex_csr_addr (ex_csr_addr),
        .ex_csr_op   (ex_csr_op),
        .ex_csr_wdata(ex_csr_wdata),
        .mem_csr_addr(mem_csr_addr),
        .mem_csr_we  (mem_csr_we),
        .mem_csr_wdata(mem_csr_wdata)
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
    assign ebreak_debug = wb_ebreak;

endmodule
