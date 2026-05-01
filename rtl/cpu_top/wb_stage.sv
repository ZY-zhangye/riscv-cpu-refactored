`include "defines.svh"
module wb_stage (
    input logic clk,
    input logic rst_n,
    //来自内存阶段的信息
    input logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus,
    //握手信号
    input logic ms_to_ws_valid,
    output logic ws_allowin,
    //送到寄存器堆的信息
    output logic regfile_wen,
    output logic reg_fpu_wen,
    output logic [4:0] regfile_addr,
    output logic [31:0] regfile_wdata
    //debug接口
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_wb_pc,
    output logic [4:0] debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic debug_wb_rf_wen,
    output logic debug_wb_fpu_rf_wen
    `endif
);

    logic ws_ready_go;
    logic ws_valid;
    assign ws_ready_go = 1'b1;
    assign ws_allowin = !ws_valid || ws_ready_go && ms_to_ws_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_valid <= 1'b0;
        end else if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end
    end

    logic [`MS_WS_WIDTH-1:0] ms_ws_bus_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_ws_bus_r <= '0;
        end else if (ms_to_ws_valid && ws_allowin) begin
            ms_ws_bus_r <= ms_to_ws_bus;
        end
    end

    //解析来自内存阶段的信息
    logic [31:0] wb_result;
    logic [4:0] wb_dst_addr;
    logic [31:0] wb_pc;
    logic wb_regfile_wen;
    logic wb_fpu_regfile_wen;
    assign {wb_pc, wb_result, wb_dst_addr, wb_regfile_wen, wb_fpu_regfile_wen} = ms_ws_bus_r;
    assign regfile_wen = wb_regfile_wen;
    assign reg_fpu_wen = wb_fpu_regfile_wen;
    assign regfile_addr = wb_dst_addr;
    assign regfile_wdata = wb_result;
    `ifdef DEBUG_EN
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_addr = wb_dst_addr;
    assign debug_wb_rf_data = wb_result;
    assign debug_wb_rf_wen = wb_regfile_wen;
    assign debug_wb_fpu_rf_wen = wb_fpu_regfile_wen;
    `endif

endmodule
