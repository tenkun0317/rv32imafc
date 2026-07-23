module csr_reg #(
    parameter NUM_PMP_ENTRIES = 16,
    parameter PMP_GRANULARITY = 0  // G value; min 4-byte when G=0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [11:0] raddr,
    output logic [31:0] rdata,
    input  logic        we,
    input  logic [11:0] waddr,
    input  logic [31:0] wdata,
    input  logic        instr_ret,
    input  logic        trap_trigger,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_tval,
    input  logic        mret_taken,
    input  logic        meip_i,
    input  logic        msip_i,
    output logic [31:0] mtvec_val,
    output logic [31:0] mepc_val,
    output logic        irq_pending,
    output logic [31:0] mie_val,
    output logic [31:0] mip_val,
    output logic [31:0] jvt_val,
    output logic        csr_illegal,
    output logic [1:0]  priv_lvl,
    output logic [31:0] pmpcfg_o   [0:3],
    output logic [31:0] pmpaddr_o  [0:(NUM_PMP_ENTRIES-1)]
);

    logic [31:0] mstatus, mie, mtvec, mepc, mcause, mtval, mip;
    logic [31:0] mcycle_lo, mcycle_hi, minstret_lo, minstret_hi;
    logic [31:0] mtime, mtimecmp;
    logic [31:0] mcountinhibit;
    logic [31:0] jvt;
    logic [31:0] mscratch;
    logic [31:0] pmpcfg   [0:3];  // 4 cfg registers for up to 16 entries
    logic [31:0] pmpaddr  [0:(NUM_PMP_ENTRIES-1)];

    wire mtip = (mtime >= mtimecmp && mtimecmp != 32'h0);
    wire [31:0] mip_next = {mip[31:12], meip_i, mip[10:8], mtip, mip[6:4], msip_i, mip[2:0]};

    wire global_irq = mstatus[3] && (priv_lvl == 2'b11);  // MIE bit, only in M-mode
    wire any_irq = global_irq && |(mie & mip_next);

    assign irq_pending = any_irq;

    assign rdata = csr_read(raddr);

    function automatic logic [31:0] csr_read(input logic [11:0] addr);
        unique case (addr)
            12'h300: return mstatus;
            12'h301: return 32'h40001105;  // misa: RV32I + M + A + C
            12'h304: return mie;
            12'h305: return mtvec;
            12'h320: return mcountinhibit;
            12'h340: return mscratch;
            12'h341: return mepc;
            12'h342: return mcause;
            12'h343: return mtval;
            12'h344: return mip;
            12'hB00: return mcycle_lo;      // mcycle
            12'hB02: return minstret_lo;    // minstret
            12'hB80: return mcycle_hi;      // mcycleh
            12'hB82: return minstret_hi;    // minstreth
            12'hC00: return mcycle_lo;      // cycle (RO, alias of mcycle_lo)
            12'hC01: return mtime;          // time (RO)
            12'hC02: return minstret_lo;    // instret (RO, alias of minstret_lo)
            12'hC80: return mcycle_hi;      // cycleh
            12'hC82: return minstret_hi;    // instreth
            12'hC60: return mtimecmp;       // mtimecmp
            12'hF11: return 32'h0;          // mvendorid
            12'hF12: return 32'h0;          // marchid
            12'hF13: return 32'h0;          // mimpid
            12'hF14: return 32'h0;          // mhartid
            12'h017: return jvt;            // Zcmt jump vector table
            12'h3A0: return pmpcfg[0];
            12'h3A1: return pmpcfg[1];
            12'h3A2: return pmpcfg[2];
            12'h3A3: return pmpcfg[3];
            default: begin
                if (addr >= 12'h3B0 && addr < 12'h3B0 + NUM_PMP_ENTRIES)
                    return pmpaddr[addr[3:0]];  // addr[3:0] maps 0x3B0..3BF to index 0..15
                return 32'h0;
            end
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus       <= 32'h0;
            mie           <= 32'h0;
            mtvec         <= 32'h80000000;
            mepc          <= 32'h0;
            mcause        <= 32'h0;
            mtval         <= 32'h0;
            mip           <= 32'h0;
            mcycle_lo     <= 32'h0;
            mcycle_hi     <= 32'h0;
            minstret_lo   <= 32'h0;
            minstret_hi   <= 32'h0;
            mtime         <= 32'h0;
            mtimecmp      <= 32'h0;
            mcountinhibit <= 32'h0;
            jvt           <= 32'h80000000;
            mscratch      <= 32'h0;
            priv_lvl      <= 2'b11;
            for (int i = 0; i < 4; i++) pmpcfg[i] <= 32'h0;
            for (int i = 0; i < NUM_PMP_ENTRIES; i++) pmpaddr[i] <= 32'h0;
        end else begin
            if (trap_trigger) begin
                mepc   <= trap_pc;
                mcause <= trap_cause;
                mtval  <= trap_tval;
                mstatus[12:11] <= priv_lvl;
                mstatus[7]     <= mstatus[3];
                mstatus[3]     <= 1'b0;
                priv_lvl       <= 2'b11;
            end
            if (mret_taken) begin
                priv_lvl       <= mstatus[12:11];
                mstatus[3]     <= mstatus[7];
                mstatus[7]     <= 1'b1;
                mstatus[12:11] <= 2'b00;
            end
            // Counters
            if (!mcountinhibit[0]) begin
                mcycle_lo <= mcycle_lo + 32'd1;
                if (mcycle_lo == 32'hFFFFFFFF)
                    mcycle_hi <= mcycle_hi + 32'd1;
            end
            if (instr_ret && !mcountinhibit[2]) begin
                minstret_lo <= minstret_lo + 32'd1;
                if (minstret_lo == 32'hFFFFFFFF)
                    minstret_hi <= minstret_hi + 32'd1;
            end
if (we) begin
                unique case (waddr)
                    12'h300: mstatus       <= wdata;
                    12'h304: mie           <= wdata;
                    12'h305: mtvec         <= wdata;
                    12'h320: mcountinhibit <= wdata;
                    12'h340: mscratch      <= wdata;
                    12'h341: mepc          <= wdata;
                    12'h342: mcause        <= wdata;
                    12'h343: mtval         <= wdata;
                    12'h344: mip           <= wdata;
                    12'hB00: mcycle_lo     <= wdata;
                    12'hB02: minstret_lo   <= wdata;
                    12'hB80: mcycle_hi     <= wdata;
                    12'hB82: minstret_hi   <= wdata;
                    12'hC01: mtime         <= wdata;
                    12'hC60: mtimecmp      <= wdata;
                    12'h017: jvt           <= wdata & 32'hFFFFFFC0;
                    12'h3A0, 12'h3A1, 12'h3A2, 12'h3A3: begin
                        automatic int ci = waddr[1:0]; // 0..3
                        automatic logic [31:0] mask = 32'h0;
                        for (int e = 0; e < 4; e++) begin
                            if (!pmpcfg[ci][7 + e*8])
                                mask[7 + e*8 +: 8] = 8'hFF;
                        end
                        pmpcfg[ci] <= (pmpcfg[ci] & ~mask) | (wdata & mask);
                    end
                    default: begin
                        if (waddr >= 12'h3B0 && waddr < 12'h3B0 + NUM_PMP_ENTRIES) begin
                            automatic int pi = waddr[3:0]; // entry index 0..15
                            automatic int cfg_idx = pi[4:2]; // which pmpcfg register
                            automatic int cfg_byte = pi[1:0]; // which byte within cfg
                            if (!pmpcfg[cfg_idx][7 + cfg_byte*8])
                                pmpaddr[pi] <= wdata;
                        end
                    end
                endcase
            end
            mip <= mip_next;
        end
    end

    wire csr_addr_legal = (waddr inside {
        12'h300, 12'h304, 12'h305, 12'h320, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
        12'hB00, 12'hB02, 12'hB80, 12'hB82,
        12'hC01, 12'hC60,
        12'h017,
        12'h3A0, 12'h3A1, 12'h3A2, 12'h3A3
    }) || (waddr >= 12'h3B0 && waddr < 12'h3B0 + NUM_PMP_ENTRIES);
    wire csr_priv_ok = (priv_lvl == 2'b11) || (waddr[9:8] != 2'b11);
    assign csr_illegal = we && !(csr_addr_legal && csr_priv_ok);

    assign mtvec_val = mtvec;
    assign mepc_val  = mepc;
    assign mie_val   = mie;
    assign mip_val   = mip;
    assign jvt_val   = jvt;
    for (genvar g = 0; g < 4; g++) assign pmpcfg_o[g] = pmpcfg[g];
    for (genvar g = 0; g < NUM_PMP_ENTRIES; g++) assign pmpaddr_o[g] = pmpaddr[g];

endmodule
