module reg_file (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

    logic [31:0] rf [0:31];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                rf[i] <= 32'h0;
            end
        end else begin
            if (rd_we && rd_addr != 5'd0) begin
                rf[rd_addr] <= rd_data;
            end
        end
    end

    assign rs1_data = (rs1_addr == 5'd0) ? 32'h0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'h0 : rf[rs2_addr];

endmodule
