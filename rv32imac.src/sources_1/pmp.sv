module pmp_check #(
    parameter NUM_PMP_ENTRIES = 16,
    parameter PMP_GRANULARITY = 0  // G value: 0 = 4-byte, 1 = 8-byte, etc.
) (
    input  logic [1:0]  priv_lvl,
    input  logic [31:0] addr,
    input  logic        is_write,   // 1 = store/amo, 0 = load/fetch
    input  logic        is_exec,    // 1 = instruction fetch

    input  logic [31:0] pmpcfg   [0:3],
    input  logic [31:0] pmpaddr  [0:(NUM_PMP_ENTRIES-1)],

    output logic        pmp_fault
);

    // pmpcfg layout: 4 entries per 32-bit register
    // byte 0 = entry 0 (bits [7:0]), byte 1 = entry 1 (bits [15:8]), etc.
    // Each 8-bit entry: {L(bit7), [6:5]=reserved, A(bit[4:3]), X(bit2), W(bit1), R(bit0)}
    // A: 00=OFF, 01=TOR, 10=NA4, 11=NAPOT

    localparam PMP_SHIFT = PMP_GRANULARITY + 2;

    logic matched;
    logic perm_ok;
    logic entry_locked;

    function automatic logic [7:0] get_cfg(input int ei);
        int ci = ei[4:2];         // pmpcfg register index (0..3)
        int bi = ei[1:0];         // byte within register (0..3)
        return pmpcfg[ci][bi*8 +: 8];
    endfunction

    function automatic logic [33:0] pmp_addr_decode(input int ei);
        logic [31:0] raw = pmpaddr[ei];
        logic [33:0] result;
        if ((get_cfg(ei)[4:3] == 2'b10)) begin   // NA4
            result = {raw[33:PMP_SHIFT], {(PMP_SHIFT){1'b0}}};
        end else begin
            result = {2'b0, raw} << PMP_SHIFT;
        end
        return result;
    endfunction

    always_comb begin
        matched      = 1'b0;
        perm_ok      = 1'b1;
        entry_locked = 1'b0;
        pmp_fault    = 1'b0;

        for (int i = 0; i < NUM_PMP_ENTRIES; i++) begin
            automatic logic [7:0]   cfg        = get_cfg(i);
            automatic logic [1:0]   A          = cfg[4:3];
            automatic logic         L          = cfg[7];
            automatic logic         R          = cfg[0];
            automatic logic         W          = cfg[1];
            automatic logic         X          = cfg[2];
            automatic logic [33:0]  entry_addr = pmp_addr_decode(i);
            automatic logic [33:0]  prev_addr;
            automatic logic [33:0]  addr34     = {2'b0, addr};
            automatic logic         in_region;

            in_region = 1'b0;

            if (A == 2'b01) begin  // TOR
                if (i == 0)
                    prev_addr = 34'h0;
                else
                    prev_addr = pmp_addr_decode(i - 1);
                in_region = (addr34 >= prev_addr) && (addr34 < entry_addr);
            end else if (A == 2'b10) begin  // NA4
                in_region = (addr34[33:PMP_SHIFT] == entry_addr[33:PMP_SHIFT]);
            end else if (A == 2'b11) begin  // NAPOT
                logic [7:0] napot_raw = pmpaddr[i][7:0];
                logic [3:0] pos;
                logic       any_one = 1'b0;
                for (int b = 0; b < 8; b++) begin
                    if (napot_raw[b]) begin
                        pos = b[3:0];
                        any_one = 1'b1;
                    end
                end
                if (any_one) begin
                    automatic logic [33:0] size = 34'h1 << (pos + 3);
                    automatic logic [33:0] mask = size - 1'h1;
                    automatic logic [33:0] base = entry_addr & ~mask;
                    automatic logic [33:0] top  = base + size;
                    in_region = (addr34 >= base) && (addr34 < top);
                end
            end

            if (in_region && A != 2'b00 && !matched) begin
                matched      = 1'b1;
                entry_locked = L;
                // Check permission
                if (is_exec && !X) perm_ok = 1'b0;
                if (!is_exec && !is_write && !R) perm_ok = 1'b0;
                if (!is_exec && is_write && !W) perm_ok = 1'b0;
            end
        end

        if (priv_lvl == 2'b11) begin
            // M-mode: bypass PMP entries unless locked
            if (matched && entry_locked && !perm_ok)
                pmp_fault = 1'b1;
        end else begin
            // U-mode: enforce all matching. If no match, deny.
            if (!matched || !perm_ok)
                pmp_fault = 1'b1;
        end
    end

endmodule