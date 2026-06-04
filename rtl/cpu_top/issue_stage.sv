`include "defines.svh"
module issue_stage (
    input logic clk,
    input logic rst_n,
    //来自IF阶段的数据0
    input logic fs_to_is_valid,
    output logic is_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1,
    //送往ID阶段的数据0
    output logic is_to_ds_valid,
    input logic ds_allowin,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus,
    //送往ID阶段的数据1
    output logic is_to_ds_valid1,
    input logic ds_allowin1,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1,
    //分支跳转与异常冲刷信号
    input logic br_taken,
    input logic exception_flag,
    output logic is_flush,
    output logic is_flush1
);


endmodule
