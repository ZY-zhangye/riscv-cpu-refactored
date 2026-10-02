`timescale 1ps / 1ps

module inst_ram_xpm #(
    parameter MEM_FILE = "program.mem"
) (
    input  logic        clk,
    input  logic        en,
    input  logic [31:0] addr,
    output logic [31:0] inst
);

    logic [31:0] mem [0:4095];
    string image_file;
    integer i;

    initial begin
        inst = 32'h0000_0013;
        for (i = 0; i < 4096; i = i + 1) begin
            mem[i] = 32'h0000_0013;
        end
        if (!$value$plusargs("IROM_HEX=%s", image_file)) begin
            $fatal(1, "missing +IROM_HEX=<one-word-per-line hex file>");
        end
        $readmemh(image_file, mem);
        $display("[SOC] IROM loaded from %s", image_file);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            // Preserve the board ROM's low-address aliasing, including mtvec.
            inst <= mem[addr[13:2]];
        end
    end

endmodule

module blk_mem_gen_0 (
    input  logic        clka,
    input  logic        ena,
    input  logic [3:0]  wea,
    input  logic [15:0] addra,
    input  logic [31:0] dina,
    output logic [31:0] douta
);

    logic [31:0] mem [0:65535];
    string image_file;
    integer i;

    initial begin
        douta = 32'd0;
        for (i = 0; i < 65536; i = i + 1) begin
            mem[i] = 32'd0;
        end
        if ($value$plusargs("DRAM_HEX=%s", image_file)) begin
            $readmemh(image_file, mem);
            $display("[SOC] DRAM initialized from %s; remaining words are zero", image_file);
        end else begin
            $display("[SOC] DRAM initialized to zero");
        end
    end

    always_ff @(posedge clka) begin
        if (ena) begin
            douta <= mem[addra];
            if (wea[0]) begin
                mem[addra][7:0] <= dina[7:0];
            end
            if (wea[1]) begin
                mem[addra][15:8] <= dina[15:8];
            end
            if (wea[2]) begin
                mem[addra][23:16] <= dina[23:16];
            end
            if (wea[3]) begin
                mem[addra][31:24] <= dina[31:24];
            end
        end
    end

endmodule
