module mem_stage #(
    parameter RAM_INIT_FILE = "",
    parameter RAM_SIZE = 262144
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] ex_rs2_data,
    input  logic [2:0]  ex_mem_type,
    input  logic        ex_mem_read,
    input  logic        ex_mem_write,
    input  logic        ex_amo,
    input  logic [4:0]  ex_amo_op,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_rd_we,
    input  logic        ex_valid,
    input  logic        ex_ebreak,
    input  logic        ex_mem_flush,

    output logic [31:0] mem_pc,
    output logic [31:0] mem_alu_result,
    output logic [31:0] mem_mem_data,
    output logic [4:0]  mem_rd_addr,
    output logic        mem_rd_we,
    output logic        mem_mem_read,
    output logic        mem_valid,
    output logic        mem_ebreak,
    output logic        mem_load_fault,
    output logic        mem_store_fault,
    output logic        amo_stall,

    // IF instruction fetch via Port B
    input  logic [31:0] if_bram_addr,
    output logic [31:0] if_instr_dout,

    input  logic [11:0] ex_csr_addr,
    input  logic [2:0]  ex_csr_op,
    input  logic [31:0] ex_csr_wdata,
    output logic [11:0] mem_csr_addr,
    output logic        mem_csr_we,
    output logic [31:0] mem_csr_wdata,

    input  logic [1:0]  priv_lvl,
    input  logic        pmp_fault_load,
    input  logic        pmp_fault_store
);

    // AMO opcodes (funct5)
    localparam AMO_ADD  = 5'b00000;
    localparam AMO_SWAP = 5'b00001;
    localparam LR_W     = 5'b00010;
    localparam SC_W     = 5'b00011;
    localparam AMOXOR   = 5'b00100;
    localparam AMOAND   = 5'b01100;
    localparam AMOOR    = 5'b01000;
    localparam AMOMIN   = 5'b10000;
    localparam AMOMAX   = 5'b10100;
    localparam AMOMINU  = 5'b11000;
    localparam AMOMAXU  = 5'b11100;

    // ================================================================
    //  Registered MEM pipeline state (captures from EX_OUT each cycle
    //  unless holding).  Used during AMO_BUSY so that EX_OUT can
    //  advance past the AMO without losing its operands.
    // ================================================================
    logic [31:0] mem_rs2_data_q;
    logic        mem_amo_q;
    logic [4:0]  mem_amo_op_q;
    logic        mem_mem_write_q;

    // Control decode using REGISTERED AMO operands (valid during AMO_BUSY
    // because the pipeline registers hold).  The "entering" decode below
    // uses the combinational ex_* signals.
    wire a_arith = mem_amo_q && (mem_amo_op_q inside {AMO_ADD, AMOXOR, AMOAND, AMOOR, AMOMIN, AMOMAX, AMOMINU, AMOMAXU});
    wire a_lr    = mem_amo_q && (mem_amo_op_q == LR_W);
    wire a_sc    = mem_amo_q && (mem_amo_op_q == SC_W);
    wire a_swap  = mem_amo_q && (mem_amo_op_q == AMO_SWAP);
    wire a_write = a_sc || a_swap || a_arith;
    wire a_read  = a_lr || a_arith || a_swap;

    // Detection of a new AMO / LR / SC arriving from EX_OUT (comb.)
    wire amo_entering = ex_amo && ex_valid && !ex_mem_flush;

    // AMO state machine
    typedef enum logic {
        AMO_IDLE = 1'b0,
        AMO_BUSY = 1'b1
    } amo_state_t;
    amo_state_t amo_state, amo_state_next;

    always_comb begin
        amo_state_next = amo_state;
        unique case (amo_state)
            AMO_IDLE: if (amo_entering) amo_state_next = AMO_BUSY;
            AMO_BUSY: amo_state_next = AMO_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            amo_state <= AMO_IDLE;
        else if (ex_mem_flush)
            amo_state <= AMO_IDLE;
        else
            amo_state <= amo_state_next;
    end

    // Only holds MEM registers; the earlier pipeline stages advance normally.
    // EX_OUT advances past the AMO on the same cycle it enters MEM, so
    // amo_entering does NOT re-fire on the subsequent cycle.
    assign amo_stall = (amo_state == AMO_BUSY);

    // BRAM signals
    logic [31:0] ram_dout, ram_dout_q;
    logic [3:0]  ram_we;
    logic [31:0] ram_din;
    logic [2:0]  mem_mem_type_q;

    logic [11:0] mem_csr_addr_q;
    logic        mem_csr_we_q;
    logic [31:0] mem_csr_wdata_q;

    // Registered address is stable during the AMO write phase
    wire [31:0] data_ram_addr = (amo_state != AMO_IDLE) ? mem_alu_result : ex_alu_result;

    // AMO arithmetic result (uses registered rs2_data during the write phase)
    logic [31:0] amo_result_data;
    always_comb begin
        amo_result_data = 32'h0;
        if (a_arith && (amo_state == AMO_BUSY)) begin
            unique case (mem_amo_op_q)
                AMO_ADD:  amo_result_data = ram_dout + mem_rs2_data_q;
                AMOXOR:   amo_result_data = ram_dout ^ mem_rs2_data_q;
                AMOAND:   amo_result_data = ram_dout & mem_rs2_data_q;
                AMOOR:    amo_result_data = ram_dout | mem_rs2_data_q;
                AMOMIN: begin
                    if (ram_dout[31] == mem_rs2_data_q[31])
                        amo_result_data = ram_dout[30:0] < mem_rs2_data_q[30:0] ? ram_dout : mem_rs2_data_q;
                    else
                        amo_result_data = ram_dout[31] ? ram_dout : mem_rs2_data_q;
                end
                AMOMAX: begin
                    if (ram_dout[31] == mem_rs2_data_q[31])
                        amo_result_data = ram_dout[30:0] > mem_rs2_data_q[30:0] ? ram_dout : mem_rs2_data_q;
                    else
                        amo_result_data = ram_dout[31] ? mem_rs2_data_q : ram_dout;
                end
                AMOMINU: amo_result_data = ram_dout < mem_rs2_data_q ? ram_dout : mem_rs2_data_q;
                AMOMAXU: amo_result_data = ram_dout > mem_rs2_data_q ? ram_dout : mem_rs2_data_q;
                default:  amo_result_data = 32'h0;
            endcase
        end
    end

    // LR/SC reservation (single-core — always succeeds)
    logic reservation_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reservation_valid_q <= 1'b0;
        else if (ex_mem_flush)
            reservation_valid_q <= 1'b0;
        else if (ex_amo && (ex_amo_op == LR_W) && ex_valid && !ex_mem_flush)
            reservation_valid_q <= 1'b1;
        else if (mem_amo_q && (mem_amo_op_q == SC_W) && (amo_state == AMO_BUSY))
            reservation_valid_q <= 1'b0;
    end

    // Byte/halfword/word store: generate byte enables and replicate data.
    // AMO overrides are merged into the same always_comb.
    always_comb begin
        ram_we  = 4'b0;
        ram_din = ex_rs2_data;

        // Normal (non-AMO) store
        if (ex_mem_write && !ex_amo) begin
            case (ex_mem_type)
                3'b000: begin
                    ram_we = 4'b0001 << ex_alu_result[1:0];
                    ram_din = {4{ex_rs2_data[7:0]}};
                end
                3'b001: begin
                    ram_we = {2'b0, 2'b11} << {ex_alu_result[1], 1'b0};
                    ram_din = {2{ex_rs2_data[15:0]}};
                end
                3'b010: begin
                    ram_we = 4'b1111;
                    ram_din = ex_rs2_data;
                end
                default: begin
                    ram_we = 4'b1111;
                    ram_din = ex_rs2_data;
                end
            endcase
        end

        // --- AMO write overrides ---

        // Arithmetic AMO second cycle: write computed result using REGISTERED data
        if (a_arith && (amo_state == AMO_BUSY)) begin
            ram_we = 4'b1111;
            ram_din = amo_result_data;
        end

        // AMOSWAP: write rs2 in same cycle as read (uses registered rs2)
        if (a_swap && (amo_state == AMO_BUSY)) begin
            ram_we = 4'b1111;
            ram_din = mem_rs2_data_q;
        end

        // SC.W: write only if reservation valid
        if (a_sc && (amo_state == AMO_BUSY) && reservation_valid_q) begin
            ram_we = 4'b1111;
            ram_din = mem_rs2_data_q;
        end

        if (ex_mem_flush) ram_we = 4'b0;
    end

    unified_bram #(
        .RAM_SIZE   (RAM_SIZE),
        .INIT_FILE  (RAM_INIT_FILE)
    ) u_ram (
        .clk   (clk),
        .addr_a(data_ram_addr),
        .we_a  (ram_we),
        .din_a (ram_din),
        .dout_a(ram_dout),

        .addr_b(if_bram_addr),
        .we_b  (4'b0),
        .din_b (32'h0),
        .dout_b(if_instr_dout)
    );

    // ================================================================
    //  Load data mux
    //  For SC.W the rd return value is 0 (success) / 1 (failure).
    // ================================================================
    always_comb begin
        // SC.W override
        if (a_sc && (amo_state == AMO_BUSY))
            mem_mem_data = {31'b0, ~reservation_valid_q};
        else begin
            unique case (mem_mem_type_q)
                3'b000: begin
                    unique case (mem_alu_result[1:0])
                        2'b00: mem_mem_data = {{24{ram_dout[7]}},  ram_dout[7:0]};
                        2'b01: mem_mem_data = {{24{ram_dout[15]}}, ram_dout[15:8]};
                        2'b10: mem_mem_data = {{24{ram_dout[23]}}, ram_dout[23:16]};
                        2'b11: mem_mem_data = {{24{ram_dout[31]}}, ram_dout[31:24]};
                    endcase
                end
                3'b001: begin
                    unique case (mem_alu_result[1])
                        1'b0: mem_mem_data = {{16{ram_dout[15]}}, ram_dout[15:0]};
                        1'b1: mem_mem_data = {{16{ram_dout[31]}}, ram_dout[31:16]};
                    endcase
                end
                3'b010: mem_mem_data = ram_dout;
                3'b100: begin
                    unique case (mem_alu_result[1:0])
                        2'b00: mem_mem_data = {24'h0, ram_dout[7:0]};
                        2'b01: mem_mem_data = {24'h0, ram_dout[15:8]};
                        2'b10: mem_mem_data = {24'h0, ram_dout[23:16]};
                        2'b11: mem_mem_data = {24'h0, ram_dout[31:24]};
                    endcase
                end
                3'b101: begin
                    unique case (mem_alu_result[1])
                        1'b0: mem_mem_data = {16'h0, ram_dout[15:0]};
                        1'b1: mem_mem_data = {16'h0, ram_dout[31:16]};
                    endcase
                end
                default: mem_mem_data = ram_dout;
            endcase
        end
    end

    // ================================================================
    //  MEM pipeline registers
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_pc          <= 32'h0;
            mem_alu_result  <= 32'h0;
            mem_rd_addr     <= 5'h0;
            mem_rd_we       <= 1'b0;
            mem_mem_read    <= 1'b0;
            mem_valid       <= 1'b0;
            mem_ebreak      <= 1'b0;
            mem_mem_type_q  <= 3'h0;
            ram_dout_q      <= 32'h0;
            mem_rs2_data_q  <= 32'h0;
            mem_amo_q       <= 1'b0;
            mem_amo_op_q    <= 5'h0;
            mem_mem_write_q <= 1'b0;
            mem_csr_addr_q  <= 12'h0;
            mem_csr_we_q    <= 1'b0;
            mem_csr_wdata_q <= 32'h0;
        end else if (ex_mem_flush) begin
            mem_pc          <= 32'h0;
            mem_alu_result  <= 32'h0;
            mem_rd_addr     <= 5'h0;
            mem_rd_we       <= 1'b0;
            mem_mem_read    <= 1'b0;
            mem_valid       <= 1'b0;
            mem_ebreak      <= 1'b0;
            mem_mem_type_q  <= 3'h0;
            ram_dout_q      <= 32'h0;
            mem_rs2_data_q  <= 32'h0;
            mem_amo_q       <= 1'b0;
            mem_amo_op_q    <= 5'h0;
            mem_mem_write_q <= 1'b0;
            mem_csr_addr_q  <= 12'h0;
            mem_csr_we_q    <= 1'b0;
            mem_csr_wdata_q <= 32'h0;
        end else if (amo_state == AMO_BUSY) begin
            // Hold — keep AMO state for the write phase
        end else begin
            mem_pc          <= ex_pc;
            mem_alu_result  <= ex_alu_result;
            mem_rd_addr     <= ex_rd_addr;
            mem_rd_we       <= ex_rd_we;
            mem_mem_read    <= ex_mem_read;
            mem_valid       <= ex_valid;
            mem_ebreak      <= ex_ebreak;
            mem_mem_type_q  <= ex_mem_type;
            ram_dout_q      <= ram_dout;
            mem_rs2_data_q  <= ex_rs2_data;
            mem_amo_q       <= ex_amo;
            mem_amo_op_q    <= ex_amo_op;
            mem_mem_write_q <= ex_mem_write;
            mem_csr_addr_q  <= ex_csr_addr;
            mem_csr_we_q    <= (ex_csr_op != 3'h0);
            mem_csr_wdata_q <= ex_csr_wdata;
        end
    end

    assign mem_csr_addr = mem_csr_addr_q;
    assign mem_csr_we   = mem_csr_we_q;
    assign mem_csr_wdata = mem_csr_wdata_q;

    // Load / Store access fault detection (addr range + PMP)
    wire mem_addr_hi_in_range = (mem_alu_result >= 32'h80000000) && (mem_alu_result < 32'h80000000 + RAM_SIZE);
    wire mem_addr_lo_in_range = (mem_alu_result < RAM_SIZE);
    wire mem_addr_in_range = mem_addr_hi_in_range || mem_addr_lo_in_range;
    assign mem_load_fault  = mem_mem_read && mem_valid && (!mem_addr_in_range || pmp_fault_load);
    wire ex_mem_write_comb = ex_mem_write || ex_amo;
    assign mem_store_fault = ex_mem_write_comb && ex_valid && (!mem_addr_in_range || pmp_fault_store);

endmodule
