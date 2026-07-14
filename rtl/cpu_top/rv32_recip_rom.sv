// Standalone synchronous reciprocal ROM.  Keeping the memory and its read
// register in a separate module makes Vivado infer RAMB36E1 instead of a
// large distributed-ROM mux tree.
module rv32_recip_rom #(
    parameter integer ADDR_WIDTH = 16,
    parameter integer DATA_WIDTH = 40,
    parameter string MEM_FILE = "rtl/cpu_top/rv32_recip_lut_f40.mem"
) (
    input  logic                    clk,
    input  logic                    en,
    input  logic [ADDR_WIDTH-1:0]   addr,
    output logic [DATA_WIDTH-1:0]   data
);
    localparam integer DEPTH = (1 << ADDR_WIDTH);
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial $readmemh(MEM_FILE, mem);

    always_ff @(posedge clk) begin
        if (en)
            data <= mem[addr];
    end
endmodule
