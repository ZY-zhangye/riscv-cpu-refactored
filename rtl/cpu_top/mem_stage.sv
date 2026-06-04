`include "defines.svh"
module mem_stage (
    input logic clk,
    input logic rst_n,
    //来自执行阶段的信息
    input logic es_flush0,
    input logic es_flush1,
    input logic [`ES_MS_WIDTH-1:0] es_to_ms_bus0,
    input logic [`ES_MS_WIDTH-1:0] es_to_ms_bus1,
    //送到写回阶段的信息
    output logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus0,
    output logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus1,
    //握手信号
    input logic es_to_ms_valid0,
    input logic es_to_ms_valid1,
    output logic ms_to_ws_valid0,
    output logic ms_to_ws_valid1,
    output logic ms_allowin0,
    output logic ms_allowin1,
    input logic ws_allowin0,
    input logic ws_allowin1,
    //数据存储器接口
    input logic [31:0] dmem_rdata,
    //数据前递接口-打包
    output logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus0,
    output logic [`MEM_FWD_PACKET_WIDTH-1:0] mem_fwd_bus1,
    output logic [31:0] mem_result0,
    output logic [31:0] mem_result1,
    //异常信息接口
    input logic exception_flag,
    input logic [`EXE_EXC_BUS-1:0] exe_exc_bus,
    //plic接口
    input logic plic_irq,
    input logic external_irq_enable,
    //CSR接口（二选一分发）
    output logic csr_we,
    output logic [11:0] csr_waddr,
    output logic [31:0] csr_wdata,
    output logic [6:0] exception_code,
    output logic [31:0] exception_mtval
);

    logic ms_valid0, ms_valid1;
    logic mem_regfile_wen0, mem_regfile_wen1;
    logic mem_reg_fpu_wen0, mem_reg_fpu_wen1;
    logic [`ES_MS_WIDTH-1:0] es_ms_bus_r0, es_ms_bus_r1;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus_r0, exe_exc_bus_r1;
    logic ms_ready_go0, ms_ready_go1;
    logic es_flush_r0, es_flush_r1;
    logic ms_flush0, ms_flush1;

    assign ms_ready_go0 = 1'b1;
    assign ms_ready_go1 = 1'b1;

    assign ms_allowin0 = !ms_valid0 || ms_ready_go0 && ws_allowin0;
    assign ms_allowin1 = !ms_valid1 || ms_ready_go1 && ws_allowin1;

    assign ms_to_ws_valid0 = ms_valid0 && ms_ready_go0;
    assign ms_to_ws_valid1 = ms_valid1 && ms_ready_go1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_valid0 <= 1'b0;
            ms_valid1 <= 1'b0;
        end else begin
            if (ms_allowin0) ms_valid0 <= es_to_ms_valid0;
            if (ms_allowin1) ms_valid1 <= es_to_ms_valid1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            es_ms_bus_r0 <= '0;
            exe_exc_bus_r0 <= '0;
            es_flush_r0 <= 1'b0;
            es_ms_bus_r1 <= '0;
            exe_exc_bus_r1 <= '0;
            es_flush_r1 <= 1'b0;
        end else begin
            if (es_to_ms_valid0 && ms_allowin0) begin
                es_ms_bus_r0 <= es_to_ms_bus0;
                exe_exc_bus_r0 <= exe_exc_bus;
                es_flush_r0 <= es_flush0;
            end
            if (es_to_ms_valid1 && ms_allowin1) begin
                es_ms_bus_r1 <= es_to_ms_bus1;
                exe_exc_bus_r1 <= exe_exc_bus;
                es_flush_r1 <= es_flush1;
            end
        end
    end
    assign ms_flush0 = rst_n && es_flush_r0;
    assign ms_flush1 = rst_n && es_flush_r1;

    //解包
    logic [31:0] mem_pc0;
    logic [31:0] exe_result0;
    logic [5:0] load_inst0;
    logic [4:0] rd_addr0;
    logic regfile_wen0_int;
    logic reg_fpu_wen0_int;
    logic [1:0] wb_sel0;
    logic csr_wen0;
    logic [11:0] csr_addr0;
    logic [31:0] csr_data0;
    assign {
        mem_pc0,
        exe_result0,
        load_inst0,
        rd_addr0,
        regfile_wen0_int,
        reg_fpu_wen0_int,
        wb_sel0,
        csr_wen0,
        csr_addr0,
        csr_data0
    } = es_ms_bus_r0;

    logic [31:0] mem_pc1;
    logic [31:0] exe_result1;
    logic [5:0] load_inst1;
    logic [4:0] rd_addr1;
    logic regfile_wen1_int;
    logic reg_fpu_wen1_int;
    logic [1:0] wb_sel1;
    logic csr_wen1;
    logic [11:0] csr_addr1;
    logic [31:0] csr_data1;
    assign {
        mem_pc1,
        exe_result1,
        load_inst1,
        rd_addr1,
        regfile_wen1_int,
        reg_fpu_wen1_int,
        wb_sel1,
        csr_wen1,
        csr_addr1,
        csr_data1
    } = es_ms_bus_r1;

    // 确定哪个通道是有效的 load 指令
    logic ms_is_load0;
    logic ms_is_load1;
    assign ms_is_load0 = ms_valid0 && |load_inst0[5:1] && !load_inst0[0];
    assign ms_is_load1 = ms_valid1 && |load_inst1[5:1] && !load_inst1[0];

    logic [1:0] data_offest;
    logic [5:0] load_inst_active;
    assign data_offest = ms_is_load1 ? exe_result1[1:0] : exe_result0[1:0];
    assign load_inst_active = ms_is_load1 ? load_inst1 : load_inst0;

    logic [31:0] load_data;
    logic load_lb;
    logic load_lh;
    logic load_lw;
    logic load_lbu;
    logic load_lhu;

    assign load_lb  = (load_inst_active == `LB);
    assign load_lh  = (load_inst_active == `LH);
    assign load_lw  = (load_inst_active == `LW);
    assign load_lbu = (load_inst_active == `LBU);
    assign load_lhu = (load_inst_active == `LHU);

    logic [7:0]  load_byte;
    logic [15:0] load_half;

    always_comb begin
        unique case (data_offest)
            2'b00:  load_byte = dmem_rdata[7:0];
            2'b01:  load_byte = dmem_rdata[15:8];
            2'b10:  load_byte = dmem_rdata[23:16];
            default: load_byte = dmem_rdata[31:24];
        endcase
    end

    always_comb begin
        unique case (data_offest[1])
            1'b0:    load_half = dmem_rdata[15:0];
            default: load_half = dmem_rdata[31:16];
        endcase
    end

    always_comb begin
        load_data = dmem_rdata;
        unique case (1'b1)
            load_lb: begin
                load_data = {{24{load_byte[7]}}, load_byte};
            end
            load_lbu: begin
                load_data = {24'b0, load_byte};
            end
            load_lh: begin
                load_data = {{16{load_half[15]}}, load_half};
            end
            load_lhu: begin
                load_data = {16'b0, load_half};
            end
            default: begin
                load_data = dmem_rdata;
            end
        endcase
    end

    // 结果选择与前递打包
    assign mem_result0 = ({32{wb_sel0[1]}} & exe_result0) |
                         ({32{~wb_sel0[1]}} & load_data);
    assign mem_result1 = ({32{wb_sel1[1]}} & exe_result1) |
                         ({32{~wb_sel1[1]}} & load_data);

    assign mem_regfile_wen0 = regfile_wen0_int && !ms_flush0 && !exception_flag;
    assign mem_reg_fpu_wen0 = reg_fpu_wen0_int && !ms_flush0 && !exception_flag;
    assign mem_fwd_bus0 = {rd_addr0, mem_regfile_wen0, mem_reg_fpu_wen0, ms_valid0};

    assign mem_regfile_wen1 = regfile_wen1_int && !ms_flush1 && !exception_flag;
    assign mem_reg_fpu_wen1 = reg_fpu_wen1_int && !ms_flush1 && !exception_flag;
    assign mem_fwd_bus1 = {rd_addr1, mem_regfile_wen1, mem_reg_fpu_wen1, ms_valid1};

    assign ms_to_ws_bus0 = {
        mem_pc0,
        mem_result0,
        rd_addr0,
        mem_regfile_wen0,
        mem_reg_fpu_wen0
    };
    assign ms_to_ws_bus1 = {
        mem_pc1,
        mem_result1,
        rd_addr1,
        mem_regfile_wen1,
        mem_reg_fpu_wen1
    };

    // 异常与 CSR 逻辑
    logic [32:0] br_bus0;
    logic [6:0] exc_code0;
    logic [31:0] exc_mtval0;
    assign {
        br_bus0,
        exc_code0,
        exc_mtval0
    } = exe_exc_bus_r0;
    logic br_taken0;
    logic [31:0] br_target0;
    assign br_taken0 = br_bus0[32];
    assign br_target0 = br_bus0[31:0];

    logic [32:0] br_bus1;
    logic [6:0] exc_code1;
    logic [31:0] exc_mtval1;
    assign {
        br_bus1,
        exc_code1,
        exc_mtval1
    } = exe_exc_bus_r1;
    logic br_taken1;
    logic [31:0] br_target1;
    assign br_taken1 = br_bus1[32];
    assign br_target1 = br_bus1[31:0];

    logic exception_iam0, exception_iam1;
    logic exception_lam0, exception_lam1;
    logic exception_sam0, exception_sam1;
    logic sync_exception0, sync_exception1;
    logic take_irq0, take_irq1;

    assign exception_iam0 = (br_taken0 && (br_target0[1:0] != 2'b00)) && !ms_flush0;
    assign exception_lam0 = !ms_flush0 &&
                       (((load_inst0 == `LW) && (exe_result0[1:0] != 2'b00)) ||
                        (((load_inst0 == `LH) || (load_inst0 == `LHU)) && exe_result0[0]));
    assign exception_sam0 = !ms_flush0 &&
                       (((load_inst0 == `SW) && (exe_result0[1:0] != 2'b00)) ||
                        ((load_inst0 == `SH) && exe_result0[0]));
    assign sync_exception0 = exception_iam0 || exception_lam0 || exception_sam0 || exc_code0[5];
    assign take_irq0 = ms_valid0 && !ms_flush0 && !sync_exception0 && plic_irq && external_irq_enable;

    assign exception_iam1 = (br_taken1 && (br_target1[1:0] != 2'b00)) && !ms_flush1;
    assign exception_lam1 = !ms_flush1 &&
                       (((load_inst1 == `LW) && (exe_result1[1:0] != 2'b00)) ||
                        (((load_inst1 == `LH) || (load_inst1 == `LHU)) && exe_result1[0]));
    assign exception_sam1 = !ms_flush1 &&
                       (((load_inst1 == `SW) && (exe_result1[1:0] != 2'b00)) ||
                        ((load_inst1 == `SH) && exe_result1[0]));
    assign sync_exception1 = exception_iam1 || exception_lam1 || exception_sam1 || exc_code1[5];
    assign take_irq1 = ms_valid1 && !ms_flush1 && !sync_exception1 && plic_irq && external_irq_enable;

    logic [6:0] exception_code0, exception_code1;
    logic [31:0] exception_mtval0, exception_mtval1;

    assign exception_code0 = ms_flush0 ? `EXC_NONE :
                            exception_iam0 ? `EXC_IAM :
                            exception_lam0 ? `EXC_LAM :
                            exception_sam0 ? `EXC_SAM :
                            take_irq0 ? `PLIC_IRQ_BIT :
                            exc_code0;
    assign exception_mtval0 = ms_flush0 ? 32'b0 :
                            exception_iam0 ? br_target0 :
                            (exception_lam0 || exception_sam0) ? exe_result0 :
                            take_irq0 ? 32'b0 :
                            exc_mtval0;

    assign exception_code1 = ms_flush1 ? `EXC_NONE :
                            exception_iam1 ? `EXC_IAM :
                            exception_lam1 ? `EXC_LAM :
                            exception_sam1 ? `EXC_SAM :
                            take_irq1 ? `PLIC_IRQ_BIT :
                            exc_code1;
    assign exception_mtval1 = ms_flush1 ? 32'b0 :
                            exception_iam1 ? br_target1 :
                            (exception_lam1 || exception_sam1) ? exe_result1 :
                            take_irq1 ? 32'b0 :
                            exc_mtval1;

    // 异常优先级：Lane 0 优先
    assign exception_code = (ms_valid0 && (exception_code0 != `EXC_NONE)) ? exception_code0 :
                            (ms_valid1 && (exception_code1 != `EXC_NONE)) ? exception_code1 :
                            `EXC_NONE;
    assign exception_mtval = (ms_valid0 && (exception_code0 != `EXC_NONE)) ? exception_mtval0 :
                             (ms_valid1 && (exception_code1 != `EXC_NONE)) ? exception_mtval1 :
                             32'b0;

    // CSR 写入
    logic csr_we0, csr_we1;
    assign csr_we0 = csr_wen0 && !ms_flush0 && !exception_code[5];
    assign csr_we1 = csr_wen1 && !ms_flush1 && !exception_code[5];

    assign csr_we = (csr_we0 || csr_we1) && !exception_code[5];
    assign csr_waddr = exception_code[5] ? `CSR_MEPC : (csr_we0 ? csr_addr0 : csr_addr1);
    assign csr_wdata = exception_code[5] ? ((ms_valid0 && exception_code0[5]) ? mem_pc0 : mem_pc1) : (csr_we0 ? csr_data0 : csr_data1);

endmodule
