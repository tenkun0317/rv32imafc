module unified_bram #(
    parameter RAM_SIZE   = 131072,
    parameter INIT_FILE  = ""
) (
    input  logic        clk,

    input  logic [31:0] addr_a,
    input  logic [3:0]  we_a,
    input  logic [31:0] din_a,
    output logic [31:0] dout_a,

    input  logic [31:0] addr_b,
    input  logic [3:0]  we_b,
    input  logic [31:0] din_b,
    output logic [31:0] dout_b
);

    localparam WORDS = RAM_SIZE / 4;

    (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

    initial begin
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = 32'h0;
        end
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    wire [15:0] waddr_a = addr_a[17:2];
    wire [15:0] waddr_b = addr_b[17:2];

    always_ff @(posedge clk) begin
        if (we_a[0]) mem[waddr_a][7:0]   <= din_a[7:0];
        if (we_a[1]) mem[waddr_a][15:8]  <= din_a[15:8];
        if (we_a[2]) mem[waddr_a][23:16] <= din_a[23:16];
        if (we_a[3]) mem[waddr_a][31:24] <= din_a[31:24];
        dout_a <= mem[waddr_a];
    end

    always_ff @(posedge clk) begin
        if (we_b[0]) mem[waddr_b][7:0]   <= din_b[7:0];
        if (we_b[1]) mem[waddr_b][15:8]  <= din_b[15:8];
        if (we_b[2]) mem[waddr_b][23:16] <= din_b[23:16];
        if (we_b[3]) mem[waddr_b][31:24] <= din_b[31:24];
        dout_b <= mem[waddr_b];
    end

endmodule