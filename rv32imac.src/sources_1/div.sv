module div (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [31:0] dividend,
    input  logic [31:0] divisor,
    input  logic        is_signed,
    output logic [31:0] quotient,
    output logic [31:0] remainder,
    output logic        busy
);

    typedef enum logic { IDLE = 1'b0, COMPUTE = 1'b1 } state_t;
    state_t state;

    logic [4:0]  cnt;
    logic [31:0] dividend_abs, divisor_abs;
    logic        neg_quot, neg_rem;

    logic [32:0] rem;  // 33-bit remainder (bit 32 = sign)
    logic [31:0] quot; // 32-bit quotient
    logic [31:0] d;    // divisor copy (absolute)

    assign dividend_abs = (is_signed && dividend[31]) ? -dividend : dividend;
    assign divisor_abs  = (is_signed && divisor[31])  ? -divisor  : divisor;
    assign neg_quot = is_signed && (dividend[31] ^ divisor[31]);
    assign neg_rem  = is_signed && dividend[31];

    logic divisor_zero;
    assign divisor_zero = (divisor == 32'h0);

    // Next-state combinational
    logic [32:0] rem_next;
    logic [31:0] quot_next;
    always_comb begin
        if (rem[32]) begin
            rem_next = {rem[30:0], quot[31]} + d;   // 2*rem + d (non-restoring "add")
        end else begin
            rem_next = {rem[30:0], quot[31]} - d;   // 2*rem - d (non-restoring "sub")
        end
        quot_next = {quot[30:0], ~rem_next[32]};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt   <= 5'd0;
            rem   <= 33'h0;
            quot  <= 32'h0;
            d     <= 32'h0;
        end else if (state == IDLE && start) begin
            state <= COMPUTE;
            cnt   <= 5'd1;
            rem   <= 33'h0;
            quot  <= dividend_abs;
            d     <= divisor_abs;
        end else if (state == COMPUTE) begin
            cnt   <= cnt + 5'd1;
            rem   <= rem_next;
            quot  <= quot_next;
            if (cnt == 5'd31) begin
                state <= IDLE;
                // Final iteration: shift quotient bit one more time
            end
        end
    end

    // Post-correction: restore remainder if negative, apply sign
    logic [31:0] raw_quot, raw_rem;
    always_comb begin
        if (divisor_zero) begin
            raw_quot = 32'hFFFFFFFF;
            raw_rem  = dividend;
        end else begin
            raw_quot = quot;
            raw_rem  = rem[32] ? (rem[31:0] + d) : rem[31:0];
            if (neg_quot) raw_quot = -raw_quot;
            if (neg_rem)  raw_rem  = -raw_rem;
        end
    end

    assign quotient  = raw_quot;
    assign remainder = raw_rem;
    assign busy      = (state == COMPUTE);

endmodule