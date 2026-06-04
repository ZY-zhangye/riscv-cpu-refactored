`include "defines.svh"
module cpu_top (
    input logic clk,
    input logic rst_n,
    //指令存储器接口
    input logic [31:0] imem_rdata,
    output logic [31:0] imem_addr,
    output logic imem_en,
    //数据存储器接口
    input logic [31:0] dmem_rdata,
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
    output logic [31:0] debug_data
    `endif
);

    //连接if模块
    logic fs_to_is_valid;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus;
    logic is_allowin;
    logic br_taken;
    logic [31:0] br_target;
    logic br_redirect;
    logic [31:0] br_redirect_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic bp_update_is_jalr;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic exception_flag;
    logic [31:0] exception_addr;
    logic external_irq_enable;

    //连接issue模块
    logic is_to_ds_valid;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus;
    logic ds_allowin;
    logic is_flush;

    //连接id_exe模块
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
    logic regfile_wen;
    logic reg_fpu_wen;
    logic [4:0] regfile_waddr;
    logic [`DATA_WIDTH-1:0] regfile_wdata;
    logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus;

    //连接es模块
    logic ms_allowin;
    logic es_to_ms_valid;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus;
    logic es_flush;
    logic [31:0] mem_result;
    logic [31:0] reg_fpu_data3;
    logic [`EXE_EXC_BUS - 1:0] exe_exc_bus;

    //连接ms模块
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus;
    logic ms_to_ws_valid;
    logic ws_allowin;
    logic csr_we;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic valid_inst;
    assign valid_inst = br_taken;

    //实例化
    if_stage u_if_stage (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(imem_addr),
        .inst_ren(imem_en),
        .inst_in(imem_rdata),
        .pc_out1(), // 预留的第二条指令地址输出
        .inst_ren1(), // 预留的第二条指令使能输出
        .inst_in1(), // 预留的第二条指令输入
        .ds_allowin(is_allowin),
        .fs_to_ds_valid(fs_to_is_valid),
        .fs_to_ds_bus(fs_to_is_bus),
        .ds_allowin1(1'b0), // 预留的第二条译码阶段允许信号
        .fs_to_ds_valid1(), // 预留的第二条指令有效信
        .fs_to_ds_bus1(), // 预留的第二条指令总线
        .br_taken(br_redirect),
        .br_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    issue_stage u_issue_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_is_valid(fs_to_is_valid),
        .fs_to_is_bus(fs_to_is_bus),
        .is_allowin(is_allowin),
        .is_to_ds_valid(is_to_ds_valid),
        .is_to_ds_bus(is_to_ds_bus),
        .ds_allowin(ds_allowin),
        .fs_to_is_valid1(1'b0),
        .fs_to_is_bus1('0),
        .is_allowin1(),
        .is_to_ds_valid1(),
        .is_to_ds_bus1(),
        .ds_allowin1(1'b0),
        .br_taken(br_redirect),
        .exception_flag(exception_flag),
        .is_flush(is_flush),
        .is_flush1()
    );

    id_exe_stage u_id_exe_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(is_to_ds_valid),
        .fs_to_ds_bus(is_to_ds_bus),
        .ds_allowin(ds_allowin),
        .is_flush(is_flush),
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
        .mem_fwd_bus(mem_fwd_bus),
        .exception_flag(exception_flag),
        .fs_exc_bus(fs_exc_bus),
        .ms_allowin(ms_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .mem_result(mem_result),
        .reg_fpu_data3(reg_fpu_data3),
        .exe_exc_bus(exe_exc_bus),
        .br_taken(br_taken),
        .br_target(br_target),
        .br_redirect(br_redirect),
        .br_redirect_target(br_redirect_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr)
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
        .dmem_rdata(dmem_rdata),
        .mem_fwd_bus(mem_fwd_bus),
        .mem_result(mem_result),
        .exception_flag(exception_flag),
        .exe_exc_bus(exe_exc_bus),
        .plic_irq(plic_irq),
        .external_irq_enable(external_irq_enable),
        .csr_we(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval)
    );

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
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen)
        `endif
    );

    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .regfile_wen(regfile_wen),
        .regfile_waddr(regfile_waddr),
        .regfile_wdata(regfile_wdata),
        .regfile_raddr1(rs1_addr),
        .regfile_rdata1(rs1_data),
        .regfile_raddr2(rs2_addr),
        .regfile_rdata2(rs2_data)
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
        .br_taken(br_redirect),
        .ms_to_ws_valid(ms_to_ws_valid),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr),
        .external_irq_enable(external_irq_enable)
    );



endmodule
