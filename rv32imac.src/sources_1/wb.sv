module wb_stage (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] mem_mem_data,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_rd_we,
    input  logic        ex_mem_read,
    input  logic        ex_valid,
    input  logic        ex_ebreak,

    output logic [4:0]  wb_rd_addr,
    output logic [31:0] wb_rd_data,
    output logic        wb_rd_we,
    output logic        wb_valid,
    output logic        wb_ebreak
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_rd_addr  <= 5'h0;
            wb_rd_data  <= 32'h0;
            wb_rd_we    <= 1'b0;
            wb_valid    <= 1'b0;
            wb_ebreak   <= 1'b0;
        end else begin
            wb_rd_addr  <= ex_rd_addr;
            wb_rd_we    <= ex_rd_we & ex_valid;
            wb_valid    <= ex_valid;
            wb_ebreak   <= ex_ebreak;

            if (ex_mem_read) begin
                wb_rd_data <= mem_mem_data;
            end else begin
                wb_rd_data <= ex_alu_result;
            end
        end
    end

endmodule