`include "defines.svh"
module cpu_top (
    input logic clk,
    input logic rst_n,
    //指令存储器接口
    input logic [31:0] imem_rdata,
    input logic [31:0] imem_rdata1,
    output logic [31:0] imem_addr,
    output logic [31:0] imem_addr1,
    output logic imem_en,
    //数据存储器接口
    input logic [31:0] dmem_rdata,
    input logic dmem_rvalid,
    output logic [31:0] dmem_addr,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    output logic [31:0] dmem_wdata,
    //plic接口
    input logic plic_irq
    //debug接口
    `ifdef DEBUG_EN
    ,
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
    output logic debug_store_valid,
    output logic [31:0] debug_store_pc,
    output logic [31:0] debug_store_addr,
    output logic [3:0] debug_store_wen,
    output logic [31:0] debug_store_wdata
    `endif
);

    //连接if模块
    logic ds_allowin;
    logic fs_to_ds_valid;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;
    logic frontend_redirect;
    logic [1:0] fetch_push_count;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_push_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_push_uop1;
    logic [1:0] fetch_pop_count;
    logic [3:0] fetch_count;
    logic [3:0] fetch_free_count;
    logic fetch_peek_valid0;
    logic fetch_peek_valid1;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_peek_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_peek_uop1;
    logic issue_bundle_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] issue_bundle;
    logic issue_pair_accepted;
    logic issue_reject_raw;
    logic issue_reject_waw;
    logic issue_reject_struct;
    logic bundle_push_ready;
    logic bundle_head_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle_head;
    logic bundle_next_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle_next;
    logic bundle_pop;
    logic [2:0] bundle_count;
    logic issue_queue_full_event;
    logic legacy_bundle_valid;
    logic legacy_bundle_pop;
    logic legacy_adapter_busy;
    logic legacy_ds_active;
    logic legacy_domain_idle;
    logic dual_candidate;
    logic next_dual_candidate;
    logic dual_bundle_valid;
    logic dual_bundle_pop;
    logic dual_launch_ready;
    logic dual_busy;
    logic dual_mode;
    logic [2:0] legacy_cooldown;
    logic prefer_legacy_dispatch;
    logic dual_rf_read_en;
    logic [4:0] dual_rf_raddr0;
    logic [4:0] dual_rf_raddr1;
    logic [4:0] dual_rf_raddr2;
    logic [4:0] dual_rf_raddr3;
    logic [31:0] dual_rf_rdata0;
    logic [31:0] dual_rf_rdata1;
    logic [31:0] dual_rf_rdata2;
    logic [31:0] dual_rf_rdata3;
    logic [1:0] dual_commit_valid;
    logic [1:0] dual_commit_wen;
    logic [4:0] dual_commit_waddr0;
    logic [4:0] dual_commit_waddr1;
    logic [31:0] dual_commit_wdata0;
    logic [31:0] dual_commit_wdata1;
    logic [1:0] dual_retire_count;
    logic dual_dependency_event;
    logic dual_pending_stall_event;
    logic rf_write0_wen;
    logic [4:0] rf_write0_waddr;
    logic [31:0] rf_write0_wdata;
    logic rf_write1_wen;
    logic [4:0] rf_write1_waddr;
    logic [31:0] rf_write1_wdata;
    logic br_taken;
    logic [31:0] br_target;
    logic br_redirect;
    logic [31:0] br_redirect_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic [`BP_TYPE_WIDTH-1:0] bp_update_type;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic exception_flag;
    logic [31:0] exception_addr;
    logic external_irq_enable;

    //连接id模块
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [4:0] rs1_fpu_addr;
    logic [4:0] rs2_fpu_addr;
    logic [4:0] rs3_fpu_addr;
    logic rs3_fpu_ren;
    logic [31:0] rs1_fpu_data;
    logic [31:0] rs2_fpu_data;
    logic [11:0] csr_addr;
    logic [31:0] csr_data;
    logic ds_to_es_valid;
    logic es_allowin;
    logic ds_flush;
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus;
    logic regfile_wen;
    logic reg_fpu_wen;
    logic [4:0] regfile_waddr;
    logic [`DATA_WIDTH-1:0] regfile_wdata;
    logic [4:0] exe_dest_addr;
    logic exe_regfile_wen;
    logic exe_reg_fpu_wen;
    logic [11:0] exe_csr_addr;
    logic exe_csr_wen;
    logic exe_load_pending;
    logic exe_result_pending;
    logic [4:0] mem_dest_addr;
    logic mem_regfile_wen;
    logic mem_reg_fpu_wen;
    logic [`EXC_WIDTH-1:0] ds_exc_bus;
    logic load_use_stall_event;

    //连接es模块
    logic es_valid;
    logic ms_allowin;
    logic es_to_ms_valid;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus;
    logic es_flush;
    logic [31:0] mem_result;
    logic [31:0] reg_fpu_data3;
    logic [`EXE_EXC_BUS - 1:0] exe_exc_bus;
    logic branch_event;
    logic branch_mispredict_event;
    logic execute_stall_event;
    logic ex_dmem_en;
    logic [31:0] ex_dmem_addr;
    logic [3:0] ex_dmem_wen;
    logic [31:0] ex_dmem_wdata;
    logic lsu_port_ready;

    //连接ms模块
    logic ms_valid;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus;
    logic ms_to_ws_valid;
    logic ws_allowin;
    logic csr_we;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic [1:0] legacy_retire_count;
    logic [1:0] retire_count;
    logic store_event;
    logic [31:0] store_pc;
    logic [31:0] store_addr;
    logic [3:0] store_wen;
    logic [31:0] store_wdata;

    //实例化
    if_stage u_if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(imem_addr),
        .pc_out1(imem_addr1),
        .inst_ren(imem_en),
        .inst_in(imem_rdata),
        .inst_in1(imem_rdata1),
        .fetch_free_count(fetch_free_count),
        .fetch_push_count(fetch_push_count),
        .fetch_push_uop0(fetch_push_uop0),
        .fetch_push_uop1(fetch_push_uop1),
        .frontend_redirect(frontend_redirect),
        .br_taken(br_redirect),
        .br_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_type(bp_update_type),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    fetch_fifo u_fetch_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .clear(frontend_redirect),
        .push_count(fetch_push_count),
        .push_uop0(fetch_push_uop0),
        .push_uop1(fetch_push_uop1),
        .pop_count(fetch_pop_count),
        .count(fetch_count),
        .free_count(fetch_free_count),
        .peek_valid0(fetch_peek_valid0),
        .peek_valid1(fetch_peek_valid1),
        .peek_uop0(fetch_peek_uop0),
        .peek_uop1(fetch_peek_uop1)
    );

    issue_stage u_issue_stage (
        .redirect(frontend_redirect),
        .fetch_count(fetch_count),
        .fetch_uop0(fetch_peek_uop0),
        .fetch_uop1(fetch_peek_uop1),
        .bundle_ready(bundle_push_ready),
        .fetch_pop_count(fetch_pop_count),
        .bundle_valid(issue_bundle_valid),
        .bundle(issue_bundle),
        .pair_accepted(issue_pair_accepted),
        .reject_raw(issue_reject_raw),
        .reject_waw(issue_reject_waw),
        .reject_struct(issue_reject_struct)
    );

    issue_bundle_fifo u_issue_bundle_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .clear(frontend_redirect),
        .push_valid(issue_bundle_valid),
        .push_bundle(issue_bundle),
        .pop_valid(bundle_pop),
        .head_valid(bundle_head_valid),
        .head_bundle(bundle_head),
        .next_valid(bundle_next_valid),
        .next_bundle(bundle_next),
        .count(bundle_count),
        .push_ready(bundle_push_ready)
    );

    // A dual synchronous read may launch while the final legacy WB commits;
    // the GPR provides explicit same-edge write-to-read bypass.
    assign legacy_domain_idle = !legacy_adapter_busy && !legacy_ds_active &&
                                !es_valid && !ms_valid;

    bundle_dispatch u_bundle_dispatch (
        .redirect(frontend_redirect),
        .bundle_valid(bundle_head_valid),
        .bundle(bundle_head),
        .next_bundle_valid(bundle_next_valid),
        .next_bundle(bundle_next),
        .legacy_idle(legacy_domain_idle),
        .prefer_legacy(prefer_legacy_dispatch),
        .dual_mode(dual_mode),
        .dual_candidate(dual_candidate),
        .next_dual_candidate(next_dual_candidate),
        .dual_bundle_valid(dual_bundle_valid),
        .legacy_bundle_valid(legacy_bundle_valid)
    );

    bundle_decode_adapter u_bundle_decode_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .redirect(frontend_redirect),
        .bundle_valid(legacy_bundle_valid),
        .bundle(bundle_head),
        .bundle_pop(legacy_bundle_pop),
        .busy(legacy_adapter_busy),
        .ds_allowin(ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus)
    );

    dual_alu_pipeline u_dual_alu_pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .redirect(frontend_redirect),
        .launch_valid(dual_bundle_valid),
        .launch_bundle(bundle_head),
        .launch_ready(dual_launch_ready),
        .busy(dual_busy),
        .rf_read_en(dual_rf_read_en),
        .rf_raddr0(dual_rf_raddr0),
        .rf_raddr1(dual_rf_raddr1),
        .rf_raddr2(dual_rf_raddr2),
        .rf_raddr3(dual_rf_raddr3),
        .rf_rdata0(dual_rf_rdata0),
        .rf_rdata1(dual_rf_rdata1),
        .rf_rdata2(dual_rf_rdata2),
        .rf_rdata3(dual_rf_rdata3),
        .commit_valid(dual_commit_valid),
        .commit_wen(dual_commit_wen),
        .commit_waddr0(dual_commit_waddr0),
        .commit_waddr1(dual_commit_waddr1),
        .commit_wdata0(dual_commit_wdata0),
        .commit_wdata1(dual_commit_wdata1),
        .retire_count(dual_retire_count),
        .dependency_event(dual_dependency_event),
        .pending_stall_event(dual_pending_stall_event),
        .commit_pc0(),
        .commit_pc1(),
        .commit_inst0(),
        .commit_inst1(),
        .commit_age0(),
        .commit_age1(),
        .commit_epoch0(),
        .commit_epoch1()
    );

    assign dual_bundle_pop = dual_bundle_valid && dual_launch_ready;
    assign bundle_pop = legacy_bundle_pop || dual_bundle_pop;

    always_ff @(posedge clk) begin
        if (!rst_n || frontend_redirect) begin
            dual_mode <= 1'b0;
        end else if (legacy_bundle_pop) begin
            dual_mode <= 1'b0;
        end else if (dual_bundle_pop) begin
            dual_mode <= 1'b1;
        end
    end

    // Avoid paying a full domain-drain penalty for a short ALU fragment
    // immediately following a legacy long-latency producer.  The bounded
    // cooldown is refreshed only by a real pending EX result and expires as
    // legacy bundles are consumed; long straight-line ALU runs still enter
    // dual mode through the lookahead rule.
    assign prefer_legacy_dispatch = exe_result_pending || exe_load_pending ||
                                    (legacy_cooldown != 0);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            legacy_cooldown <= 3'd0;
        end else if (exe_result_pending || exe_load_pending) begin
            legacy_cooldown <= 3'd4;
        end else if (legacy_bundle_pop && (legacy_cooldown != 0)) begin
            legacy_cooldown <= legacy_cooldown - 1'b1;
        end
    end

    assign issue_queue_full_event = !frontend_redirect &&
                                    (fetch_count != 0) &&
                                    !bundle_push_ready;

    id_stage u_id_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .ds_allowin(ds_allowin),
        .ds_active(legacy_ds_active),
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
        .regfile_wen(regfile_wen),
        .reg_fpu_wen(reg_fpu_wen),
        .regfile_waddr(regfile_waddr),
        .regfile_wdata(regfile_wdata),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .exe_reg_fpu_wen(exe_reg_fpu_wen),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .exe_load_pending(exe_load_pending),
        .exe_result_pending(exe_result_pending),
        .es_valid(es_valid),
        .mem_dest_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .mem_reg_fpu_wen(mem_reg_fpu_wen),
        .ms_valid(ms_valid),
        .br_taken(br_redirect),
        .exception_flag(exception_flag),
        .fs_exc_bus(fs_exc_bus),
        .ds_exc_bus(ds_exc_bus),
        .load_use_stall_event(load_use_stall_event)
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
        .dmem_rdata(dmem_rdata),
        .dmem_rvalid(dmem_rvalid),
        .lsu_port_ready(lsu_port_ready),
        .dmem_addr(ex_dmem_addr),
        .dmem_wen(ex_dmem_wen),
        .dmem_en(ex_dmem_en),
        .dmem_wdata(ex_dmem_wdata),
        .exe_dest_addr(exe_dest_addr),
        .exe_regfile_wen(exe_regfile_wen),
        .exe_reg_fpu_wen(exe_reg_fpu_wen),
        .exe_csr_addr(exe_csr_addr),
        .exe_csr_wen(exe_csr_wen),
        .exe_load_pending(exe_load_pending),
        .exe_result_pending(exe_result_pending),
        .es_valid(es_valid),
        .ds_exc_bus(ds_exc_bus),
        .exception_flag(exception_flag),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_redirect(br_redirect),
        .br_redirect_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_type(bp_update_type),
        .branch_event(branch_event),
        .branch_mispredict_event(branch_mispredict_event),
        .execute_stall_event(execute_stall_event),
        .mem_result(mem_result),
        .reg_fpu_data3(reg_fpu_data3),
        .exe_exc_bus(exe_exc_bus)
    );

    mem_stage u_mem_stage (
        .clk(clk),
        .rst_n(rst_n),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .ms_to_ws_bus(ms_to_ws_bus),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_allowin(ms_allowin),
        .ws_allowin(ws_allowin),
        .mem_dst_addr(mem_dest_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .mem_reg_fpu_wen(mem_reg_fpu_wen),
        .mem_result(mem_result),
        .ms_valid(ms_valid),
        .exception_flag(exception_flag),
        .exe_exc_bus(exe_exc_bus),
        .plic_irq(plic_irq),
        .external_irq_enable(external_irq_enable),
        .csr_we(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .retire_count(legacy_retire_count),
        .store_commit_valid(store_event),
        .store_commit_pc(store_pc),
        .store_commit_addr(store_addr),
        .store_commit_wen(store_wen),
        .store_commit_wdata(store_wdata)
    );

    // The data port is single-ported.  An older Store at MEM commit wins over
    // a younger EX LSU request; the resident remains unstarted and retries.
    assign lsu_port_ready = !store_event;
    assign dmem_en = store_event || ex_dmem_en;
    assign dmem_addr = store_event ? store_addr : ex_dmem_addr;
    assign dmem_wen = store_event ? store_wen : 4'b0000;
    assign dmem_wdata = store_event ? store_wdata : ex_dmem_wdata;

    wb_stage u_wb_stage (
        .clk(clk),
        .rst_n(rst_n),
        .ms_to_ws_bus(ms_to_ws_bus),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ws_allowin(ws_allowin),
        .regfile_wen(regfile_wen),
        .reg_fpu_wen(reg_fpu_wen),
        .regfile_addr(regfile_waddr),
        .regfile_wdata(regfile_wdata)
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

    assign rf_write0_wen = dual_commit_valid[0] ?
                           dual_commit_wen[0] : regfile_wen;
    assign rf_write0_waddr = dual_commit_valid[0] ?
                             dual_commit_waddr0 : regfile_waddr;
    assign rf_write0_wdata = dual_commit_valid[0] ?
                             dual_commit_wdata0 : regfile_wdata;
    assign rf_write1_wen = dual_commit_valid[1] && dual_commit_wen[1];
    assign rf_write1_waddr = dual_commit_waddr1;
    assign rf_write1_wdata = dual_commit_wdata1;

    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .write0_wen(rf_write0_wen),
        .write0_waddr(rf_write0_waddr),
        .write0_wdata(rf_write0_wdata),
        .write1_wen(rf_write1_wen),
        .write1_waddr(rf_write1_waddr),
        .write1_wdata(rf_write1_wdata),
        .regfile_raddr1(rs1_addr),
        .regfile_rdata1(rs1_data),
        .regfile_raddr2(rs2_addr),
        .regfile_rdata2(rs2_data),
        .sync_ren(dual_rf_read_en),
        .sync_raddr0(dual_rf_raddr0),
        .sync_raddr1(dual_rf_raddr1),
        .sync_raddr2(dual_rf_raddr2),
        .sync_raddr3(dual_rf_raddr3),
        .sync_rdata0(dual_rf_rdata0),
        .sync_rdata1(dual_rf_rdata1),
        .sync_rdata2(dual_rf_rdata2),
        .sync_rdata3(dual_rf_rdata3)
        `ifdef DEBUG_EN
        ,
        .debug_data(debug_data)
        `endif
    );

    reg_fpu u_reg_fpu (
        .clk(clk),
        .rst_n(rst_n),
        .reg_fpu_wen(reg_fpu_wen),
        .reg_fpu_waddr(regfile_waddr),
        .reg_fpu_wdata(regfile_wdata),
        .reg_fpu_raddr1(rs1_fpu_addr),
        .reg_fpu_rdata1(rs1_fpu_data),
        .reg_fpu_raddr2(rs2_fpu_addr),
        .reg_fpu_rdata2(rs2_fpu_data),
        .rs3_fpu_ren(rs3_fpu_ren),
        .reg_fpu_raddr3(rs3_fpu_addr),
        .reg_fpu_rdata3(reg_fpu_data3)
    );

    regfile_csr u_regfile_csr (
        .clk(clk),
        .rst_n(rst_n),
        .csr_wen(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .csr_raddr(csr_addr),
        .csr_rdata(csr_data),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .retire_count(retire_count),
        .branch_event(branch_event),
        .branch_mispredict_event(branch_mispredict_event),
        .load_use_stall_event(load_use_stall_event),
        .execute_stall_event(execute_stall_event),
        .issue_dual_event(issue_bundle_valid && issue_pair_accepted),
        .issue_single_event(issue_bundle_valid && !issue_pair_accepted),
        .issue_raw_event(issue_reject_raw),
        .issue_waw_event(issue_reject_waw),
        .issue_struct_event(issue_reject_struct),
        .issue_qfull_event(issue_queue_full_event),
        .result_dependency_event(dual_dependency_event),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr),
        .external_irq_enable(external_irq_enable)
    );

    assign retire_count = legacy_retire_count + dual_retire_count;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && dual_bundle_valid && legacy_bundle_valid) begin
            $fatal(1, "bundle dispatch selected both backend domains");
        end
        if (rst_n && (legacy_retire_count != 0) &&
            (dual_retire_count != 0)) begin
            $fatal(1, "legacy and dual domains retired in the same cycle");
        end
    end
`endif

    `ifdef DEBUG_EN
    assign debug_store_valid = store_event;
    assign debug_store_pc = store_pc;
    assign debug_store_addr = store_addr;
    assign debug_store_wen = store_wen;
    assign debug_store_wdata = store_wdata;
    `endif



endmodule
