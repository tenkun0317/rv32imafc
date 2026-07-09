module instr_ram #(
    parameter RAM_SIZE   = 131072,
    parameter INIT_FILE  = ""
) (
    input  logic        clk,
    input  logic [31:0] addr,
    output logic [31:0] dout
);

    (* ram_style = "block" *) logic [31:0] mem [0:RAM_SIZE/4-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_comb begin
        dout = mem[addr[31:2]];
    end

endmodule