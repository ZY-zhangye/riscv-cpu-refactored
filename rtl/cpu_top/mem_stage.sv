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
    output logic [31:0] exception_mtval
);

    logic [`ES_MS_WIDTH-1:0] es_ms_bus_r;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus_r;
    logic ms_ready_go;
    logic es_flush_r;
    logic ms_flush;
    assign ms_ready_go = 1'b1;
    assign ms_allowin = !ms_valid || ms_ready_go && ws_allowin;
    assign ms_to_ws_valid = ms_valid && ms_ready_go;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_valid <= 1'b0;
        end else if (ms_allowin) begin
            ms_valid <= es_to_ms_valid;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            es_ms_bus_r <= '0;
            exe_exc_bus_r <= '0;
            es_flush_r <= 1'b0;
        end else if (es_to_ms_valid && ms_allowin) begin
            es_ms_bus_r <= es_to_ms_bus;
            exe_exc_bus_r <= exe_exc_bus;
            es_flush_r <= es_flush;
        end
    end
    assign ms_flush = rst_n && es_flush_r;

    //解包
    logic [31:0] mem_pc;
    logic [31:0] exe_result;
    logic [5:0] load_inst;
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic reg_fpu_wen;
    logic [1:0] wb_sel;
    logic csr_wen;
    logic [11:0] csr_addr;
    logic [31:0] csr_data;
    assign {
        mem_pc,
        exe_result,
        load_inst,
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
    assign mem_regfile_wen = regfile_wen && !ms_flush && !exception_flag;
    assign mem_reg_fpu_wen = reg_fpu_wen && !ms_flush && !exception_flag;
    assign csr_we = csr_wen & ~ms_flush & ~exception_code[5];
    assign csr_waddr = csr_addr;
    assign csr_wdata = exception_code[5] ? mem_pc : csr_data; //当发生异常时将当前指令地址写入CSR寄存器，而不是正常的CSR写数据
    assign ms_to_ws_bus = {
        mem_pc,
        mem_result,
        rd_addr,
        mem_regfile_wen,
        mem_reg_fpu_wen
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
    assign exception_iam = (br_taken && (br_target[1:0] != 2'b00)) && !ms_flush;
    logic is_word_access;
    logic is_half_access;
    assign is_word_access = (load_inst == `LW) || (load_inst == `SW);
    assign is_half_access = (load_inst == `LH) || (load_inst == `LHU) || (load_inst == `SH);
    assign exception_lam = !ms_flush &&
                       (((load_inst == `LW) && (data_offest != 2'b00)) ||
                        (((load_inst == `LH) || (load_inst == `LHU)) && data_offest[0]));
    assign exception_sam = !ms_flush &&
                       (((load_inst == `SW) && (data_offest != 2'b00)) ||
                        ((load_inst == `SH) && data_offest[0]));
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

endmodule
