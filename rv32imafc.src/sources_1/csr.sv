module csr_reg (
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
    input  logic        meip_i,
    input  logic        msip_i,
    output logic [31:0] mtvec_val,
    output logic [31:0] mepc_val,
    output logic        irq_pending,
    output logic [31:0] mie_val,
    output logic [31:0] mip_val
);

    logic [31:0] mstatus, mie, mtvec, mepc, mcause, mtval, mip;
    logic [31:0] mcycle_lo, mcycle_hi, minstret_lo, minstret_hi;
    logic [31:0] mtime, mtimecmp;
    logic [31:0] mcountinhibit;

    wire mtip = (mtime >= mtimecmp && mtimecmp != 32'h0);
    wire [31:0] mip_next = {mip[31:12], meip_i, mip[10:8], mtip, mip[6:4], msip_i, mip[2:0]};

    wire global_irq = mstatus[3];  // MIE bit
    wire any_irq = global_irq && |(mie & mip_next);

    assign irq_pending = any_irq;

    assign rdata = csr_read(raddr);

    function automatic logic [31:0] csr_read(input logic [11:0] addr);
        unique case (addr)
            12'h300: return mstatus;
            12'h301: return 32'h40000100;  // misa: RV32I
            12'h304: return mie;
            12'h305: return mtvec;
            12'h320: return mcountinhibit;
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
            12'hF14: return 32'h0;          // mhartid
            default: return 32'h0;
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
        end else begin
            if (trap_trigger) begin
                mepc   <= trap_pc;
                mcause <= trap_cause;
                mtval  <= trap_tval;
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
                    default: ;
                endcase
            end
            mip <= mip_next;
        end
    end

    assign mtvec_val = mtvec;
    assign mepc_val  = mepc;
    assign mie_val   = mie;
    assign mip_val   = mip;

endmodule
