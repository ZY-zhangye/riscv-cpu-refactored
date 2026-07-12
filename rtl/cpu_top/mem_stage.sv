`include "defines.svh"
module mem_stage (
    input logic clk,
    input logic rst_n,
    //来自执行阶段的信息
    input logic es_flush,
    input logic [`ES_MS_WIDTH-1:0] es_to_ms_bus,
    //送到写回阶段的信息
    output logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus,
    //握手信号
    input logic es_to_ms_valid,
    output logic ms_to_ws_valid,
    output logic ms_allowin,
    input logic ws_allowin,
    output logic ms_valid,
    //数据存储器接口
    input logic [31:0] dmem_rdata,
    input logic commit_kill,
    output logic store_commit_valid,
    output logic [31:0] store_commit_pc,
    output logic [31:0] store_commit_addr,
    output logic [3:0] store_commit_wen,
    output logic [31:0] store_commit_wdata,
    //数据前递接口
    output logic [4:0] mem_dst_addr,
    output logic mem_regfile_wen,
    output logic mem_reg_fpu_wen,
    output logic [31:0] mem_result,
    //异常信息接口
    input logic exception_flag,
    input logic [`EXE_EXC_BUS-1:0] exe_exc_bus,
    //plic接口
    input logic plic_irq,
    input logic external_irq_enable,
    //CSR接口
    output logic csr_we,
    output logic [11:0] csr_waddr,
    output logic [31:0] csr_wdata,
    output logic [6:0] exception_code,
    output logic [31:0] exception_mtval,
    //未来双发可直接扩展为0/1/2，本阶段只会输出0或1
    output logic [1:0] retire_count
);

    logic [`ES_MS_WIDTH-1:0] es_ms_bus_r;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus_r;
    logic ms_ready_go;
    logic ms_core_allowin;
    logic ms_allowin_r;
    logic ms_in_fire;
    logic ms_skid_valid;
    logic ms_skid_valid_next;
    logic [`ES_MS_WIDTH-1:0] es_ms_bus_skid;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus_skid;
    logic es_flush_skid;
    logic exception_iam_r;
    logic exception_lam_r;
    logic exception_sam_r;
    logic exception_iam_skid;
    logic exception_lam_skid;
    logic exception_sam_skid;
    logic es_flush_r;
    logic ms_flush;

    // Decode alignment exceptions from the incoming EX/MEM packet once, then
    // carry the narrow results with the packet. This prevents the registered
    // MEM payload store bit from driving the global exception/flush cone.
    logic [31:0] in_exe_result;
    logic [5:0] in_load_inst;
    logic [31:0] in_mem_pc;
    logic [31:0] in_mem_inst;
    logic [3:0] in_pending_store_wen;
    logic [31:0] in_pending_store_wdata;
    logic [4:0] in_rd_addr;
    logic in_regfile_wen;
    logic in_reg_fpu_wen;
    logic [1:0] in_wb_sel;
    logic in_csr_wen;
    logic [11:0] in_csr_addr;
    logic [31:0] in_csr_data;
    logic in_br_taken;
    logic [31:0] in_br_target;
    logic in_exception_iam;
    logic in_exception_lam;
    logic in_exception_sam;
    assign {
        in_mem_pc,
        in_mem_inst,
        in_exe_result,
        in_load_inst,
        in_pending_store_wen,
        in_pending_store_wdata,
        in_rd_addr,
        in_regfile_wen,
        in_reg_fpu_wen,
        in_wb_sel,
        in_csr_wen,
        in_csr_addr,
        in_csr_data
    } = es_to_ms_bus;
    assign in_br_taken = exe_exc_bus[`EXE_EXC_BUS-1];
    assign in_br_target = exe_exc_bus[`EXE_EXC_BUS-2 -: 32];
    assign in_exception_iam = in_br_taken && (in_br_target[1:0] != 2'b00);
    assign in_exception_lam =
        (((in_load_inst == `LW) && (in_exe_result[1:0] != 2'b00)) ||
         (((in_load_inst == `LH) || (in_load_inst == `LHU)) &&
          in_exe_result[0]));
    assign in_exception_sam =
        (((in_load_inst == `SW) && (in_exe_result[1:0] != 2'b00)) ||
         ((in_load_inst == `SH) && in_exe_result[0]));
    assign ms_ready_go = 1'b1;
    assign ms_core_allowin = !ms_valid || ms_ready_go && ws_allowin;
    assign ms_allowin = ms_allowin_r;
    assign ms_to_ws_valid = ms_valid && ms_ready_go && !ms_flush &&
                            !exception_code[5] && !commit_kill;
    assign ms_in_fire = es_to_ms_valid && ms_allowin;

    always_comb begin
        ms_skid_valid_next = ms_skid_valid;
        if (exception_flag) begin
            ms_skid_valid_next = 1'b0;
        end else if (ms_core_allowin) begin
            ms_skid_valid_next = 1'b0;
        end else if (ms_in_fire && !ms_skid_valid) begin
            ms_skid_valid_next = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ms_valid <= 1'b0;
            ms_allowin_r <= 1'b1;
            ms_skid_valid <= 1'b0;
            es_ms_bus_r <= '0;
            exe_exc_bus_r <= '0;
            es_flush_r <= 1'b0;
            es_ms_bus_skid <= '0;
            exe_exc_bus_skid <= '0;
            es_flush_skid <= 1'b0;
            exception_iam_r <= 1'b0;
            exception_lam_r <= 1'b0;
            exception_sam_r <= 1'b0;
            exception_iam_skid <= 1'b0;
            exception_lam_skid <= 1'b0;
            exception_sam_skid <= 1'b0;
        end else if (exception_flag) begin
            // The registered trap belongs to an older MEM instruction. Drop
            // any younger resident/skid packet admitted on the detection edge.
            ms_valid <= 1'b0;
            ms_allowin_r <= 1'b1;
            ms_skid_valid <= 1'b0;
        end else begin
            ms_skid_valid <= ms_skid_valid_next;
            ms_allowin_r <= !ms_skid_valid_next;

            if (ms_core_allowin) begin
                if (ms_skid_valid) begin
                    ms_valid <= 1'b1;
                    es_ms_bus_r <= es_ms_bus_skid;
                    exe_exc_bus_r <= exe_exc_bus_skid;
                    es_flush_r <= es_flush_skid;
                    exception_iam_r <= exception_iam_skid;
                    exception_lam_r <= exception_lam_skid;
                    exception_sam_r <= exception_sam_skid;
                end else begin
                    ms_valid <= ms_in_fire;
                    if (ms_in_fire) begin
                        es_ms_bus_r <= es_to_ms_bus;
                        exe_exc_bus_r <= exe_exc_bus;
                        es_flush_r <= es_flush;
                        exception_iam_r <= in_exception_iam;
                        exception_lam_r <= in_exception_lam;
                        exception_sam_r <= in_exception_sam;
                    end
                end
            end else if (ms_in_fire && !ms_skid_valid) begin
                es_ms_bus_skid <= es_to_ms_bus;
                exe_exc_bus_skid <= exe_exc_bus;
                es_flush_skid <= es_flush;
                exception_iam_skid <= in_exception_iam;
                exception_lam_skid <= in_exception_lam;
                exception_sam_skid <= in_exception_sam;
            end
        end
    end
    assign ms_flush = rst_n && (es_flush_r || exception_flag);

    //解包
    logic [31:0] mem_pc;
    logic [31:0] mem_inst;
    logic [31:0] exe_result;
    logic [5:0] load_inst;
    logic [3:0] pending_store_wen;
    logic [31:0] pending_store_wdata;
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic reg_fpu_wen;
    logic [1:0] wb_sel;
    logic csr_wen;
    logic [11:0] csr_addr;
    logic [31:0] csr_data;
    assign {
        mem_pc,
        mem_inst,
        exe_result,
        load_inst,
        pending_store_wen,
        pending_store_wdata,
        rd_addr,
        regfile_wen,
        reg_fpu_wen,
        wb_sel,
        csr_wen,
        csr_addr,
        csr_data
    } = es_ms_bus_r;

    //读数据选择（显式MUX，减少可变移位逻辑）
    logic [1:0] data_offest;
