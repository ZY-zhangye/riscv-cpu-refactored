`timescale 1ps / 1ps

module my_cpu (
    input  logic        clk,
    input  logic        clk_cnt,
    input  logic        rst_n,
    output logic [31:0] led,
    input  logic [7:0]  key,
    input  logic [63:0] sw,
    output logic [39:0] seg,
    output logic [31:0] seg_value
);

    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        imem_en;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    logic [3:0]  dmem_wen;
    logic        dmem_en;

`ifdef DEBUG_EN
    logic [31:0] debug_wb_pc;
    logic [4:0]  debug_wb_rf_addr;
    logic [31:0] debug_wb_rf_data;
    logic        debug_wb_rf_wen;
    logic        debug_wb_fpu_rf_wen;
    logic [31:0] debug_data;
`endif

    cpu_top u_cpu_top (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .plic_irq(1'b0)
`ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_data(debug_data)
`endif
    );

    inst_ram_xpm u_irom (
        .clk(clk),
        .en(imem_en),
        .addr(imem_addr),
        .inst(imem_rdata)
    );

    perip_bridge u_perip_bridge (
        .clk(clk),
        .cnt_clk(clk_cnt),
        .rst(~rst_n),
        .perip_addr(dmem_addr),
        .perip_wdata(dmem_wdata),
        .perip_wen(|dmem_wen),
        .perip_ren(dmem_en),
        .perip_mask(dmem_wen),
        .perip_rdata(dmem_rdata),
        .virtual_sw_input(sw),
        .virtual_key_input(key),
        .virtual_seg_output(seg),
        .virtual_led_output(led),
        .virtual_seg_value(seg_value)
    );

endmodule
