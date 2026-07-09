module mem_stage #(
    parameter RAM_INIT_FILE = "",
    parameter RAM_SIZE = 262144
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] ex_rs2_data,
    input  logic [2:0]  ex_mem_type,
    input  logic        ex_mem_read,
    input  logic        ex_mem_write,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_rd_we,
    input  logic        ex_valid,
    input  logic        ex_ebreak,
    input  logic        ex_mem_flush,

    output logic [31:0] mem_pc,
    output logic [31:0] mem_alu_result,
    output logic [31:0] mem_mem_data,
    output logic [4:0]  mem_rd_addr,
    output logic        mem_rd_we,
    output logic        mem_mem_read,
    output logic        mem_valid,
    output logic        mem_ebreak,

    // IF instruction fetch via Port B
    input  logic [31:0] if_pc,
    output logic [31:0] if_instr_dout,

    input  logic [11:0] ex_csr_addr,
    input  logic [2:0]  ex_csr_op,
    input  logic [31:0] ex_csr_wdata,
    output logic [11:0] mem_csr_addr,
    output logic        mem_csr_we,
    output logic [31:0] mem_csr_wdata
);

    logic [31:0] ram_dout;
    logic [3:0]  ram_we;
    logic [31:0] ram_din;
    logic [2:0]  mem_mem_type_q;

    logic [11:0] mem_csr_addr_q;
    logic        mem_csr_we_q;
    logic [31:0] mem_csr_wdata_q;

    // Byte/halfword store: generate byte enables and replicate data
    always_comb begin
        ram_we  = 4'b0;
        ram_din = ex_rs2_data;
        case (ex_mem_type)
            3'b000: begin // sb
                ram_we = 4'b0001 << ex_alu_result[1:0];
                ram_din = {4{ex_rs2_data[7:0]}};
            end
            3'b001: begin // sh
                ram_we = {2'b0, 2'b11} << {ex_alu_result[1], 1'b0};
                ram_din = {2{ex_rs2_data[15:0]}};
            end
            3'b010: begin // sw
                ram_we = 4'b1111;
                ram_din = ex_rs2_data;
            end
            default: begin
                ram_we = 4'b1111;
                ram_din = ex_rs2_data;
            end
        endcase
        if (!ex_mem_write) ram_we = 4'b0;
    end

    unified_bram #(
        .RAM_SIZE   (RAM_SIZE),
        .INIT_FILE  (RAM_INIT_FILE)
    ) u_ram (
        .clk   (clk),
        .addr_a(ex_alu_result),
        .we_a  (ram_we),
        .din_a (ram_din),
        .dout_a(ram_dout),

        .addr_b(if_pc),
        .we_b  (4'b0),
        .din_b (32'h0),
        .dout_b(if_instr_dout)
    );

    // Load data mux: use MEM-registered mem_type and address (not EX stage's,
    // which has already advanced to the next instruction)
    always_comb begin
        case (mem_mem_type_q)
            3'b000: begin // lb
                unique case (mem_alu_result[1:0])
                    2'b00: mem_mem_data = {{24{ram_dout[7]}},  ram_dout[7:0]};
                    2'b01: mem_mem_data = {{24{ram_dout[15]}}, ram_dout[15:8]};
                    2'b10: mem_mem_data = {{24{ram_dout[23]}}, ram_dout[23:16]};
                    2'b11: mem_mem_data = {{24{ram_dout[31]}}, ram_dout[31:24]};
                endcase
            end
            3'b001: begin // lh
                unique case (mem_alu_result[1])
                    1'b0: mem_mem_data = {{16{ram_dout[15]}}, ram_dout[15:0]};
                    1'b1: mem_mem_data = {{16{ram_dout[31]}}, ram_dout[31:16]};
                endcase
            end
            3'b010: mem_mem_data = ram_dout; // lw
            3'b100: begin // lbu
                unique case (mem_alu_result[1:0])
                    2'b00: mem_mem_data = {24'h0, ram_dout[7:0]};
                    2'b01: mem_mem_data = {24'h0, ram_dout[15:8]};
                    2'b10: mem_mem_data = {24'h0, ram_dout[23:16]};
                    2'b11: mem_mem_data = {24'h0, ram_dout[31:24]};
                endcase
            end
            3'b101: begin // lhu
                unique case (mem_alu_result[1])
                    1'b0: mem_mem_data = {16'h0, ram_dout[15:0]};
                    1'b1: mem_mem_data = {16'h0, ram_dout[31:16]};
                endcase
            end
            default: mem_mem_data = ram_dout;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_pc        <= 32'h0;
            mem_alu_result<= 32'h0;
            mem_rd_addr   <= 5'h0;
            mem_rd_we     <= 1'b0;
            mem_mem_read  <= 1'b0;
            mem_valid     <= 1'b0;
            mem_ebreak    <= 1'b0;
            mem_mem_type_q<= 3'h0;
            mem_csr_addr_q<= 12'h0;
            mem_csr_we_q  <= 1'b0;
            mem_csr_wdata_q<= 32'h0;
        end else if (ex_mem_flush) begin
            mem_pc        <= 32'h0;
            mem_alu_result<= 32'h0;
            mem_rd_addr   <= 5'h0;
            mem_rd_we     <= 1'b0;
            mem_mem_read  <= 1'b0;
            mem_valid     <= 1'b0;
            mem_ebreak    <= 1'b0;
            mem_mem_type_q<= 3'h0;
            mem_csr_addr_q<= 12'h0;
            mem_csr_we_q  <= 1'b0;
            mem_csr_wdata_q<= 32'h0;
        end else begin
            mem_pc        <= ex_pc;
            mem_alu_result<= ex_alu_result;
            mem_rd_addr   <= ex_rd_addr;
            mem_rd_we     <= ex_rd_we;
            mem_mem_read  <= ex_mem_read;
            mem_valid     <= ex_valid;
            mem_ebreak    <= ex_ebreak;
            mem_mem_type_q<= ex_mem_type;
            mem_csr_addr_q<= ex_csr_addr;
            mem_csr_we_q  <= (ex_csr_op != 3'h0);
            mem_csr_wdata_q<= ex_csr_wdata;
        end
    end

    assign mem_csr_addr = mem_csr_addr_q;
    assign mem_csr_we   = mem_csr_we_q;
    assign mem_csr_wdata = mem_csr_wdata_q;

endmodule