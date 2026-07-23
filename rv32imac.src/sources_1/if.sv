module if_stage (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] instr_dout,

    input  logic        branch_taken,
    input  logic [31:0] branch_target,

    input  logic        trap_taken,
    input  logic [31:0] trap_target,

    input  logic        fence_i_flush,

    input  logic        stall_i,

    input  logic [1:0]  priv_lvl,

    input  logic        pmp_fault_i,

    output logic [31:0] if_pc,
    output logic [31:0] if_bram_addr,
    output logic [31:0] if_instr,
    output logic        if_access_fault
);

    logic [31:0] pc;
    logic [31:0] fetch_addr;
    logic        data_valid;
    logic        straddle_pend;
    logic        straddle_wait;
    logic [15:0] straddle_lo;

    assign if_bram_addr = fetch_addr;
    assign if_pc = pc;

    wire [31:0] pc_word = pc & 32'hFFFF_FFFC;

    // Instruction detection from instr_dout
    wire        upper_half = pc[1];
    wire [15:0] cur16 = upper_half ? instr_dout[31:16] : instr_dout[15:0];
    wire [1:0]  ilsb = cur16[1:0];
    wire        is_16bit = (ilsb != 2'b11);
    wire        is_32bit = (ilsb == 2'b11);
    wire        straddle = is_32bit && upper_half;

    wire        can_issue = data_valid && !stall_i && !straddle_pend && !straddle_wait && !straddle;

    // Straddle instruction: {next_word[15:0], current_word[31:16]}
    wire [31:0] straddle_instr = {instr_dout[15:0], straddle_lo};

    assign if_instr = straddle_pend      ? straddle_instr
                    : !can_issue         ? 32'h00000013
                    : is_16bit           ? {16'h0000, cur16}
                    :                      instr_dout;

    wire [31:0] pc_inc = is_16bit ? 32'd2 : 32'd4;
    wire [31:0] pc_next = can_issue ? pc + pc_inc : pc;
    wire        word_change = (pc_next[31:2] != pc[31:2]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc            <= 32'h80000000;
            fetch_addr    <= 32'h80000000;
            data_valid    <= 1'b0;
            straddle_pend <= 1'b0;
            straddle_wait <= 1'b0;
            straddle_lo   <= 16'h0;

        end else if (stall_i) begin
            if (!data_valid) data_valid <= 1'b1;

        end else if (branch_taken || trap_taken || fence_i_flush) begin
            automatic logic [31:0] tgt = trap_taken ? trap_target : branch_target;
            if (fence_i_flush) begin
                pc            <= pc;
                fetch_addr    <= pc & 32'hFFFF_FFFC;
                data_valid    <= 1'b0;
                straddle_pend <= 1'b0;
                straddle_wait <= 1'b0;
            end else begin
                pc            <= tgt;
                fetch_addr    <= tgt & 32'hFFFF_FFFC;
                data_valid    <= 1'b0;
                straddle_pend <= 1'b0;
                straddle_wait <= 1'b0;
            end

        end else begin
            if (straddle_pend) begin
                // BRAM data has arrived from next word fetch.
                // Assemble and issue the straddled instruction.
                pc            <= pc + 32'd4;
                fetch_addr    <= (pc + 32'd4) & 32'hFFFF_FFFC;
                data_valid    <= 1'b1;
                straddle_pend <= 1'b0;

            end else if (straddle_wait) begin
                // unified_bram has a registered read port.  The cycle after
                // changing fetch_addr still returns the old word, so wait one
                // additional cycle before consuming the next word's low half.
                straddle_wait <= 1'b0;
                straddle_pend <= 1'b1;

            end else if (can_issue) begin
                pc <= pc_next;
                if (word_change) begin
                    data_valid <= 1'b0;
                    fetch_addr <= pc_next & 32'hFFFF_FFFC;
                end

            end else if (data_valid && straddle) begin
                // 32-bit instruction at upper half of current word.
                // Fetch next word for the upper 16 bits.
                straddle_wait <= 1'b1;
                straddle_lo   <= instr_dout[31:16];
                data_valid    <= 1'b0;
                fetch_addr    <= pc_word + 32'd4;

            end else if (!data_valid) begin
                data_valid <= 1'b1;
                fetch_addr <= pc & 32'hFFFF_FFFC;
            end
        end
    end

    localparam RAM_SIZE = 262144;
    wire pc_in_hi_ram = (pc >= 32'h80000000) && (pc < 32'h80000000 + RAM_SIZE);
    wire pc_in_lo_ram = (pc < RAM_SIZE);
    assign if_access_fault = !(pc_in_hi_ram || pc_in_lo_ram) || pmp_fault_i;

endmodule
