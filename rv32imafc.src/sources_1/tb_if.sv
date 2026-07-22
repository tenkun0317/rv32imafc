`timescale 1ns / 1ps

module tb_if;

    logic        clk;
    logic        rst_n;
    logic [31:0] instr_dout;
    logic        branch_taken;
    logic [31:0] branch_target;
    logic        trap_taken;
    logic [31:0] trap_target;
    logic        stall_i;
    logic [31:0] if_pc;
    logic [31:0] if_instr;

    // ---------------------------------------------------------------
    // BRAM behavioral model: 1-cycle read latency on port B
    // ---------------------------------------------------------------
    logic [31:0] mem [0:511];
    logic [31:0] bram_dout;

    always_ff @(posedge clk) begin
        bram_dout <= mem[addr_b[17:2]];
    end

    wire [31:0] addr_b = if_pc;

    assign instr_dout = bram_dout;

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    if_stage dut (
        .clk, .rst_n,
        .instr_dout,
        .branch_taken, .trap_taken, .stall_i,
        .branch_target, .trap_target,
        .if_pc, .if_instr
    );

    // ---------------------------------------------------------------
    // Clock and initial signals
    // ---------------------------------------------------------------
    always #5 clk = ~clk;

    int pass = 0;
    int fail = 0;

    // ---------------------------------------------------------------
    // Preload known instructions into BRAM model
    //
    // Memory layout (word-aligned addresses):
    //   Address       Word[31:16]     Word[15:0]
    //   0x80000000:   C.ADDI (0191)   C.MV    (870e)   -- 2 x 16-bit
    //   0x80000004:   NOP     (0013)  // upper 16-bit ignored
    //   0x80000008:   C.ADDI (0191)   LUI     (1537)   -- 1x16 + 1x32 (lower halfword)
    //   0x8000000C:   (0)             AUIPC   (0097)   -- 1x32 (upper halfword)
    //   0x80000010:   NOP     (0013)  // aligned 32-bit
    //   0x80000014:   NOP     (0013)  // aligned 32-bit
    //   0x80000018:   NOP     (0013)  // aligned 32-bit
    //   0x8000001C:   NOP     (0013)  // aligned 32-bit
    //   0x80000020:   NOP     (0013)  // aligned 32-bit (branch target)
    //   0x80000100:   NOP     (0013)  // trap target
    //
    // 16-bit compressed instructions used:
    //   C.ADDI x0, 0  = 0x0191
    //   C.MV   x0, x0 = 0x870e
    // 32-bit instructions used:
    //   NOP            = 0x00000013 (ADDI x0, x0, 0)
    //   LUI   x0, 1    = 0x00001537
    //   AUIPC x0, 0    = 0x0000F097
    // ---------------------------------------------------------------

    initial begin
        clk           = 1'b0;
        rst_n         = 1'b0;
        branch_taken  = 1'b0;
        branch_target = 32'h80000020;
        trap_taken    = 1'b0;
        trap_target   = 32'h80000100;
        stall_i       = 1'b0;

        for (int i = 0; i < 512; i++) mem[i] = 32'h00000013;  // fill rest with NOP

        // 0x80000000: word index = ((0x80000000 >> 2) & 0x3FFF) = 2048
        // For simplicity, map addr[17:2] so 0x80000000 >> 2 = 0x20000000,
        // but since BRAM uses addr_b[17:2] only, lower bits index into mem.
        //
        // 0x80000000 >> 2 = 17'h20000, >> 2 of a byte addr -> word addr at [17:2]:
        //   addr[17:2] of 0x80000000 = 0x80000000[17:2] = 0x20000
        //   but in our 512-deep model we only care about low 9 bits.
        //   For testbench we place instructions at entries addr_b[8:2] (low 7 bits of word addr).
        //   addr[8:2] of 0x80000000 = 0x00 (entry 0)
        //   addr[8:2] of 0x80000004 = 0x01 (entry 1)
        //   addr[8:2] of 0x80000008 = 0x02 (entry 2)
        //   etc.
        //
        // Since the if_stage always drives if_pc = pc (the word-aligned address),
        // addr_b will be 0x80000000, 0x80000004, 0x80000008, etc.
        // addr_b[8:2] = 0, 1, 2, 3, 4, 5, 6, 7, 8, ...

        // Entry 0: 0x80000000 -> C.ADDI + C.MV
        mem[0] = {16'h870e, 16'h0191};

        // Entry 1: 0x80000004 -> NOP (32-bit aligned)
        mem[1] = 32'h00000013;

        // Entry 2: 0x80000008 -> C.ADDI in lower 16, LUI halves across upper 16 + next word
        //   LUI x0,1 = 0x00001537. We place in upper16: 0x1537? No — 32-bit instr at offset 2 straddles
        //   0x80000008[15:0] = C.ADDI, 0x80000008[31:16] = LUI[15:0]? Actually LUI is 32-bit, needs both halfwords.
        //   Rather: 0x80000008 lower = C.ADDI; 0x80000008 upper = part of LUI? nono.
        //   LUI is 32-bit aligned at 0x80000008? That's misaligned. Let's simplify:
        //   Entry 2: lower 16 = 0x0191 (C.ADDI), upper 16 = 0x0013 (NOP upper half).
        //   Then entry 3 (0x8000000C) = full AUIPC.
        mem[2] = {16'h0000, 16'h0191};

        // Entry 3: 0x8000000C -> AUIPC
        mem[3] = {32'h0000f097[31:16], 32'h0000f097[15:0]};

        // Entries 4-7 (0x80000010 - 0x8000001C): NOP stream
        mem[4] = 32'h00000013;
        mem[5] = 32'h00000013;
        mem[6] = 32'h00000013;
        mem[7] = 32'h00000013;

        // Entry 8: 0x80000020 -> branch target, NOP
        mem[8] = 32'h00000013;

        // Entry 64: 0x80000100 -> trap target (0x80000100 >> 2 >> 2 = 64 in low bits)
        mem[64] = 32'h00000013;

        // Reset phase
        #10 rst_n = 1'b1;  // release reset at t=10ns

        // After reset, if_stage enters IDLE at pc=0x80000000.
        // At posedge after reset release, BRAM issues read at pc_aligned=0x80000000.
        // One cycle latency: bram_dout becomes mem[0] = {C.MV, C.ADDI}
        // Next posedge: IDLE->ACTIVE, consumes first instr, pc holds at 0x80000000.
        #10; check_step(0, 32'h00000013, "reset+1: IDLE, outputs NOP (garbage suppression)");

        // posedge at t=20: IDLE->ACTIVE, first instruction consumed from mem[0]
        // pc=0x80000000, pc[0]==0, pc[1]==0, inst_lsb = instr_dout[1:0] = 0x91[1:0] = 01 != 11 -> is_16bit=1
        // if_instr = instr_lower = {16'h0, 0x0191} = 0x00000191 (C.ADDI)
        // pc advances to pc+2 = 0x80000002. BRAM addr = pc_aligned = 0x80000000 (same word), dout_b still mem[0]
        #10; check_step(1, 32'h00000191, "first instr: C.ADDI from mem[0] at pc=0x80000000");

        // posedge at t=30: ACTIVE, pc=0x80000002
        // pc[0]==0, pc[1]==1 -> inst_lsb = instr_dout[17:16] = 0x870e[17:16] = 87? is_16bit? inst_lsb=87[1:0]=11 => NO
        // Wait: 0x870e[17:16] = 0x87 -> lower bits of 0x87 = 3'b011 -> lsb is 1? Actually byte 0x87 = 10000111 binary.
        // 0x87 in context of halfword byte: inst_lsb = upper halfword's bits[17:16] = lower 2 bits of upper byte = bits 17:16 = 0x87? 
        // instr_dout[17:16] = 0x87e? No. instr_dout = {0x870e, 0x0191} = 32'h870e0191
        // instr_dout[17:16] = 0x870e0191[17:16]: [31:16] = 870e, [17:16] of that = 0e? 
        // 0x870e0191: [31:24]=87, [23:16]=0e, [15:8]=01, [7:0]=91
        // [17:16] = part of high halfword first byte?
        // Actually bits are numbered: bit 0 is LSB. So [17:16] are bits 17 and 16:
        // bit 16 = 0x0191[16], bit 17 = 0x0191[17]? No — 32-bit value:
        // bit index: 31 30 ... 17 16 15 14 ... 0
        // 0x870e0191 in binary, bit16 = bit16 of 0191 = 0? Let me just compute:
        // 0191 = 0000000_001_1001_0001. bit16 = the 0 before "001"? Actually 16 bits of 0191:
        // 0x0191 = 16'b00000001_1001000_1? No: 0x0191 = 16'h0191 = 0000_0001_1001_0001
        // bit15 = 0, bit14 = 0, ..., bit8 = 1? Actually:
        // 0x0191: hex digits: 0 1 9 1
        // binary: 0000_0001_1001_0001
        // bit index: 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
        // bit[15:12] = 0000, bit[11:8] = 0001, bit[7:4] = 1001, bit[3:0] = 0001
        // So bit 16 of the 32-bit word is the 0-th bit of the upper halfword 0x870e.
        // 0x870e = 1000_0111_0000_1110
        // bit 16 (of 32-bit word) = bit 0 (of upper halfword) = 0 (bit 0 of 0x870e = 0)
        // bit 17 = bit 1 of upper halfword = 1
        // So inst_lsb = {bit17, bit16} = 2'b10 != 11 and != 00 => is_16bit = 1
        // if_instr = {16'h0, instr_dout[31:16]} = 0x0000870e (C.MV)
        // pc advances to pc+2 = 0x80000004. BRAM addr = pc_aligned = 0x80000004 (next word), dout_b becomes mem[1]

        #10; check_step(2, 32'h0000870e, "second instr: C.MV from mem[0] upper at pc=0x80000002");
    end
    end

endmodule