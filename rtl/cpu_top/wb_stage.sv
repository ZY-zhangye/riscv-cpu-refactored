`include "defines.svh"
module wb_stage (
    input logic clk,
    input logic rst_n,
    //来自内存阶段的信息
    input logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus0,
    input logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus1,
    //握手信号
    input logic ms_to_ws_valid0,
    input logic ms_to_ws_valid1,
    output logic ws_allowin0,
    output logic ws_allowin1,
    //送到寄存器堆的信息
    output logic regfile_wen,
    output logic regfile_wen1,
    output logic reg_fpu_wen,
    output logic reg_fpu_wen1,
    output logic [4:0] regfile_addr,
    output logic [4:0] regfile_addr1,
    output logic [31:0] regfile_wdata,
    output logic [31:0] regfile_wdata1
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

    logic ws_ready_go0, ws_ready_go1;
    logic ws_valid0, ws_valid1;
    assign ws_ready_go0 = 1'b1;
    assign ws_ready_go1 = 1'b1;

    assign ws_allowin0 = !ws_valid0 || ws_ready_go0 && ms_to_ws_valid0;
    assign ws_allowin1 = !ws_valid1 || ws_ready_go1 && ms_to_ws_valid1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_valid0 <= 1'b0;
            ws_valid1 <= 1'b0;
        end else begin
            if (ws_allowin0) ws_valid0 <= ms_to_ws_valid0;
            if (ws_allowin1) ws_valid1 <= ms_to_ws_valid1;
        end
    end

    logic [`MS_WS_WIDTH-1:0] ms_ws_bus_r0, ms_ws_bus_r1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_ws_bus_r0 <= '0;
            ms_ws_bus_r1 <= '0;
        end else begin
            if (ms_to_ws_valid0 && ws_allowin0) begin
                ms_ws_bus_r0 <= ms_to_ws_bus0;
            end
            if (ms_to_ws_valid1 && ws_allowin1) begin
                ms_ws_bus_r1 <= ms_to_ws_bus1;
            end
        end
    end

    //解析来自内存阶段的信息
    logic [31:0] wb_result0, wb_result1;
    logic [4:0] wb_dst_addr0, wb_dst_addr1;
    logic [31:0] wb_pc0, wb_pc1;
    logic wb_regfile_wen0, wb_regfile_wen1;
    logic wb_fpu_regfile_wen0, wb_fpu_regfile_wen1;

    assign {wb_pc0, wb_result0, wb_dst_addr0, wb_regfile_wen0, wb_fpu_regfile_wen0} = ms_ws_bus_r0;
    assign {wb_pc1, wb_result1, wb_dst_addr1, wb_regfile_wen1, wb_fpu_regfile_wen1} = ms_ws_bus_r1;

    assign regfile_wen = wb_regfile_wen0 && ws_valid0;
    assign reg_fpu_wen = wb_fpu_regfile_wen0 && ws_valid0;
    assign regfile_addr = wb_dst_addr0;
    assign regfile_wdata = wb_result0;

    assign regfile_wen1 = wb_regfile_wen1 && ws_valid1;
    assign reg_fpu_wen1 = wb_fpu_regfile_wen1 && ws_valid1;
    assign regfile_addr1 = wb_dst_addr1;
    assign regfile_wdata1 = wb_result1;

    `ifdef DEBUG_EN
    assign debug_wb_pc = wb_pc0;
    assign debug_wb_rf_addr = wb_dst_addr0;
    assign debug_wb_rf_data = wb_result0;
    assign debug_wb_rf_wen = wb_regfile_wen0 && ws_valid0;
    assign debug_wb_fpu_rf_wen = wb_fpu_regfile_wen0 && ws_valid0;
    `endif

endmodule
