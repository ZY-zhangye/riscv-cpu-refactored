`include "defines.svh"
module id_exe_stage (
    input logic clk,
    input logic rst_n,
    //与if_stage的数据接口
    input logic fs_to_ds_valid,
    output logic ds_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    //reggiles接口
    output logic [4:0] rs1_addr,
    output logic [4:0] rs2_addr,
    input logic [`DATA_WIDTH-1:0] rs1_data,
    input logic [`DATA_WIDTH-1:0] rs2_data,
    //regfile_fpu接口
    output logic [4:0] rs1_fpu_addr,
    output logic [4:0] rs2_fpu_addr,
    output logic [4:0] rs3_fpu_addr,
    output logic rs3_fpu_ren,
    input logic [`DATA_WIDTH-1:0] rs1_fpu_data,
    input logic [`DATA_WIDTH-1:0] rs2_fpu_data,
    //csr接口
    output logic [11:0] csr_addr,
    input logic [`DATA_WIDTH-1:0] csr_data,
    //数据前递接口--访存阶段--打包
    input logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus,
    //冲刷与异常信号（来自issue_stage）
    input logic is_flush,
    input logic exception_flag,
    input logic [`EXC_WIDTH-1:0] fs_exc_bus,
    //与MEM阶段的握手信号
    input logic ms_allowin,
    output logic es_to_ms_valid,
    output logic es_flush,
    output logic [`ES_MS_WIDTH-1:0] es_to_ms_bus,
    //DMEM接口
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    //mem阶段数据前递接口（数据）
    input logic [31:0] mem_result,
    //reg_fpu数据3接口
    input logic [31:0] reg_fpu_data3,
    //异常接口（输出）
    output logic [`EXE_EXC_BUS - 1:0] exe_exc_bus,
    //跳转接口（输出）
    output logic br_taken,
    output logic [31:0] br_target,
    output logic br_redirect,
    output logic [31:0] br_redirect_target,
    output logic bp_update_valid,
    output logic [31:0] bp_update_pc,
    output logic bp_update_taken,
    output logic [31:0] bp_update_target,
    output logic bp_update_is_jalr
);

    //内部连线：ID → EX
    logic ds_to_es_valid;
    logic es_allowin;
    logic ds_flush;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus;
    logic [`EXC_WIDTH-1:0] ds_exc_bus;

    //内部连线：EX → ID （前递）
    logic [`EX_FWD_PACKET_WIDTH-1:0] exe_fwd_bus;

    //内部连线：EX br_redirect → 输出端口
    logic int_br_redirect;

    id_stage u_id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .ds_allowin(ds_allowin),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .rs1_fpu_addr(rs1_fpu_addr),
        .rs2_fpu_addr(rs2_fpu_addr),
        .rs3_fpu_addr(rs3_fpu_addr),
        .rs3_fpu_ren(rs3_fpu_ren),
        .rs1_fpu_data(rs1_fpu_data),
        .rs2_fpu_data(rs2_fpu_data),
        .csr_addr(csr_addr),
        .csr_data(csr_data),
        .ds_to_es_valid(ds_to_es_valid),
        .es_allowin(es_allowin),
        .ds_flush(ds_flush),
        .ds_to_es_bus(ds_to_es_bus),
        .exe_fwd_bus(exe_fwd_bus),
        .mem_fwd_bus(mem_fwd_bus),
        .br_taken(int_br_redirect),
        .exception_flag(exception_flag),
        .is_flush(is_flush),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus)
    );

    exe_stage u_exe_stage (
        .clk(clk),
        .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid),
        .ms_allowin(ms_allowin),
        .ds_to_es_bus(ds_to_es_bus),
        .ds_flush(ds_flush),
        .es_allowin(es_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .exe_fwd_bus(exe_fwd_bus),
        .ds_exc_bus(ds_exc_bus),
        .exception_flag(exception_flag),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_redirect(int_br_redirect),
        .br_redirect_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .mem_result(mem_result),
        .reg_fpu_data3(reg_fpu_data3),
        .exe_exc_bus(exe_exc_bus)
    );

    //内部br_redirect连接到输出端口
    assign br_redirect = int_br_redirect;

endmodule
