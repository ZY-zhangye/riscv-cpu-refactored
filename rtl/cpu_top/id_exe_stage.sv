`include "defines.svh"
module id_exe_stage (
    input logic clk,
    input logic rst_n,
    //与issue_stage的数据接口0
    input logic fs_to_ds_valid,
    output logic ds_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    //与issue_stage的数据接口1
    input logic fs_to_ds_valid1,
    output logic ds_allowin1,
    input logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus1,
    //reggiles接口0
    output logic [4:0] rs1_addr,
    output logic [4:0] rs2_addr,
    input logic [`DATA_WIDTH-1:0] rs1_data,
    input logic [`DATA_WIDTH-1:0] rs2_data,
    //reggiles接口1
    output logic [4:0] rs1_addr1,
    output logic [4:0] rs2_addr1,
    input logic [`DATA_WIDTH-1:0] rs1_data1,
    input logic [`DATA_WIDTH-1:0] rs2_data1,
    //regfile_fpu接口（lane0为主，lane1共享）
    output logic [4:0] rs1_fpu_addr,
    output logic [4:0] rs2_fpu_addr,
    output logic [4:0] rs3_fpu_addr,
    output logic rs3_fpu_ren,
    input logic [`DATA_WIDTH-1:0] rs1_fpu_data,
    input logic [`DATA_WIDTH-1:0] rs2_fpu_data,
    //csr接口（lane0为主，lane1共享）
    output logic [11:0] csr_addr,
    input logic [`DATA_WIDTH-1:0] csr_data,
    //数据前递接口--访存阶段--打包
    input logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus0,
    input logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus1,
    //冲刷与异常信号（来自issue_stage）
    input logic is_flush,
    input logic is_flush1,
    input logic exception_flag,
    input logic [`EXC_WIDTH-1:0] fs_exc_bus,
    //与MEM阶段的握手信号
    input logic ms_allowin0,
    input logic ms_allowin1,
    output logic es_to_ms_valid0,
    output logic es_flush0,
    output logic [`ES_MS_WIDTH-1:0] es_to_ms_bus0,
    output logic es_to_ms_valid1,
    output logic es_flush1,
    output logic [`ES_MS_WIDTH-1:0] es_to_ms_bus1,
    //DMEM接口（二选一仲裁）
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    //mem阶段数据前递接口（数据）
    input logic [31:0] mem_result0,
    input logic [31:0] mem_result1,
    //reg_fpu数据3接口（共享）
    input logic [31:0] reg_fpu_data3,
    //异常接口（输出，二选一仲裁）
    output logic [`EXE_EXC_BUS - 1:0] exe_exc_bus,
    //跳转接口（输出，二选一仲裁）
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

    //===========================================================================
    // Lane0: 全功能流水线
    //===========================================================================
    logic        ds_to_es_valid0;
    logic        es_allowin0;
    logic        ds_flush0;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus0;
    logic [`EXC_WIDTH-1:0] ds_exc_bus0;
    logic [`EX_FWD_PACKET_WIDTH-1:0] exe_fwd_bus0;
    logic [`EX_FWD_PACKET_WIDTH-1:0] exe_fwd_bus1;

    logic        br_redirect0, br_taken0;
    logic [31:0] br_target0, br_redirect_target0;
    logic        bp_update_valid0;
    logic [31:0] bp_update_pc0, bp_update_target0;
    logic        bp_update_taken0, bp_update_is_jalr0;

    logic [31:0] dmem_addr0, dmem_wdata0;
    logic [3:0]  dmem_wen0;
    logic        dmem_en0;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus0;

    logic [31:0] exe_result_current0;
    logic [31:0] exe_result_current1;

    id_stage u_id0 (
        .clk(clk), .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .ds_allowin(ds_allowin),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rs1_fpu_addr(rs1_fpu_addr), .rs2_fpu_addr(rs2_fpu_addr),
        .rs3_fpu_addr(rs3_fpu_addr), .rs3_fpu_ren(rs3_fpu_ren),
        .rs1_fpu_data(rs1_fpu_data), .rs2_fpu_data(rs2_fpu_data),
        .csr_addr(csr_addr), .csr_data(csr_data),
        .ds_to_es_valid(ds_to_es_valid0),
        .es_allowin(es_allowin0),
        .ds_flush(ds_flush0),
        .ds_to_es_bus(ds_to_es_bus0),
        .exe_fwd_bus0(exe_fwd_bus0),
        .exe_fwd_bus1(exe_fwd_bus1),
        .mem_fwd_bus0(mem_fwd_bus0),
        .mem_fwd_bus1(mem_fwd_bus1),
        .br_taken(br_redirect0),
        .exception_flag(exception_flag),
        .is_flush(is_flush),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus0)
    );

    exe_stage #(.LANE_ID(0)) u_exe0 (
        .clk(clk), .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid0),
        .ms_allowin(ms_allowin0),
        .ds_to_es_bus(ds_to_es_bus0),
        .ds_flush(ds_flush0),
        .es_allowin(es_allowin0),
        .es_to_ms_valid(es_to_ms_valid0),
        .es_flush(es_flush0),
        .es_to_ms_bus(es_to_ms_bus0),
        .dmem_addr(dmem_addr0), .dmem_wen(dmem_wen0),
        .dmem_en(dmem_en0), .dmem_wdata(dmem_wdata0),
        .exe_fwd_bus(exe_fwd_bus0),
        .exe_result_lane0(exe_result_current0),
        .exe_result_lane1(exe_result_current1),
        .exe_result_current(exe_result_current0),
        .ds_exc_bus(ds_exc_bus0),
        .exception_flag(exception_flag),
        .br_taken(br_taken0), .br_target(br_target0),
        .br_redirect(br_redirect0), .br_redirect_target(br_redirect_target0),
        .bp_update_valid(bp_update_valid0), .bp_update_pc(bp_update_pc0),
        .bp_update_taken(bp_update_taken0), .bp_update_target(bp_update_target0),
        .bp_update_is_jalr(bp_update_is_jalr0),
        .mem_result0(mem_result0),
        .mem_result1(mem_result1),
        .reg_fpu_data3(reg_fpu_data3),
        .exe_exc_bus(exe_exc_bus0)
    );

    //===========================================================================
    // Lane1: 全功能流水线
    //===========================================================================
    logic        ds_to_es_valid1;
    logic        es_allowin1;
    logic        ds_flush1;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus1;
    logic [`EXC_WIDTH-1:0] ds_exc_bus1;

    logic        br_redirect1, br_taken1;
    logic [31:0] br_target1, br_redirect_target1;
    logic        bp_update_valid1;
    logic [31:0] bp_update_pc1, bp_update_target1;
    logic        bp_update_taken1, bp_update_is_jalr1;

    logic [31:0] dmem_addr1, dmem_wdata1;
    logic [3:0]  dmem_wen1;
    logic        dmem_en1;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus1;

    id_stage u_id1 (
        .clk(clk), .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid1),
        .fs_to_ds_bus(fs_to_ds_bus1),
        .ds_allowin(ds_allowin1),
        .rs1_addr(rs1_addr1), .rs2_addr(rs2_addr1),
        .rs1_data(rs1_data1), .rs2_data(rs2_data1),
        .rs1_fpu_addr(), .rs2_fpu_addr(),
        .rs3_fpu_addr(), .rs3_fpu_ren(),
        .rs1_fpu_data('0), .rs2_fpu_data('0),
        .csr_addr(), .csr_data('0),
        .ds_to_es_valid(ds_to_es_valid1),
        .es_allowin(es_allowin1),
        .ds_flush(ds_flush1),
        .ds_to_es_bus(ds_to_es_bus1),
        .exe_fwd_bus0(exe_fwd_bus0),
        .exe_fwd_bus1(exe_fwd_bus1),
        .mem_fwd_bus0(mem_fwd_bus0),
        .mem_fwd_bus1(mem_fwd_bus1),
        .br_taken(br_redirect0 || br_redirect1),
        .exception_flag(exception_flag),
        .is_flush(is_flush1),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus1)
    );

    exe_stage #(.LANE_ID(1)) u_exe1 (
        .clk(clk), .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid1),
        .ms_allowin(ms_allowin1),
        .ds_to_es_bus(ds_to_es_bus1),
        .ds_flush(ds_flush1),
        .es_allowin(es_allowin1),
        .es_to_ms_valid(es_to_ms_valid1),
        .es_flush(es_flush1),
        .es_to_ms_bus(es_to_ms_bus1),
        .dmem_addr(dmem_addr1), .dmem_wen(dmem_wen1),
        .dmem_en(dmem_en1), .dmem_wdata(dmem_wdata1),
        .exe_fwd_bus(exe_fwd_bus1),
        .exe_result_lane0(exe_result_current0),
        .exe_result_lane1(exe_result_current1),
        .exe_result_current(exe_result_current1),
        .ds_exc_bus(ds_exc_bus1),
        .exception_flag(exception_flag),
        .br_taken(br_taken1), .br_target(br_target1),
        .br_redirect(br_redirect1), .br_redirect_target(br_redirect_target1),
        .bp_update_valid(bp_update_valid1), .bp_update_pc(bp_update_pc1),
        .bp_update_taken(bp_update_taken1), .bp_update_target(bp_update_target1),
        .bp_update_is_jalr(bp_update_is_jalr1),
        .mem_result0(mem_result0),
        .mem_result1(mem_result1),
        .reg_fpu_data3(reg_fpu_data3),
        .exe_exc_bus(exe_exc_bus1)
    );

    //===========================================================================
    // DMEM接口仲裁：lane0优先
    //===========================================================================
    assign dmem_addr      = dmem_en0       ? dmem_addr0     : dmem_addr1;
    assign dmem_wdata     = dmem_en0       ? dmem_wdata0    : dmem_wdata1;
    assign dmem_wen       = dmem_en0       ? dmem_wen0      : dmem_wen1;
    assign dmem_en        = dmem_en0       || dmem_en1;

    //===========================================================================
    // 分支/跳转接口：lane0优先
    //===========================================================================
    assign br_taken           = br_taken0           ? br_taken0           : br_taken1;
    assign br_target          = br_taken0           ? br_target0          : br_target1;
    assign br_redirect        = br_redirect0        ? br_redirect0        : br_redirect1;
    assign br_redirect_target = br_redirect0        ? br_redirect_target0 : br_redirect_target1;
    assign bp_update_valid    = bp_update_valid0    ? bp_update_valid0    : bp_update_valid1;
    assign bp_update_pc       = bp_update_valid0    ? bp_update_pc0       : bp_update_pc1;
    assign bp_update_taken    = bp_update_valid0    ? bp_update_taken0    : bp_update_taken1;
    assign bp_update_target   = bp_update_valid0    ? bp_update_target0   : bp_update_target1;
    assign bp_update_is_jalr  = bp_update_valid0    ? bp_update_is_jalr0  : bp_update_is_jalr1;

    //===========================================================================
    // 异常接口：lane0优先
    //===========================================================================
    assign exe_exc_bus = exe_exc_bus0 ? exe_exc_bus0 : exe_exc_bus1;

endmodule
