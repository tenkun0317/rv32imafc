module mul (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic        is_signed_a,
    input  logic        is_signed_b,
    input  logic        sel_hi,
    output logic [31:0] result,
    output logic        busy
);

    typedef enum logic [1:0] { IDLE = 2'b00, COMPUTE = 2'b01, DONE = 2'b10 } state_t;
    state_t state;

    logic [31:0] a_abs, b_abs;
    logic        neg_result;
    logic [63:0] product_full;

    assign a_abs = is_signed_a && a[31] ? -a : a;
    assign b_abs = is_signed_b && b[31] ? -b : b;
    assign neg_result = (is_signed_a && a[31]) ^ (is_signed_b && b[31]);

    logic start_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_prev <= 0;
        else
            start_prev <= start;
    end

    wire start_edge = start && !start_prev;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            product_full <= 64'h0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_edge) begin
                        state <= COMPUTE;
                    end
                end
                COMPUTE: begin
                    state <= DONE;
                end
                DONE: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    logic [31:0] a_r, b_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r <= 0;
            b_r <= 0;
        end else if (start_edge) begin
            a_r <= a_abs;
            b_r <= b_abs;
        end
    end

    (* use_dsp = "yes" *)
    logic [63:0] mul_result;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mul_result <= 0;
        else if (state == COMPUTE)
            mul_result <= a_r * b_r;
    end

    logic [63:0] product_corrected;
    always_comb begin
        product_corrected = neg_result ? -mul_result : mul_result;
    end

    assign result = sel_hi ? product_corrected[63:32] : product_corrected[31:0];
    assign busy   = (state != IDLE);

endmodule
