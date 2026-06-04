`include "defines.svh"
module issue_stage (
    input logic clk,
    input logic rst_n,
    //来自IF阶段的数据0
    input logic fs_to_is_valid,
    output logic is_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus,
    //送往ID阶段的数据0
    output logic is_to_ds_valid,
    input logic ds_allowin,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus,
    //来自IF阶段的数据1（预留）
    input logic fs_to_is_valid1,
    output logic is_allowin1,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1,
    //送往ID阶段的数据1（预留）
    output logic is_to_ds_valid1,
    input logic ds_allowin1,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1,
    //分支跳转与异常冲刷信号
    input logic br_taken,
    input logic exception_flag,
    output logic is_flush,
    output logic is_flush1
);

    //组合直通：lane0
    assign is_to_ds_valid = fs_to_is_valid;
    assign is_allowin = ds_allowin;
    assign is_to_ds_bus = fs_to_is_bus;

    //组合直通：lane1（预留）
    assign is_to_ds_valid1 = fs_to_is_valid1;
    assign is_allowin1 = ds_allowin1;
    assign is_to_ds_bus1 = fs_to_is_bus1;

    //冲刷信号：预留给双发射使用，当前置0
    assign is_flush = 1'b0;
    assign is_flush1 = 1'b0;

endmodule
