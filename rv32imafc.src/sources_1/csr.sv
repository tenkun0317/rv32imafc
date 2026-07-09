module csr_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [11:0] raddr,
    output logic [31:0] rdata,
    input  logic        we,
    input  logic [11:0] waddr,
    input  logic [31:0] wdata,
    input  logic        trap_trigger,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_tval,
    output logic [31:0] mtvec_val,
    output logic [31:0] mepc_val
);

    logic [31:0] mstatus, mie, mtvec, mepc, mcause, mtval, mip;
    logic [31:0] mcycle, minstret, mtime;

    assign rdata = csr_read(raddr);

    function automatic logic [31:0] csr_read(input logic [11:0] addr);
        unique case (addr)
            12'h300: return mstatus;
            12'h301: return 32'h40000100;  // misa: RV32I
            12'h304: return mie;
            12'h305: return mtvec;
            12'h341: return mepc;
            12'h342: return mcause;
            12'h343: return mtval;
            12'h344: return mip;
            12'hB00: return mcycle;         // mcycle
            12'hB02: return minstret;       // minstret
            12'hC00: return mcycle;         // cycle (RO, alias of mcycle)
            12'hC01: return mtime;          // time (RO)
            12'hC02: return minstret;       // instret (RO, alias of minstret)
            12'hF14: return 32'h0;          // mhartid
            default: return 32'h0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 32'h0;
            mie      <= 32'h0;
            mtvec    <= 32'h0;
            mepc     <= 32'h0;
            mcause   <= 32'h0;
            mtval    <= 32'h0;
            mip      <= 32'h0;
            mcycle   <= 32'h0;
            minstret <= 32'h0;
            mtime    <= 32'h0;
        end else begin
            if (trap_trigger) begin
                mepc   <= trap_pc;
                mcause <= trap_cause;
                mtval  <= trap_tval;
            end else if (we) begin
                unique case (waddr)
                    12'h300: mstatus  <= wdata;
                    12'h304: mie      <= wdata;
                    12'h305: mtvec    <= wdata;
                    12'h341: mepc     <= wdata;
                    12'h342: mcause   <= wdata;
                    12'h343: mtval    <= wdata;
                    12'h344: mip      <= wdata;
                    12'hB00: mcycle   <= wdata;
                    12'hB02: minstret <= wdata;
                    12'hC01: mtime    <= wdata;
                    default: ;
                endcase
            end
        end
    end

    assign mtvec_val = mtvec;
    assign mepc_val  = mepc;

endmodule