logic [31:0] load_data;

logic load_lb;
logic load_lh;
logic load_lw;
logic load_lbu;
logic load_lhu;

assign data_offest = exe_result[1:0];

assign load_lb  = (load_inst == `LB);
assign load_lh  = (load_inst == `LH);
assign load_lw  = (load_inst == `LW);
assign load_lbu = (load_inst == `LBU);
assign load_lhu = (load_inst == `LHU);

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
    
    //结果选择（case减少级联三目）
    assign mem_result = ({32{wb_sel[1]}} & exe_result) |
                         ({32{~wb_sel[1]}} & load_data);
    assign mem_dst_addr = rd_addr;
    assign mem_regfile_wen = ms_valid && regfile_wen && !ms_flush &&
                             !exception_code[5] && !commit_kill;
    assign mem_reg_fpu_wen = ms_valid && reg_fpu_wen && !ms_flush &&
                             !exception_code[5] && !commit_kill;
    assign csr_we = ms_valid && csr_wen && !ms_flush &&
                    !exception_code[5] && !commit_kill;
    assign csr_waddr = csr_addr;
    assign csr_wdata = exception_code[5] ? mem_pc : csr_data; //当发生异常时将当前指令地址写入CSR寄存器，而不是正常的CSR写数据
    assign ms_to_ws_bus = {
        mem_pc,
        mem_inst,
        mem_result,
        rd_addr,
        mem_regfile_wen,
        mem_reg_fpu_wen,
        csr_we,
        csr_waddr,
        csr_wdata
    };
    //异常相关信息
    //解包异常信息包
    logic [32:0] br_bus;
    logic [6:0] exc_code;
    logic [31:0] exc_mtval;
    assign {
        br_bus,
        exc_code,
        exc_mtval
    } = exe_exc_bus_r;
    logic br_taken;
    logic [31:0] br_target;
    assign br_taken = br_bus[32];
    assign br_target = br_bus[31:0];

    //处理来自exe阶段的可能引起异常的数据
    logic exception_iam;
    logic exception_lam;
    logic exception_sam;
    logic sync_exception;
    logic take_irq;
    assign exception_iam = ms_valid && exception_iam_r && !ms_flush;
    logic is_word_access;
    logic is_half_access;
    assign is_word_access = (load_inst == `LW) || (load_inst == `SW);
    assign is_half_access = (load_inst == `LH) || (load_inst == `LHU) || (load_inst == `SH);
    assign exception_lam = ms_valid && exception_lam_r && !ms_flush;
    assign exception_sam = ms_valid && exception_sam_r && !ms_flush;
    assign sync_exception = exception_iam || exception_lam || exception_sam || exc_code[5];
    assign take_irq = ms_valid && !ms_flush && !sync_exception && plic_irq && external_irq_enable;
    assign exception_code = ms_flush ? `EXC_NONE :
                            exception_iam ? `EXC_IAM :
                            exception_lam ? `EXC_LAM :
                            exception_sam ? `EXC_SAM :
                            take_irq ? `PLIC_IRQ_BIT :
                            exc_code;
    assign exception_mtval = ms_flush ? 32'b0 :
                            exception_iam ? br_target :
                            (exception_lam || exception_sam) ? exe_result :
                            take_irq ? 32'b0 :
                            exc_mtval;
    assign store_commit_valid = ms_valid && ms_ready_go && ws_allowin &&
                                !ms_flush && !commit_kill &&
                                !exception_code[5] &&
                                (pending_store_wen != 4'b0000);
    assign store_commit_pc = mem_pc;
    assign store_commit_addr = exe_result;
    assign store_commit_wen = store_commit_valid ? pending_store_wen : 4'b0000;
    assign store_commit_wdata = pending_store_wdata;
    assign retire_count = {1'b0, ms_to_ws_valid};

endmodule
