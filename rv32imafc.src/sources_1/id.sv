module id_stage (
    input  logic [31:0] if_instr,
    input  logic        if_valid,
    input  logic        if_access_fault,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,

    output logic [4:0]  id_rs1_addr,
    output logic [4:0]  id_rs2_addr,
    output logic [31:0] id_imm,
    output logic [5:0]  id_alu_op,
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
    output logic        id_mul_div,  // 1 for multiply/divide instructions
    output logic        id_amo,      // 1 for AMO / LR / SC
    output logic [4:0]  id_amo_op,  // funct5 for AMO/LR/SC
    output logic        id_illegal,
    output logic        id_if_access_fault,

    output logic        ex_stall,
    input  logic        ex_done,

    input  logic [31:0] csr_rdata,
    output logic [11:0] id_csr_addr,
    output logic [2:0]  id_csr_op,
    output logic [31:0] id_csr_rdata,

    output logic [1:0]  id_branch_op,
    output logic [2:0]  id_branch_f3
);

    // ================================================================
    //  C-extension expander: 16-bit → 32-bit
    // ================================================================
    logic [31:0] expanded_instr;
    logic        expander_illegal;
    always_comb begin
        expanded_instr   = if_instr;  // pass-through for 32-bit
        expander_illegal = 1'b0;

        if (if_instr[1:0] != 2'b11) begin
            unique case (if_instr[1:0])
                2'b00: begin  // Quadrant 0
                    unique case (if_instr[15:13])
                 3'b000: begin // C.ADDI4SPN
                              if (|if_instr[12:5]) begin
                                  // ADDI rd', x2, nzuimm
                                  // nzuimm is zero-extended
                                  // nzuimm[9:0] = {inst[12:7], inst[12:11], inst[5], inst[6], 2'b00} ← no wait
                                  // Actually: nzuimm[9]=inst[10], nzuimm[8]=inst[9], nzuimm[7]=inst[8],
                                  // nzuimm[6]=inst[7], nzuimm[5]=inst[12], nzuimm[4]=inst[11],
                                  // nzuimm[3]=inst[5], nzuimm[2]=inst[6], nzuimm[1:0]=00
                                  // Zero-extend to 12 bits for ADDI: {2'b00, nzuimm[9:0]}
                                  expanded_instr = {2'b00, if_instr[10:7], if_instr[12:11], if_instr[5], if_instr[6], 2'b00,
                                                    5'd2, 3'b000, 2'b01, if_instr[4:2], 7'b0010011};
                              end else begin
                                  expander_illegal = 1'b1;
                                  expanded_instr = 32'h00000013;
                              end
                          end
                          3'b010: begin // C.LW
                             // LW rd'(x8+inst[4:2]), offset(rs1'=x8+inst[9:7])
                             // offset[6:0] = {inst[12], inst[11:10], inst[6], inst[5], 2'b00}
                             // signed offset = sign_ext(offset[6:0]) → {{5{offset[6]}}, offset[6:0]} = 12 bits
                             expanded_instr = {{5{if_instr[12]}}, if_instr[12], if_instr[11:10], if_instr[6], if_instr[5], 2'b00,
                                               2'b01, if_instr[9:7], 3'b010, 2'b01, if_instr[4:2], 7'b0000011};
                         end
                          3'b110: begin // C.SW
                              // SW rs2'(x8+inst[4:2]), offset(rs1'=x8+inst[9:7])
                              // offset[6:0] = {inst[12], inst[11:10], inst[6], inst[5], 2'b00}
                              // S-type imm[11:0] = {{5{offset[6]}}, offset[6:0]}
                              // S-type: {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}
                              // imm[11:5] = {{5{inst[12]}}, inst[12], inst[11]}
                              // imm[4:0]  = {inst[10], inst[6], inst[5], 2'b00}
                              expanded_instr = {{5{if_instr[12]}}, if_instr[12], if_instr[11],
                                                2'b01, if_instr[4:2],
                                                2'b01, if_instr[9:7],
                                                3'b010,
                                                if_instr[10], if_instr[6], if_instr[5], 2'b00,
                                                7'b0100011};
                         end
                          3'b100: begin // Zcb: CLB/CLH/CSB/CSH loads/stores
                              unique case (if_instr[12:10])
                                  3'b000: begin // c.lbu
                                      // LBU rd', uimm(rs1'), uimm = {inst[12], inst[6], inst[5]}
                                      expanded_instr = {9'b000_000_000, if_instr[12], if_instr[6], if_instr[5],
                                                        2'b01, if_instr[9:7], 3'b100, 2'b01, if_instr[4:2], 7'b0000011};
                                  end
                                  3'b001: begin // c.lhu (bit6=0) or c.lh (bit6=1)
                                      if (if_instr[6] == 1'b0) begin
                                          // c.lhu: LHU rd', uimm(rs1')
                                          expanded_instr = {6'b000000, if_instr[12], if_instr[6], if_instr[5], if_instr[4], if_instr[3], 1'b0,
                                                            2'b01, if_instr[9:7], 3'b101, 2'b01, if_instr[4:2], 7'b0000011};
                                      end else begin
                                          // c.lh: LH rd', uimm(rs1')
                                          expanded_instr = {6'b000000, if_instr[12], if_instr[6], if_instr[5], if_instr[4], if_instr[3], 1'b0,
                                                            2'b01, if_instr[9:7], 3'b001, 2'b01, if_instr[4:2], 7'b0000011};
                                      end
                                  end
                                  3'b010: begin // c.sb
                                      // SB rs2', uimm(rs1'), uimm = {inst[12], inst[6], inst[5]}
                                      expanded_instr = {6'b000000, if_instr[12],
                                                        2'b01, if_instr[4:2],
                                                        2'b01, if_instr[9:7],
                                                        3'b000,
                                                        if_instr[6], if_instr[5], 3'b000,
                                                        7'b0100011};
                                  end
                                  3'b011: begin // c.sh
                                      // SH rs2', uimm(rs1')
                                      expanded_instr = {6'b000000, if_instr[12],
                                                        2'b01, if_instr[4:2],
                                                        2'b01, if_instr[9:7],
                                                        3'b001,
                                                        if_instr[6], if_instr[5], if_instr[4], if_instr[3], 1'b0,
                                                        7'b0100011};
                                  end
                                  default: begin
                                      expander_illegal = 1'b1;
                                      expanded_instr = 32'h00000013;
                                  end
                              endcase
                          end

                          default: begin
                              expander_illegal = 1'b1;
                              expanded_instr = 32'h00000013;
                          end
                      endcase
                  end

                 2'b01: begin  // Quadrant 1
                    unique case (if_instr[15:13])
                        3'b000: begin // C.ADDI / C.NOP
                            // ADDI rd, rd, imm[5:0]
                            // imm = sign_ext({inst[12], inst[6:2]})
                            expanded_instr = {{26{if_instr[12]}}, if_instr[12], if_instr[6:2],
                                              if_instr[11:7], 3'b000, if_instr[11:7], 7'b0010011};
                        end
                         3'b001: begin // C.JAL (RV32)
                              // From binutils EXTRACT_RVC_J_IMM:
                              // offset = ((inst>>3)&0x7)<<1 | ((inst>>11)&1)<<4 |
                              //          ((inst>>2)&1)<<5  | ((inst>>7)&1)<<6  |
                              //          ((inst>>6)&1)<<7  | ((inst>>9)&0x3)<<8 |
                              //          ((inst>>8)&1)<<10 | (-(inst>>12)&1)<<11
                              // offset bits mapped to JAL expanded instr:
                              //   offset[10] = inst[8],  offset[9] = inst[10]
                              //   offset[8]  = inst[9],  offset[7] = inst[6]
                              //   offset[6]  = inst[7],  offset[5] = inst[2]
                              //   offset[4]  = inst[11], offset[3] = inst[5]
                              //   offset[2]  = inst[4],  offset[1] = inst[3]
                              //   offset[11] = inst[12] (sign)
                              // expanded_instr[31]   = offset[20] = inst[12]
                              // expanded_instr[30:21] = offset[10:1] = {inst[8],inst[10],inst[9],inst[6],inst[7],inst[2],inst[11],inst[5],inst[4],inst[3]}
                              // expanded_instr[20]   = offset[11] = inst[12]
                              // expanded_instr[19:12] = offset[19:12] = {8{inst[12]}}
                              expanded_instr = {if_instr[12],
                                                if_instr[8], if_instr[10], if_instr[9],
                                                if_instr[6], if_instr[7],
                                                if_instr[2],
                                                if_instr[11],
                                                if_instr[5], if_instr[4], if_instr[3],
                                                if_instr[12],
                                                {8{if_instr[12]}},
                                                5'd1,
                                                7'b1101111};
                        end
                         3'b010: begin // C.LI
                             // LI rd, imm = ADDI rd, x0, imm
                             // imm = sign_ext({inst[12], inst[6:2]})
                             expanded_instr = {{26{if_instr[12]}}, if_instr[12], if_instr[6:2],
                                               5'b0, 3'b000, if_instr[11:7], 7'b0010011};
                         end
                         3'b011: begin // C.ADDI16SP / C.LUI
                              if (if_instr[11:7] == 5'd2) begin
                                  // C.ADDI16SP: ADDI x2, x2, nzimm
                                  // nzimm[9:4] = {inst[12], inst[6:2]}, nzimm[3:0] = 0
                                  // sign-extend 10-bit nzimm to 12-bit ADDI imm:
                                  // imm[11:0] = {nzimm[9], nzimm[9], nzimm[9:0]}
                                  //           = {inst[12], inst[12], inst[12], inst[6:2], 4'b0000}
                                  // Bit count: 1+1+1+5+4 = 12 ✓
                                  expanded_instr = {if_instr[12], if_instr[12], if_instr[12], if_instr[6:2], 4'b0000,
                                                    5'd2, 3'b000, 5'd2, 7'b0010011};
                             end else if (if_instr[11:7] != 5'b0) begin
                                 // C.LUI: LUI rd, imm[17:12]
                                 // imm = sign_ext({inst[12], inst[6:2]}) << 12
                                 expanded_instr = {{14{if_instr[12]}}, if_instr[12], if_instr[6:2],
                                                   if_instr[11:7], 7'b0110111};
                             end else begin
                                 expanded_instr = 32'h00000013; // NOP (HINT)
                             end
                        end
                         3'b100: begin // CB/CA-format ops (decode via funct2, bit[12] is shamt/imm)
                             unique case (if_instr[11:10])
                                 2'b00: begin // C.SRLI rd', shamt
                                     expanded_instr = {7'b0000000, if_instr[6:2],
                                                       2'b01, if_instr[9:7], 3'b101, 2'b01, if_instr[9:7], 7'b0010011};
                                 end
                                 2'b01: begin // C.SRAI rd', shamt
                                     expanded_instr = {7'b0100000, if_instr[6:2],
                                                       2'b01, if_instr[9:7], 3'b101, 2'b01, if_instr[9:7], 7'b0010011};
                                 end
                                 2'b10: begin // C.ANDI rd', imm
                                     expanded_instr = {{26{if_instr[12]}}, if_instr[12], if_instr[6:2],
                                                       2'b01, if_instr[9:7], 3'b111, 2'b01, if_instr[9:7], 7'b0010011};
                                 end
                                2'b11: begin // CA-format ALU ops + Zcb
                                    unique case (if_instr[6:5])
                                        2'b00: begin // C.SUB: SUB rd', rd', rs2'
                                            expanded_instr = {7'b0100000, 2'b01, if_instr[4:2],
                                                              2'b01, if_instr[9:7], 3'b000, 2'b01, if_instr[9:7], 7'b0110011};
                                        end
                                        2'b01: begin // C.XOR: XOR rd', rd', rs2'
                                            expanded_instr = {7'b0000000, 2'b01, if_instr[4:2],
                                                              2'b01, if_instr[9:7], 3'b100, 2'b01, if_instr[9:7], 7'b0110011};
                                        end
                                        2'b10: begin // C.OR: OR rd', rd', rs2'
                                            expanded_instr = {7'b0000000, 2'b01, if_instr[4:2],
                                                              2'b01, if_instr[9:7], 3'b110, 2'b01, if_instr[9:7], 7'b0110011};
                                        end
                                        2'b11: begin // Zcb unary or C.AND
                                            unique case (if_instr[4:2])
                                                3'b000: begin // c.zext.b
                                                    expanded_instr = {12'h0FF, 2'b01, if_instr[9:7], 3'b111, 2'b01, if_instr[9:7], 7'b0010011};
                                                end
                                                3'b001: begin // c.sext.b
                                                    expanded_instr = {7'b0110000, 5'b00100, 2'b01, if_instr[9:7], 3'b001, 2'b01, if_instr[9:7], 7'b0010011};
                                                end
                                                3'b010: begin // c.zext.h
                                                    expanded_instr = {7'b0000100, 5'b00000, 2'b01, if_instr[9:7], 3'b100, 2'b01, if_instr[9:7], 7'b0110011};
                                                end
                                                3'b011: begin // c.sext.h
                                                    expanded_instr = {7'b0110000, 5'b00101, 2'b01, if_instr[9:7], 3'b001, 2'b01, if_instr[9:7], 7'b0010011};
                                                end
                                                3'b101: begin // c.not
                                                    expanded_instr = {12'hFFF, 2'b01, if_instr[9:7], 3'b100, 2'b01, if_instr[9:7], 7'b0010011};
                                                end
                                                default: begin // C.AND: AND rd', rd', rs2'
                                                    expanded_instr = {7'b0000000, 2'b01, if_instr[4:2],
                                                                      2'b01, if_instr[9:7], 3'b111, 2'b01, if_instr[9:7], 7'b0110011};
                                                end
                                            endcase
                                        end
                                        default: begin
                                            expander_illegal = 1'b1;
                                            expanded_instr = 32'h00000013;
                                        end
                                    endcase
                                end
                              endcase
                          end
                           3'b101: begin // C.J
                               // JAL x0, offset (same offset encoding as C.JAL)
                               // From binutils EXTRACT_RVC_J_IMM:
                               // offset[10:1] = {inst[8],inst[10],inst[9],inst[6],inst[7],inst[2],inst[11],inst[5],inst[4],inst[3]}
                               expanded_instr = {if_instr[12],
                                                 if_instr[8], if_instr[10], if_instr[9],
                                                 if_instr[6], if_instr[7],
                                                 if_instr[2],
                                                 if_instr[11],
                                                 if_instr[5], if_instr[4], if_instr[3],
                                                 if_instr[12],
                                                 {8{if_instr[12]}},
                                                 5'b0,
                                                 7'b1101111};
                         end
                          3'b110: begin // C.BEQZ
                             // BEQ rs1'(x8+inst[9:7]), x0, offset
                             // offset[8:0] = {inst[12], inst[6:5], inst[2], inst[11:10], inst[4:3], 1'b0}
                             // B-type: {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode}
                             // imm[12] = off[12] = off[8] = inst[12]
                             // imm[11] = off[11] = off[8] = inst[12]
                             // imm[10:5] = {off[10:5]} = {inst[12], inst[12], inst[12], inst[6], inst[5], inst[2]}
                             // rs2 = x0
                             // rs1 = x8 + inst[9:7] = {2'b01, inst[9:7]}
                             // imm[4:1] = off[4:1] = {inst[11], inst[10], inst[4], inst[3]}
                              expanded_instr = {if_instr[12],
                                                if_instr[12], if_instr[12], if_instr[12],
                                                if_instr[6], if_instr[5], if_instr[2],
                                                5'b00000,
                                                2'b01, if_instr[9:7],
                                                3'b000,
                                                if_instr[11], if_instr[10], if_instr[4], if_instr[3],
                                                if_instr[12],
                                                7'b1100011};
                         end
                          3'b111: begin // C.BNEZ
                              // BNE rs1'(x8+inst[9:7]), x0, offset
                              expanded_instr = {if_instr[12],
                                                if_instr[12], if_instr[12], if_instr[12],
                                                if_instr[6], if_instr[5], if_instr[2],
                                                5'b00000,
                                                2'b01, if_instr[9:7],
                                                3'b001,
                                                if_instr[11], if_instr[10], if_instr[4], if_instr[3],
                                                if_instr[12],
                                                7'b1100011};
                         end
                          default: begin
                              expander_illegal = 1'b1;
                              expanded_instr = 32'h00000013;
                          end
                     endcase
                 end

                2'b10: begin  // Quadrant 2
                    unique case (if_instr[15:13])
                 3'b000: begin // C.SLLI
                             // SLLI rd, rd, shamt (full 5-bit rd/rs1)
                             expanded_instr = {7'b0000000, if_instr[6:2],
                                               if_instr[11:7], 3'b001, if_instr[11:7], 7'b0010011};
                        end
                         3'b010: begin // C.LWSP
                             // LW rd, offset(x2)
                             // offset[5:0] = {inst[12], inst[6:2]}
                             expanded_instr = {{6{if_instr[12]}}, if_instr[12], if_instr[6:2],
                                               5'd2, 3'b010, if_instr[11:7], 7'b0000011};
                         end
                          3'b100: begin // C.MV / C.JR / C.ADD / C.JALR (CR format)
                              if (if_instr[12] == 1'b0) begin
                                  // funct4[0]=0: C.MV (rs2≠0) or C.JR (rs2=0)
                                  if (if_instr[6:2] == 5'b0) begin
                                      // C.JR rs1: JALR x0, 0(rs1)
                                      expanded_instr = {12'b0, if_instr[11:7], 3'b000, 5'b0, 7'b1100111};
                                  end else begin
                                      // C.MV rd, rs2: ADD rd, x0, rs2.  The
                                      // compressed rs2 field is a register,
                                      // not an ADDI immediate.
                                      expanded_instr = {7'b0000000, if_instr[6:2], 5'b0, 3'b000, if_instr[11:7], 7'b0110011};
                                  end
                              end else begin
                                  // funct4[0]=1: C.ADD (rs2≠0) or C.JALR (rs2=0)
                                  if (if_instr[6:2] == 5'b0) begin
                                      // C.JALR rs1: JALR x1, 0(rs1)
                                      expanded_instr = {12'b0, if_instr[11:7], 3'b000, 5'b1, 7'b1100111};
                                  end else begin
                                      // C.ADD rd, rs2: ADD rd, rd, rs2
                                      expanded_instr = {7'b0000000, if_instr[6:2], if_instr[11:7], 3'b000, if_instr[11:7], 7'b0110011};
                                  end
                              end
                          end
                         3'b110: begin // C.SWSP
                             // SW rs2, offset(x2)
                             // offset[5:0] = inst[12:7], rs2 = inst[6:2] (full 5-bit address)
                             expanded_instr = {{7{if_instr[12]}},
                                               if_instr[6:2],
                                               5'd2,
                                               3'b010,
                                               if_instr[11:7],
                                               7'b0100011};
                         end
                        3'b001, 3'b011, 3'b101, 3'b111: begin // Reserved / HINT
                            expanded_instr = 32'h00000013; // NOP
                        end
                    endcase
                end

                default: begin
                    expander_illegal = 1'b1;
                    expanded_instr = 32'h00000013; // illegal → NOP
                end
            endcase
        end
    end

    // ================================================================
    //  Standard 32-bit decoder
    // ================================================================
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [11:0] funct12;
    logic [4:0] rd, rs1, rs2;

    assign opcode = expanded_instr[6:0];
    assign funct3 = expanded_instr[14:12];
    assign funct7 = expanded_instr[31:25];
    assign funct12 = expanded_instr[31:20];
    assign rd  = expanded_instr[11:7];
    assign rs1 = expanded_instr[19:15];
    assign rs2 = expanded_instr[24:20];

    assign id_rs2_addr = rs2;
    assign id_rd_addr  = rd;

    assign id_csr_rdata = csr_rdata;

    always_comb begin
        id_imm = 32'h0;
        id_alu_op = 6'b0;
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
        id_illegal = expander_illegal;
        id_if_access_fault = if_access_fault;
        ex_stall = 1'b0;
        id_mul_div = 1'b0;
        id_amo = 1'b0;
        id_amo_op = 5'b0;
        id_rs1_addr = rs1;
        id_csr_addr = 12'h0;
        id_csr_op = 3'h0;
        id_branch_op = 2'h0;
        id_branch_f3 = 3'h0;

        case (opcode)
            7'b0110111: begin
                id_imm = {expanded_instr[31:12], 12'h0};
                id_alu_a_sel = 2'b01;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
            end
            7'b0010111: begin
                id_imm = {expanded_instr[31:12], 12'h0};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
            end
             7'b1101111: begin
                id_imm = {{11{expanded_instr[31]}}, expanded_instr[31], expanded_instr[19:12], expanded_instr[20], expanded_instr[30:21], 1'b0};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b10;
                id_rd_we = 1'b1;
                id_branch_op = 2'b10;
            end
             7'b1100111: begin
                id_imm = {{20{expanded_instr[31]}}, expanded_instr[31:20]};
                id_alu_a_sel = 2'b10;
                id_alu_b_sel = 2'b10;
                id_rd_we = 1'b1;
                id_branch_op = 2'b11;
            end
            7'b0000011: begin
                id_imm = {{20{expanded_instr[31]}}, expanded_instr[31:20]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
                id_mem_read = 1'b1;
                id_mem_type = funct3;
            end
            7'b0100011: begin
                id_imm = {{20{expanded_instr[31]}}, expanded_instr[31:25], expanded_instr[11:7]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_mem_write = 1'b1;
                id_mem_type = funct3;
            end
             7'b1100011: begin
                id_imm = {{19{expanded_instr[31]}}, expanded_instr[31], expanded_instr[7], expanded_instr[30:25], expanded_instr[11:8], 1'b0};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b00;
                id_alu_op = 6'b00001;
                id_branch_op = 2'b01;
                id_branch_f3 = funct3;
            end
            7'b0010011: begin
                id_imm = {{20{expanded_instr[31]}}, expanded_instr[31:20]};
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_rd_we = 1'b1;
                case (funct3)
                    3'b000: id_alu_op = 6'b00000; // ADDI
                    3'b010: id_alu_op = 6'b00010; // SLTI
                    3'b011: id_alu_op = 6'b00011; // SLTIU
                    3'b100: id_alu_op = 6'b00101; // XORI
                    3'b110: id_alu_op = 6'b01000; // ORI
                    3'b111: id_alu_op = 6'b01001; // ANDI
                    3'b001: begin
                        if (funct7 == 7'b0110000) begin // clz/ctz/cpop/sext.b/sext.h
                            case (expanded_instr[24:20])
                                5'b00000: id_alu_op = 6'b011100; // clz
                                5'b00001: id_alu_op = 6'b011101; // ctz
                                5'b00010: id_alu_op = 6'b011110; // cpop
                                5'b00100: id_alu_op = 6'b011111; // sext.b
                                5'b00101: id_alu_op = 6'b100000; // sext.h
                                default: id_illegal = 1'b1;
                            endcase
                        end else if (funct7 inside {7'b0010100, 7'b0100100, 7'b0110100}) begin
                            case (funct7)
                                7'b0010100: id_alu_op = 6'b100100; // bseti
                                7'b0100100: id_alu_op = 6'b100101; // bclri
                                7'b0110100: id_alu_op = 6'b100110; // binvi
                                default:    id_illegal = 1'b1;
                            endcase
                        end else if (funct7 == 7'b0000000) begin
                            id_alu_op = 6'b00100; // SLLI
                        end else begin
                            id_illegal = 1'b1;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0100100) begin
                            id_alu_op = 6'b100111; // bexti
                        end else if (funct7 == 7'b0110000) begin
                            id_alu_op = 6'b011011; // rori
                        end else if (funct7 == 7'b0010100 && expanded_instr[24:20] == 5'b00111) begin
                            id_alu_op = 6'b100010; // orc.b
                        end else if (funct7 == 7'b0110100 && expanded_instr[24:20] == 5'b11000) begin
                            id_alu_op = 6'b100011; // rev8
                        end else if (funct7[5]) begin
                            id_alu_op = 6'b00111; // SRAI
                        end else if (funct7 == 7'b0000000) begin
                            id_alu_op = 6'b00110; // SRLI
                        end else begin
                            id_illegal = 1'b1;
                        end
                    end
                    default: id_alu_op = 6'b0;
                endcase
            end
            7'b0110011: begin
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b00;
                id_rd_we = 1'b1;
                // Zicond: czero.eqz (funct7=0000111, funct3=101) / czero.nez (funct7=0000111, funct3=111)
                if (funct7 == 7'b0000111 && funct3 == 3'b101) begin
                    id_alu_op = 6'b01010;
                end else if (funct7 == 7'b0000111 && funct3 == 3'b111) begin
                    id_alu_op = 6'b01011;
                end else if (funct7 == 7'h01) begin
                    id_mul_div = 1'b1;
                    case (funct3)
                        3'b000: id_alu_op = 6'b01010; // MUL
                        3'b001: id_alu_op = 6'b01011; // MULH
                        3'b010: id_alu_op = 6'b01100; // MULHSU
                        3'b011: id_alu_op = 6'b01101; // MULHU
                        3'b100: begin                  // DIV
                            id_alu_op = 6'b01110;
                            if (ex_done) ex_stall = 1'b0;
                            else ex_stall = 1'b1;
                        end
                        3'b101: begin                  // DIVU
                            id_alu_op = 6'b01111;
                            if (ex_done) ex_stall = 1'b0;
                            else ex_stall = 1'b1;
                        end
                        3'b110: begin                  // REM
                            id_alu_op = 6'b10000;
                            if (ex_done) ex_stall = 1'b0;
                            else ex_stall = 1'b1;
                        end
                        3'b111: begin                  // REMU
                            id_alu_op = 6'b10001;
                            if (ex_done) ex_stall = 1'b0;
                            else ex_stall = 1'b1;
                        end
                        default: id_alu_op = 6'b0;
                    endcase
                // Zba: funct7=0010000 (0x10)
                end else if (funct7 == 7'b0010000) begin
                    case (funct3)
                        3'b010: id_alu_op = 6'b010000; // sh1add
                        3'b100: id_alu_op = 6'b010001; // sh2add
                        3'b110: id_alu_op = 6'b010010; // sh3add
                        default: id_illegal = 1'b1;
                    endcase
                // Zbb logic-neg: funct7=0100000 (0x20), funct3=100/110/111
                end else if (funct7 == 7'b0100000 && (funct3 inside {3'b100, 3'b110, 3'b111})) begin
                    case (funct3)
                        3'b111: id_alu_op = 6'b010011; // andn
                        3'b110: id_alu_op = 6'b010100; // orn
                        3'b100: id_alu_op = 6'b010101; // xnor
                        default: id_illegal = 1'b1;
                    endcase
                // Zbb min/max: funct7=0000101 (0x05)
                end else if (funct7 == 7'b0000101) begin
                    case (funct3)
                        3'b100: id_alu_op = 6'b010110; // min
                        3'b101: id_alu_op = 6'b010111; // minu
                        3'b110: id_alu_op = 6'b011000; // max
                        3'b111: id_alu_op = 6'b011001; // maxu
                        default: id_illegal = 1'b1;
                    endcase
                // Zbb rotates: funct7=0110000 (0x30)
                end else if (funct7 == 7'b0110000) begin
                    case (funct3)
                        3'b001: id_alu_op = 6'b011010; // rol
                        3'b101: id_alu_op = 6'b011011; // ror
                        default: id_illegal = 1'b1;
                    endcase
                // Zbs bset/bclr/binv (funct3=001): funct7=0010100/0100100/0110100
                end else if (funct3 == 3'b001 && (funct7 inside {7'b0010100, 7'b0100100, 7'b0110100})) begin
                    case (funct7)
                        7'b0010100: id_alu_op = 6'b100100; // bset
                        7'b0100100: id_alu_op = 6'b100101; // bclr
                        7'b0110100: id_alu_op = 6'b100110; // binv
                        default:    id_illegal = 1'b1;
                    endcase
                // Zbs bext: funct3=101, funct7=0100100 (0x24)
                end else if (funct3 == 3'b101 && funct7 == 7'b0100100) begin
                    id_alu_op = 6'b100111; // bext
                // Zbb zext.h: funct3=100, funct7=0000100 (0x04)
                end else if (funct3 == 3'b100 && funct7 == 7'b0000100) begin
                    id_alu_op = 6'b100001; // zext.h
                end else begin
                    case (funct3)
                        3'b000: begin
                            if (funct7[5]) id_alu_op = 6'b00001;
                            else id_alu_op = 6'b00000;
                        end
                        3'b001: id_alu_op = 6'b00100;
                        3'b010: id_alu_op = 6'b00010;
                        3'b011: id_alu_op = 6'b00011;
                        3'b100: id_alu_op = 6'b00101;
                        3'b101: begin
                            if (funct7[5]) id_alu_op = 6'b00111;
                            else id_alu_op = 6'b00110;
                        end
                        3'b110: id_alu_op = 6'b01000;
                        3'b111: id_alu_op = 6'b01001;
                        default: id_alu_op = 6'b0;
                    endcase
                end
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
                    id_csr_addr = expanded_instr[31:20];
                    id_csr_op   = funct3;
                    id_rd_we    = 1'b1;
                    id_rs1_addr = 5'h0;
                    id_imm      = {27'h0, rs1};
                 end else begin
                    // CSR register-variant: CSRRW (001), CSRRS (010), CSRRC (011)
                    id_csr_addr = expanded_instr[31:20];
                    id_csr_op   = funct3;
                    id_rd_we    = 1'b1;
                end
            end
            7'b0001111: begin
                // FENCE / FENCE.I — no architectural effect for this core
            end
            7'b0101111: begin
                // AMO / LR / SC
                id_amo     = 1'b1;
                id_amo_op  = expanded_instr[31:27];
                id_alu_a_sel = 2'b00;
                id_alu_b_sel = 2'b01;
                id_mem_type  = funct3;
                unique case (expanded_instr[31:27])
                    5'b00010: begin // LR.W
                        id_mem_read = 1'b1;
                        id_rd_we    = 1'b1;
                    end
                    5'b00011: begin // SC.W
                        id_mem_read  = 1'b1;
                        id_mem_write = 1'b1;
                        id_rd_we     = 1'b1;
                    end
                    default: begin // AMO (ADD, SWAP, XOR, AND, OR, MIN, MAX, MINU, MAXU)
                        if (expanded_instr[31:27] inside {5'b00000, 5'b00001, 5'b00100, 5'b01100, 5'b01000, 5'b10000, 5'b10100, 5'b11000, 5'b11100}) begin
                            id_mem_read  = 1'b1;
                            id_mem_write = 1'b1;
                            id_rd_we     = 1'b1;
                        end else begin
                            id_illegal = 1'b1;
                        end
                    end
                endcase
            end
            default: begin
                id_illegal = 1'b1;
            end
        endcase
    end

endmodule
