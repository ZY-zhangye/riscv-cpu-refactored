`include "defines.svh"

module cpu_top (
    input logic clk,
    input logic rst_n,
    //双路指令存储器接口
    input logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic imem_en,
    input logic [31:0] imem_rdata1,
    output logic [31:0] imem_addr1,
    output logic imem_en1,
    //单路数据存储器接口
    input logic [31:0] dmem_rdata,
    output logic [31:0] dmem_addr,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    output logic [31:0] dmem_wdata,
    input logic plic_irq
    `ifdef DEBUG_EN
    ,
    //兼容既有lane0调试接口
    output logic [31:0] debug_wb_pc,
    output logic [4:0] debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic debug_wb_rf_wen,
    output logic debug_wb_fpu_rf_wen,
    output logic [31:0] debug_data,
    output logic debug_commit_valid,
    output logic [31:0] debug_commit_inst,
    output logic debug_commit_csr_wen,
    output logic [11:0] debug_commit_csr_addr,
    output logic [31:0] debug_commit_csr_data,
    //lane1退休调试接口
    output logic [31:0] debug_wb_pc1,
    output logic [4:0] debug_wb_rf_addr1,
    output logic [31:0] debug_wb_rf_data1,
    output logic debug_wb_rf_wen1,
    output logic debug_wb_fpu_rf_wen1,
    output logic debug_commit_valid1,
    output logic [31:0] debug_commit_inst1,
    output logic debug_commit_csr_wen1,
    output logic [11:0] debug_commit_csr_addr1,
    output logic [31:0] debug_commit_csr_data1,
    //issue观察接口
    output logic [31:0] debug_issue_inst0,
    output logic [31:0] debug_issue_pc0,
    output logic debug_issue_valid0,
    output logic [31:0] debug_issue_inst1,
    output logic [31:0] debug_issue_pc1,
    output logic debug_issue_valid1,
    //store副作用trace
    output logic debug_store_valid,
    output logic [31:0] debug_store_pc,
    output logic [31:0] debug_store_addr,
    output logic [3:0] debug_store_wen,
    output logic [31:0] debug_store_wdata
    `endif
);

    // IF -> issue
    logic fs_to_is_valid0;
    logic fs_to_is_valid1;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus0;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1;
    logic issue_allowin;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;

    // branch/exception redirect：每个bundle最多一条控制流，按lane年龄选择
    logic br_redirect;
    logic [31:0] br_redirect_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic exception_flag;
    logic [31:0] exception_addr;
    logic external_irq_enable;
    logic br_taken0;
    logic [31:0] br_target0;
    logic br_redirect0;
    logic [31:0] br_redirect_target0;
    logic bp_update_valid0;
    logic [31:0] bp_update_pc0;
    logic bp_update_taken0;
    logic [31:0] bp_update_target0;
    logic bp_update_is_jalr0;
    logic bp_update_is_call0;
    logic bp_update_is_return0;
    logic br_taken1;
    logic [31:0] br_target1;
    logic br_redirect1;
    logic [31:0] br_redirect_target1;
    logic bp_update_valid1;
    logic [31:0] bp_update_pc1;
    logic bp_update_taken1;
    logic [31:0] bp_update_target1;
    logic bp_update_is_jalr1;
    logic bp_update_is_call1;
    logic bp_update_is_return1;

    // issue -> ID bundle
    logic is_to_ds_valid0;
    logic is_to_ds_valid1;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus0;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1;
    logic ds_bundle_allowin;
    logic issue_flush;
    logic dual_issue_event;
    logic single_issue_event;
    logic issue_raw_reject_event;
    logic issue_waw_reject_event;
    logic issue_struct_reject_event;
    logic issue_lsu_pair_event;
    logic issue_lane1_control_event;
    logic issue_bitman_pair_event;
    logic issue_cross_packet_pair_event;
    logic issue_queue_full_event;

    // GPR 4R2W
    logic [4:0] rs1_addr0;
    logic [4:0] rs2_addr0;
    logic [31:0] rs1_data0;
    logic [31:0] rs2_data0;
    logic [4:0] rs1_addr1;
    logic [4:0] rs2_addr1;
    logic [31:0] rs1_data1;
    logic [31:0] rs2_data1;
    logic wb_regfile_wen0;
    logic wb_reg_fpu_wen0;
    logic [4:0] wb_regfile_addr0;
    logic [31:0] wb_regfile_data0;
    logic wb_regfile_wen1;
    logic wb_reg_fpu_wen1;
    logic [4:0] wb_regfile_addr1;
    logic [31:0] wb_regfile_data1;

    // lane0 FPR/CSR；L1禁止lane1发射这些类别
    logic [4:0] rs1_fpu_addr0;
    logic [4:0] rs2_fpu_addr0;
    logic [4:0] rs3_fpu_addr0;
    logic rs3_fpu_ren0;
    logic [31:0] rs1_fpu_data0;
    logic [31:0] rs2_fpu_data0;
    logic [31:0] reg_fpu_data3;
    logic [11:0] csr_addr0;
    logic [31:0] csr_data0;
    logic [4:0] unused_fpu_addr1a;
    logic [4:0] unused_fpu_addr1b;
    logic [4:0] unused_fpu_addr1c;
    logic unused_fpu_ren1;
    logic [11:0] unused_csr_addr1;

    // ID lane0/lane1
    logic ds_allowin0_raw;
    logic ds_allowin1_raw;
    logic ds_valid0;
    logic ds_valid1;
    logic ds_to_es_valid0_raw;
    logic ds_to_es_valid1_raw;
    logic ds_to_es_valid0;
    logic ds_to_es_valid1;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus0;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus1;
    logic ds_flush0;
    logic ds_flush1;
    logic [`EXC_WIDTH-1:0] ds_exc_bus0;
    logic [`EXC_WIDTH-1:0] ds_exc_bus1;
    logic load_use_stall_event0;
    logic load_use_stall_event1;
    logic id_bundle_advance;
    logic id_lanes_ready;

    // EX lane0/lane1
    logic es_allowin0_raw;
    logic es_allowin1_raw;
    logic es_valid0;
    logic es_valid1;
    logic es_to_ms_valid0_raw;
    logic es_to_ms_valid1_raw;
    logic es_to_ms_valid0;
    logic es_to_ms_valid1;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus0;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus1;
    logic es_flush0;
    logic es_flush1;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus0;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus1;
    logic [4:0] exe_dest_addr0;
    logic exe_regfile_wen0;
    logic exe_reg_fpu_wen0;
    logic [11:0] exe_csr_addr0;
    logic exe_csr_wen0;
    logic exe_load_pending0;
    logic exe_result_pending0;
    logic [4:0] exe_dest_addr1;
    logic exe_regfile_wen1;
    logic exe_reg_fpu_wen1;
    logic [11:0] exe_csr_addr1;
    logic exe_csr_wen1;
    logic exe_load_pending1;
    logic exe_result_pending1;
    logic ex_branch_event;
    logic ex_branch_mispredict_event;
    logic execute_stall_event0;
    logic execute_stall_event1;
    logic ex_bundle_advance;
    logic ex_lanes_ready;

    // 双EX lane访存请求，顶层仲裁到单路数据存储器
    logic [31:0] ex_dmem_addr0;
    logic [31:0] ex_dmem_wdata0;
    logic [3:0] ex_dmem_wen0;
    logic ex_dmem_en0;
    logic [31:0] ex_dmem_addr1;
    logic [31:0] ex_dmem_wdata1;
    logic [3:0] ex_dmem_wen1;
    logic ex_dmem_en1;
    logic ex_load_request0;
    logic ex_load_request1;
    logic ex_load_request;
    logic mem_store_request;
    logic lsu_store_load_conflict;
    logic branch_event1;
    logic branch_mispredict_event1;
    logic unused_store_event1;
    logic [31:0] unused_store_pc1;
    logic [31:0] unused_store_addr1;
    logic [3:0] unused_store_wen1;
    logic [31:0] unused_store_wdata1;

    logic store_event0;
    logic [31:0] store_pc0;
    logic [31:0] store_addr0;
    logic [3:0] store_wen0;
    logic [31:0] store_wdata0;
    logic [31:0] exe_forward_result0;
    logic [31:0] exe_forward_result1;
    `ifdef L3F_SAME_CYCLE_ALU_BYPASS
    logic same_cycle_alu_producer0;
    logic same_cycle_alu_producer1;
    `endif

    // MEM lane0/lane1
    logic ms_allowin0_raw;
    logic ms_allowin1_raw;
    logic ms_valid0;
    logic ms_valid1;
    logic ms_to_ws_valid0;
    logic ms_to_ws_valid1;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus0;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus1;
    logic [4:0] mem_dest_addr0;
    logic mem_regfile_wen0;
    logic mem_reg_fpu_wen0;
    logic [31:0] mem_result0;
    logic [4:0] mem_dest_addr1;
    logic mem_regfile_wen1;
    logic mem_reg_fpu_wen1;
    logic [31:0] mem_result1;
    logic csr_we0;
    logic [11:0] csr_waddr0;
    logic [31:0] csr_wdata0;
    logic [6:0] exception_code0;
    logic [31:0] exception_mtval0;
    logic [6:0] exception_code1;
    logic [31:0] exception_mtval1;
    logic [1:0] retire_count0;
    logic [1:0] retire_count1;
    logic ws_bundle_allowin;
    logic ws_allowin0_raw;
    logic ws_allowin1_raw;

    logic csr_we1;
    logic [11:0] csr_waddr1;
    logic [31:0] csr_wdata1;
    logic [6:0] selected_exception_code;
    logic [31:0] selected_exception_mtval;
    logic selected_csr_we;
    logic [11:0] selected_csr_waddr;
    logic [31:0] selected_csr_wdata;
    logic lane0_redirect_event;
    logic lane1_commit_kill;
    logic store_commit_valid0;
    logic [31:0] store_commit_pc0;
    logic [31:0] store_commit_addr0;
    logic [3:0] store_commit_wen0;
    logic [31:0] store_commit_wdata0;
    logic store_commit_valid1;
    logic [31:0] store_commit_pc1;
    logic [31:0] store_commit_addr1;
    logic [3:0] store_commit_wen1;
    logic [31:0] store_commit_wdata1;

    logic [1:0] retire_count_total;
    logic irq_pending;
    logic plic_irq_at_bundle_boundary;

    // IF
    if_stage u_if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(imem_addr),
        .inst_ren(imem_en),
        .inst_in(imem_rdata),
        .pc_out1(imem_addr1),
        .inst_ren1(imem_en1),
        .inst_in1(imem_rdata1),
        .ds_allowin(issue_allowin),
        .fs_to_ds_valid(fs_to_is_valid0),
        .fs_to_ds_valid1(fs_to_is_valid1),
        .fs_to_ds_bus(fs_to_is_bus0),
        .fs_to_ds_bus1(fs_to_is_bus1),
        .br_taken(br_redirect),
        .br_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .bp_update_is_call(bp_update_is_call),
        .bp_update_is_return(bp_update_is_return),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    // Issue
    assign ds_bundle_allowin = ds_allowin0_raw && ds_allowin1_raw;

    issue_stage u_issue_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_is_valid0(fs_to_is_valid0),
        .fs_to_is_valid1(fs_to_is_valid1),
        .fs_to_is_bus0(fs_to_is_bus0),
        .fs_to_is_bus1(fs_to_is_bus1),
        .is_allowin(issue_allowin),
        .is_to_ds_valid0(is_to_ds_valid0),
        .is_to_ds_valid1(is_to_ds_valid1),
        .is_to_ds_bus0(is_to_ds_bus0),
        .is_to_ds_bus1(is_to_ds_bus1),
        .ds_bundle_allowin(ds_bundle_allowin),
        .br_redirect(br_redirect),
        .exception_flag(exception_flag),
        .issue_flush(issue_flush),
        .dual_issue_event(dual_issue_event),
        .single_issue_event(single_issue_event),
        .issue_raw_reject_event(issue_raw_reject_event),
        .issue_waw_reject_event(issue_waw_reject_event),
        .issue_struct_reject_event(issue_struct_reject_event),
        .issue_lsu_pair_event(issue_lsu_pair_event),
        .issue_lane1_control_event(issue_lane1_control_event),
        .issue_bitman_pair_event(issue_bitman_pair_event),
        .issue_cross_packet_pair_event(issue_cross_packet_pair_event),
        .issue_queue_full_event(issue_queue_full_event)
        `ifdef DEBUG_EN
        ,
        .debug_issue_inst0(debug_issue_inst0),
        .debug_issue_pc0(debug_issue_pc0),
        .debug_issue_valid0(debug_issue_valid0),
        .debug_issue_inst1(debug_issue_inst1),
        .debug_issue_pc1(debug_issue_pc1),
        .debug_issue_valid1(debug_issue_valid1)
        `endif
    );

    // ID bundle coupling. ds_to_es_valid本身只表示lane就绪，真正送入EX时再用
    // id_bundle_advance门控，避免其中一条因相关停顿时另一条先行。
    assign id_lanes_ready = (!ds_valid0 || ds_to_es_valid0_raw) &&
                            (!ds_valid1 || ds_to_es_valid1_raw);
    assign id_bundle_advance = es_allowin0_raw && es_allowin1_raw &&
                               id_lanes_ready;
    assign ds_to_es_valid0 = ds_to_es_valid0_raw && id_bundle_advance;
    assign ds_to_es_valid1 = ds_to_es_valid1_raw && id_bundle_advance;

    id_stage u_id_stage0 (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(is_to_ds_valid0 && ds_bundle_allowin),
        .ds_allowin(ds_allowin0_raw),
        .fs_to_ds_bus(is_to_ds_bus0),
        .rs1_addr(rs1_addr0),
        .rs2_addr(rs2_addr0),
        .rs1_data(rs1_data0),
        .rs2_data(rs2_data0),
        .rs1_fpu_addr(rs1_fpu_addr0),
        .rs2_fpu_addr(rs2_fpu_addr0),
        .rs3_fpu_addr(rs3_fpu_addr0),
        .rs3_fpu_ren(rs3_fpu_ren0),
        .rs1_fpu_data(rs1_fpu_data0),
        .rs2_fpu_data(rs2_fpu_data0),
        .csr_addr(csr_addr0),
        .csr_data(csr_data0),
        .ds_to_es_valid(ds_to_es_valid0_raw),
        .es_allowin(id_bundle_advance),
        .ds_flush(ds_flush0),
        .ds_to_es_bus(ds_to_es_bus0),
        .regfile_wen(wb_regfile_wen0),
        .reg_fpu_wen(wb_reg_fpu_wen0),
        .regfile_waddr(wb_regfile_addr0),
        .regfile_wdata(wb_regfile_data0),
        .regfile_wen1(wb_regfile_wen1),
        .reg_fpu_wen1(wb_reg_fpu_wen1),
        .regfile_waddr1(wb_regfile_addr1),
        .regfile_wdata1(wb_regfile_data1),
        .exe_dest_addr(exe_dest_addr0),
        .exe_regfile_wen(exe_regfile_wen0),
        .exe_reg_fpu_wen(exe_reg_fpu_wen0),
        .exe_csr_addr(exe_csr_addr0),
        .exe_csr_wen(exe_csr_wen0),
        .exe_load_pending(exe_load_pending0),
        .exe_result_pending(exe_result_pending0),
        .es_valid(es_valid0),
        .mem_dest_addr(mem_dest_addr0),
        .mem_regfile_wen(mem_regfile_wen0),
        .mem_reg_fpu_wen(mem_reg_fpu_wen0),
        .ms_valid(ms_valid0),
        .secondary_exe_dest_addr(exe_dest_addr1),
        .secondary_exe_regfile_wen(exe_regfile_wen1),
        .secondary_exe_load_pending(exe_load_pending1),
        .secondary_exe_result_pending(exe_result_pending1),
        .secondary_es_valid(es_valid1),
        .secondary_mem_dest_addr(mem_dest_addr1),
        .secondary_mem_regfile_wen(mem_regfile_wen1),
        .secondary_ms_valid(ms_valid1),
        .br_taken(br_redirect),
        .exception_flag(exception_flag),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus0),
        .load_use_stall_event(load_use_stall_event0),
        .ds_valid_out(ds_valid0)
    );

    id_stage u_id_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(is_to_ds_valid1 && ds_bundle_allowin),
        .ds_allowin(ds_allowin1_raw),
        .fs_to_ds_bus(is_to_ds_bus1),
        .rs1_addr(rs1_addr1),
        .rs2_addr(rs2_addr1),
        .rs1_data(rs1_data1),
        .rs2_data(rs2_data1),
        .rs1_fpu_addr(unused_fpu_addr1a),
        .rs2_fpu_addr(unused_fpu_addr1b),
        .rs3_fpu_addr(unused_fpu_addr1c),
        .rs3_fpu_ren(unused_fpu_ren1),
        .rs1_fpu_data(32'b0),
        .rs2_fpu_data(32'b0),
        .csr_addr(unused_csr_addr1),
        .csr_data(32'b0),
        .ds_to_es_valid(ds_to_es_valid1_raw),
        .es_allowin(id_bundle_advance),
        .ds_flush(ds_flush1),
        .ds_to_es_bus(ds_to_es_bus1),
        .regfile_wen(wb_regfile_wen0),
        .reg_fpu_wen(wb_reg_fpu_wen0),
        .regfile_waddr(wb_regfile_addr0),
        .regfile_wdata(wb_regfile_data0),
        .regfile_wen1(wb_regfile_wen1),
        .reg_fpu_wen1(wb_reg_fpu_wen1),
        .regfile_waddr1(wb_regfile_addr1),
        .regfile_wdata1(wb_regfile_data1),
        .exe_dest_addr(exe_dest_addr0),
        .exe_regfile_wen(exe_regfile_wen0),
        .exe_reg_fpu_wen(exe_reg_fpu_wen0),
        .exe_csr_addr(exe_csr_addr0),
        .exe_csr_wen(exe_csr_wen0),
        .exe_load_pending(exe_load_pending0),
        .exe_result_pending(exe_result_pending0),
        .es_valid(es_valid0),
        .mem_dest_addr(mem_dest_addr0),
        .mem_regfile_wen(mem_regfile_wen0),
        .mem_reg_fpu_wen(mem_reg_fpu_wen0),
        .ms_valid(ms_valid0),
        .secondary_exe_dest_addr(exe_dest_addr1),
        .secondary_exe_regfile_wen(exe_regfile_wen1),
        .secondary_exe_load_pending(exe_load_pending1),
        .secondary_exe_result_pending(exe_result_pending1),
        .secondary_es_valid(es_valid1),
        .secondary_mem_dest_addr(mem_dest_addr1),
        .secondary_mem_regfile_wen(mem_regfile_wen1),
        .secondary_ms_valid(ms_valid1),
        .br_taken(br_redirect),
        .exception_flag(exception_flag),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus1),
        .load_use_stall_event(load_use_stall_event1),
        .ds_valid_out(ds_valid1)
    );

    // EX bundle coupling
    assign ex_lanes_ready = (!es_valid0 || es_to_ms_valid0_raw) &&
                            (!es_valid1 || es_to_ms_valid1_raw);
    assign ex_bundle_advance = ms_allowin0_raw && ms_allowin1_raw &&
                               ex_lanes_ready && !lsu_store_load_conflict;
    assign es_to_ms_valid0 = es_to_ms_valid0_raw && ex_bundle_advance;
    assign es_to_ms_valid1 = es_to_ms_valid1_raw && ex_bundle_advance;

    // lane0控制流年龄更老；当前配对规则不会让两个lane同时包含控制流。
    assign br_redirect = br_redirect0 || br_redirect1;
    assign br_redirect_target = br_redirect0 ? br_redirect_target0 : br_redirect_target1;
    assign bp_update_valid = bp_update_valid0 || bp_update_valid1;
    assign bp_update_pc = bp_update_valid0 ? bp_update_pc0 : bp_update_pc1;
    assign bp_update_taken = bp_update_valid0 ? bp_update_taken0 : bp_update_taken1;
    assign bp_update_target = bp_update_valid0 ? bp_update_target0 : bp_update_target1;
    assign bp_update_is_jalr = bp_update_valid0 ? bp_update_is_jalr0 : bp_update_is_jalr1;
    assign bp_update_is_call = bp_update_valid0 ? bp_update_is_call0 : bp_update_is_call1;
    assign bp_update_is_return = bp_update_valid0 ? bp_update_is_return0 : bp_update_is_return1;

    exe_stage u_exe_stage0 (
        .clk(clk),
        .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid0),
        .es_allowin(es_allowin0_raw),
        .ms_allowin(ex_bundle_advance),
        .es_to_ms_valid(es_to_ms_valid0_raw),
        .ds_flush(ds_flush0),
        .ds_to_es_bus(ds_to_es_bus0),
        .es_to_ms_bus(es_to_ms_bus0),
        .es_flush(es_flush0),
        .forward_ex_result0(exe_forward_result0),
        .forward_ex_result1(exe_forward_result1),
        .forward_mem_result0(mem_result0),
        .forward_mem_result1(mem_result1),
        .reg_fpu_data3(reg_fpu_data3),
        .dmem_addr(ex_dmem_addr0),
        .dmem_wdata(ex_dmem_wdata0),
        .dmem_wen(ex_dmem_wen0),
        .dmem_en(ex_dmem_en0),
        .exe_dest_addr(exe_dest_addr0),
        .exe_regfile_wen(exe_regfile_wen0),
        .exe_reg_fpu_wen(exe_reg_fpu_wen0),
        .exe_csr_addr(exe_csr_addr0),
        .exe_csr_wen(exe_csr_wen0),
        .exe_load_pending(exe_load_pending0),
        .exe_result_pending(exe_result_pending0),
        .es_valid(es_valid0),
        .ds_exc_bus(ds_exc_bus0),
        .exe_exc_bus(exe_exc_bus0),
        .exception_flag(exception_flag),
        .br_taken(br_taken0),
        .br_target(br_target0),
        .br_redirect(br_redirect0),
        .br_redirect_target(br_redirect_target0),
        .bp_update_valid(bp_update_valid0),
        .bp_update_pc(bp_update_pc0),
        .bp_update_taken(bp_update_taken0),
        .bp_update_target(bp_update_target0),
        .bp_update_is_jalr(bp_update_is_jalr0),
        .bp_update_is_call(bp_update_is_call0),
        .bp_update_is_return(bp_update_is_return0),
        .branch_event(ex_branch_event),
        .branch_mispredict_event(ex_branch_mispredict_event),
        .execute_stall_event(execute_stall_event0),
        .store_event(store_event0),
        .store_pc(store_pc0),
        .store_addr(store_addr0),
        .store_wen(store_wen0),
        .store_wdata(store_wdata0),
        .exe_forward_result(exe_forward_result0)
        `ifdef L3F_SAME_CYCLE_ALU_BYPASS
        ,
        .same_cycle_bypass_valid(1'b0),
        .same_cycle_bypass_addr(5'b0),
        .same_cycle_alu_producer(same_cycle_alu_producer0)
        `endif
    );

    exe_stage u_exe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_valid1),
        .es_allowin(es_allowin1_raw),
        .ms_allowin(ex_bundle_advance),
        .es_to_ms_valid(es_to_ms_valid1_raw),
        .ds_flush(ds_flush1),
        .ds_to_es_bus(ds_to_es_bus1),
        .es_to_ms_bus(es_to_ms_bus1),
        .es_flush(es_flush1),
        .forward_ex_result0(exe_forward_result0),
        .forward_ex_result1(exe_forward_result1),
        .forward_mem_result0(mem_result0),
        .forward_mem_result1(mem_result1),
        .reg_fpu_data3(32'b0),
        .dmem_addr(ex_dmem_addr1),
        .dmem_wdata(ex_dmem_wdata1),
        .dmem_wen(ex_dmem_wen1),
        .dmem_en(ex_dmem_en1),
        .exe_dest_addr(exe_dest_addr1),
        .exe_regfile_wen(exe_regfile_wen1),
        .exe_reg_fpu_wen(exe_reg_fpu_wen1),
        .exe_csr_addr(exe_csr_addr1),
        .exe_csr_wen(exe_csr_wen1),
        .exe_load_pending(exe_load_pending1),
        .exe_result_pending(exe_result_pending1),
        .es_valid(es_valid1),
        .ds_exc_bus(ds_exc_bus1),
        .exe_exc_bus(exe_exc_bus1),
        .exception_flag(exception_flag),
        .br_taken(br_taken1),
        .br_target(br_target1),
        .br_redirect(br_redirect1),
        .br_redirect_target(br_redirect_target1),
        .bp_update_valid(bp_update_valid1),
        .bp_update_pc(bp_update_pc1),
        .bp_update_taken(bp_update_taken1),
        .bp_update_target(bp_update_target1),
        .bp_update_is_jalr(bp_update_is_jalr1),
        .bp_update_is_call(bp_update_is_call1),
        .bp_update_is_return(bp_update_is_return1),
        .branch_event(branch_event1),
        .branch_mispredict_event(branch_mispredict_event1),
        .execute_stall_event(execute_stall_event1),
        .store_event(unused_store_event1),
        .store_pc(unused_store_pc1),
        .store_addr(unused_store_addr1),
        .store_wen(unused_store_wen1),
        .store_wdata(unused_store_wdata1),
        .exe_forward_result(exe_forward_result1)
        `ifdef L3F_SAME_CYCLE_ALU_BYPASS
        ,
        .same_cycle_bypass_valid(same_cycle_alu_producer0),
        .same_cycle_bypass_addr(exe_dest_addr0),
        .same_cycle_alu_producer(same_cycle_alu_producer1)
        `endif
    );

    // 外部中断只在bundle边界交给lane0；若当前有lane1退休则先记为pending。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending <= 1'b0;
        end else if (exception_code0 == `PLIC_IRQ_BIT) begin
            irq_pending <= 1'b0;
        end else if (plic_irq && external_irq_enable) begin
            irq_pending <= 1'b1;
        end
    end
    assign plic_irq_at_bundle_boundary = (plic_irq || irq_pending) && !ms_valid1;

    assign ws_bundle_allowin = ws_allowin0_raw && ws_allowin1_raw;
    assign lane0_redirect_event = exception_code0[5] ||
                                  (exception_code0 == 7'b100_0000);
    assign lane1_commit_kill = lane0_redirect_event;

    mem_stage u_mem_stage0 (
        .clk(clk),
        .rst_n(rst_n),
        .es_flush(es_flush0),
        .es_to_ms_bus(es_to_ms_bus0),
        .ms_to_ws_bus(ms_to_ws_bus0),
        .es_to_ms_valid(es_to_ms_valid0),
        .ms_to_ws_valid(ms_to_ws_valid0),
        .ms_allowin(ms_allowin0_raw),
        .ws_allowin(ws_bundle_allowin),
        .ms_valid(ms_valid0),
        .dmem_rdata(dmem_rdata),
        .commit_kill(1'b0),
        .store_commit_valid(store_commit_valid0),
        .store_commit_pc(store_commit_pc0),
        .store_commit_addr(store_commit_addr0),
        .store_commit_wen(store_commit_wen0),
        .store_commit_wdata(store_commit_wdata0),
        .mem_dst_addr(mem_dest_addr0),
        .mem_regfile_wen(mem_regfile_wen0),
        .mem_reg_fpu_wen(mem_reg_fpu_wen0),
        .mem_result(mem_result0),
        .exception_flag(exception_flag),
        .exe_exc_bus(exe_exc_bus0),
        .plic_irq(plic_irq_at_bundle_boundary),
        .external_irq_enable(external_irq_enable),
        .csr_we(csr_we0),
        .csr_waddr(csr_waddr0),
        .csr_wdata(csr_wdata0),
        .exception_code(exception_code0),
        .exception_mtval(exception_mtval0),
        .retire_count(retire_count0)
    );

    mem_stage u_mem_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .es_flush(es_flush1),
        .es_to_ms_bus(es_to_ms_bus1),
        .ms_to_ws_bus(ms_to_ws_bus1),
        .es_to_ms_valid(es_to_ms_valid1),
        .ms_to_ws_valid(ms_to_ws_valid1),
        .ms_allowin(ms_allowin1_raw),
        .ws_allowin(ws_bundle_allowin),
        .ms_valid(ms_valid1),
        .dmem_rdata(dmem_rdata),
        .commit_kill(lane1_commit_kill),
        .store_commit_valid(store_commit_valid1),
        .store_commit_pc(store_commit_pc1),
        .store_commit_addr(store_commit_addr1),
        .store_commit_wen(store_commit_wen1),
        .store_commit_wdata(store_commit_wdata1),
        .mem_dst_addr(mem_dest_addr1),
        .mem_regfile_wen(mem_regfile_wen1),
        .mem_reg_fpu_wen(mem_reg_fpu_wen1),
        .mem_result(mem_result1),
        .exception_flag(exception_flag),
        .exe_exc_bus(exe_exc_bus1),
        .plic_irq(1'b0),
        .external_irq_enable(1'b0),
        .csr_we(csr_we1),
        .csr_waddr(csr_waddr1),
        .csr_wdata(csr_wdata1),
        .exception_code(exception_code1),
        .exception_mtval(exception_mtval1),
        .retire_count(retire_count1)
    );

    // 单LSU仲裁。已到MEM且确认提交的store优先于年轻EX load；冲突时冻结整个EX bundle一拍。
    assign ex_load_request0 = ex_dmem_en0 && (ex_dmem_wen0 == 4'b0000);
    assign ex_load_request1 = ex_dmem_en1 && (ex_dmem_wen1 == 4'b0000);
    assign ex_load_request = ex_load_request0 || ex_load_request1;
    assign mem_store_request = store_commit_valid0 || store_commit_valid1;
    assign lsu_store_load_conflict = mem_store_request && ex_load_request;
    assign dmem_en = mem_store_request || (ex_load_request && ex_bundle_advance);
    assign dmem_addr = store_commit_valid0 ? store_commit_addr0 :
                       store_commit_valid1 ? store_commit_addr1 :
                       ex_load_request0 ? ex_dmem_addr0 : ex_dmem_addr1;
    assign dmem_wen = store_commit_valid0 ? store_commit_wen0 :
                      store_commit_valid1 ? store_commit_wen1 : 4'b0000;
    assign dmem_wdata = store_commit_valid0 ? store_commit_wdata0 :
                        store_commit_valid1 ? store_commit_wdata1 : 32'b0;

    wb_stage u_wb_stage0 (
        .clk(clk),
        .rst_n(rst_n),
        .ms_to_ws_bus(ms_to_ws_bus0),
        .ms_to_ws_valid(ms_to_ws_valid0),
        .ws_allowin(ws_allowin0_raw),
        .regfile_wen(wb_regfile_wen0),
        .reg_fpu_wen(wb_reg_fpu_wen0),
        .regfile_addr(wb_regfile_addr0),
        .regfile_wdata(wb_regfile_data0)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_commit_valid(debug_commit_valid),
        .debug_commit_inst(debug_commit_inst),
        .debug_commit_csr_wen(debug_commit_csr_wen),
        .debug_commit_csr_addr(debug_commit_csr_addr),
        .debug_commit_csr_data(debug_commit_csr_data)
        `endif
    );

    wb_stage u_wb_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .ms_to_ws_bus(ms_to_ws_bus1),
        .ms_to_ws_valid(ms_to_ws_valid1),
        .ws_allowin(ws_allowin1_raw),
        .regfile_wen(wb_regfile_wen1),
        .reg_fpu_wen(wb_reg_fpu_wen1),
        .regfile_addr(wb_regfile_addr1),
        .regfile_wdata(wb_regfile_data1)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc1),
        .debug_wb_rf_addr(debug_wb_rf_addr1),
        .debug_wb_rf_data(debug_wb_rf_data1),
        .debug_wb_rf_wen(debug_wb_rf_wen1),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen1),
        .debug_commit_valid(debug_commit_valid1),
        .debug_commit_inst(debug_commit_inst1),
        .debug_commit_csr_wen(debug_commit_csr_wen1),
        .debug_commit_csr_addr(debug_commit_csr_addr1),
        .debug_commit_csr_data(debug_commit_csr_data1)
        `endif
    );

    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .regfile_wen(wb_regfile_wen0),
        .regfile_waddr(wb_regfile_addr0),
        .regfile_wdata(wb_regfile_data0),
        .regfile_wen1(wb_regfile_wen1),
        .regfile_waddr1(wb_regfile_addr1),
        .regfile_wdata1(wb_regfile_data1),
        .regfile_raddr1(rs1_addr0),
        .regfile_rdata1(rs1_data0),
        .regfile_raddr2(rs2_addr0),
        .regfile_rdata2(rs2_data0),
        .regfile_raddr3(rs1_addr1),
        .regfile_rdata3(rs1_data1),
        .regfile_raddr4(rs2_addr1),
        .regfile_rdata4(rs2_data1)
        `ifdef DEBUG_EN
        ,
        .debug_data(debug_data)
        `endif
    );

    reg_fpu u_reg_fpu (
        .clk(clk),
        .rst_n(rst_n),
        .reg_fpu_wen(wb_reg_fpu_wen0),
        .reg_fpu_waddr(wb_regfile_addr0),
        .reg_fpu_wdata(wb_regfile_data0),
        .reg_fpu_raddr1(rs1_fpu_addr0),
        .reg_fpu_rdata1(rs1_fpu_data0),
        .reg_fpu_raddr2(rs2_fpu_addr0),
        .reg_fpu_rdata2(rs2_fpu_data0),
        .rs3_fpu_ren(rs3_fpu_ren0),
        .reg_fpu_raddr3(rs3_fpu_addr0),
        .reg_fpu_rdata3(reg_fpu_data3)
    );

    assign retire_count_total = retire_count0 + retire_count1;

    // oldest-first异常选择：lane0异常/返回优先；lane1异常仍允许lane0正常提交。
    assign selected_exception_code = lane0_redirect_event ? exception_code0 : exception_code1;
    assign selected_exception_mtval = lane0_redirect_event ? exception_mtval0 : exception_mtval1;
    assign selected_csr_we = csr_we0 || csr_we1;
    assign selected_csr_waddr = csr_we0 ? csr_waddr0 : csr_waddr1;
    assign selected_csr_wdata = lane0_redirect_event ? csr_wdata0 :
                                exception_code1[5] ? csr_wdata1 :
                                csr_we0 ? csr_wdata0 : csr_wdata1;

    regfile_csr u_regfile_csr (
        .clk(clk),
        .rst_n(rst_n),
        .csr_wen(selected_csr_we),
        .csr_waddr(selected_csr_waddr),
        .csr_wdata(selected_csr_wdata),
        .csr_raddr(csr_addr0),
        .csr_rdata(csr_data0),
        .exception_code(selected_exception_code),
        .exception_mtval(selected_exception_mtval),
        .retire_count(retire_count_total),
        .branch_event(ex_branch_event || branch_event1),
        .branch_mispredict_event(ex_branch_mispredict_event || branch_mispredict_event1),
        .load_use_stall_event(load_use_stall_event0 || load_use_stall_event1),
        .execute_stall_event(execute_stall_event0 || execute_stall_event1),
        .dual_issue_event(dual_issue_event),
        .single_issue_event(single_issue_event),
        .issue_raw_reject_event(issue_raw_reject_event),
        .issue_waw_reject_event(issue_waw_reject_event),
        .issue_struct_reject_event(issue_struct_reject_event),
        .issue_lsu_pair_event(issue_lsu_pair_event),
        .issue_lane1_control_event(issue_lane1_control_event),
        .lsu_conflict_event(lsu_store_load_conflict),
        .issue_bitman_pair_event(issue_bitman_pair_event),
        .issue_cross_packet_pair_event(issue_cross_packet_pair_event),
        .issue_queue_full_event(issue_queue_full_event),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr),
        .external_irq_enable(external_irq_enable)
    );

    `ifdef DEBUG_EN
    assign debug_store_valid = store_commit_valid0 || store_commit_valid1;
    assign debug_store_pc = store_commit_valid0 ? store_commit_pc0 : store_commit_pc1;
    assign debug_store_addr = store_commit_valid0 ? store_commit_addr0 : store_commit_addr1;
    assign debug_store_wen = store_commit_valid0 ? store_commit_wen0 : store_commit_wen1;
    assign debug_store_wdata = store_commit_valid0 ? store_commit_wdata0 : store_commit_wdata1;
    `endif

endmodule
