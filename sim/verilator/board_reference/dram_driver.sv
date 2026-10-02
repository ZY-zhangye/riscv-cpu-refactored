`timescale 1ns / 1ps

module dram_driver(
    input  logic        clk,
    input  logic [17:0] perip_addr,
    input  logic [31:0] perip_wdata,
    input  logic [3:0]  perip_mask,
    input  logic        dram_wen,
    input  logic        perip_ren,
    output logic [31:0] perip_rdata
);

    logic [3:0] dram_we;

    // BRAM保持使能，消除CPU请求到ENARDEN的跨层级长路径。
    // 写掩码必须显式受dram_wen门控，避免MMIO写访问误写DRAM。
    assign dram_we = perip_mask & {4{dram_wen}};

    blk_mem_gen_0 u_dram (
        .clka(clk),
        .ena(1'b1),
        .wea(dram_we),
        .addra(perip_addr[17:2]),
        .dina(perip_wdata),
        .douta(perip_rdata)
    );

    // perip_ren由上层保留用于固定一周期读协议；BRAM端口持续预读当前地址。
    logic unused_perip_ren;
    assign unused_perip_ren = perip_ren;

endmodule
