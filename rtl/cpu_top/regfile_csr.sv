`include "defines.svh"
module regfile_csr (
    input logic clk,
    input logic rst_n,
    //写端口
    input logic csr_wen,
    input logic [11:0] csr_waddr,
    input logic [31:0] csr_wdata,
    //读端口
    input logic [11:0] csr_raddr,
    output logic [31:0] csr_rdata,
    //异常信息接口
    input logic [6:0] exception_code,
    input logic [31:0] exception_mtval,
    //退休与性能事件接口。retire_count预留双发的0/1/2计数。
    input logic [1:0] retire_count,
    input logic branch_event,
    input logic branch_mispredict_event,
    input logic load_use_stall_event,
    input logic execute_stall_event,
    input logic dual_issue_event,
    input logic single_issue_event,
    input logic issue_raw_reject_event,
    input logic issue_waw_reject_event,
    input logic issue_struct_reject_event,
    input logic issue_lsu_pair_event,
    input logic issue_lane1_control_event,
    input logic lsu_conflict_event,
    output logic exception_flag,
    output logic [31:0] exception_addr,
    output logic external_irq_enable
);

    logic [31:0] mstatus, misa, mtvec, mepc, mcause, mhartid, mie, mip, mtval, mvendorid, marchid, mimpid, mscratch;
    logic mret_flag;
    logic external_irq_flag;
    logic prev_exception_flag;
    assign mret_flag = exception_code == 7'b100_0000; //仅当异常代码为MRET指令引起的异常时mret_flag才为1
    assign external_irq_flag = exception_code == `PLIC_IRQ_BIT;
    logic [31:0] cycle;
    logic [31:0] instret;
    logic perf_enable;
    logic perf_clear;
    logic [31:0] perf_cycle;
    logic [31:0] perf_instret;
    logic [31:0] perf_branch;
    logic [31:0] perf_brmisp;
    logic [31:0] perf_bphit;
    logic [31:0] perf_bpmiss;
    logic [31:0] perf_loaduse;
    logic [31:0] perf_exstall;
    logic [31:0] perf_exception;
    logic [31:0] perf_dual_issue;
    logic [31:0] perf_single_issue;
    logic [31:0] perf_issue_raw;
    logic [31:0] perf_issue_waw;
    logic [31:0] perf_issue_struct;
    logic [31:0] perf_lsu_pair;
    logic [31:0] perf_lane1_control;
    logic [31:0] perf_lsu_conflict;

    assign perf_clear = csr_wen && (csr_waddr == `CSR_PERF_CTRL) && csr_wdata[1];

    //标准cycle/instret始终运行；instret只统计真正退休的指令。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle <= 32'b0;
            instret <= 32'b0;
        end else begin
            cycle <= cycle + 1'b1; //每个时钟周期cycle自增
            instret <= instret + {{30{1'b0}}, retire_count};
        end
    end

    //0x7C0性能计数窗口：bit0使能，bit1写1清零。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            perf_enable <= 1'b1;
            perf_cycle <= 32'b0;
            perf_instret <= 32'b0;
            perf_branch <= 32'b0;
            perf_brmisp <= 32'b0;
            perf_bphit <= 32'b0;
            perf_bpmiss <= 32'b0;
            perf_loaduse <= 32'b0;
            perf_exstall <= 32'b0;
            perf_exception <= 32'b0;
            perf_dual_issue <= 32'b0;
            perf_single_issue <= 32'b0;
            perf_issue_raw <= 32'b0;
            perf_issue_waw <= 32'b0;
            perf_issue_struct <= 32'b0;
            perf_lsu_pair <= 32'b0;
            perf_lane1_control <= 32'b0;
            perf_lsu_conflict <= 32'b0;
        end else begin
            if (csr_wen && (csr_waddr == `CSR_PERF_CTRL)) begin
                perf_enable <= csr_wdata[0];
            end

            if (perf_clear) begin
                perf_cycle <= 32'b0;
                perf_instret <= 32'b0;
                perf_branch <= 32'b0;
                perf_brmisp <= 32'b0;
                perf_bphit <= 32'b0;
                perf_bpmiss <= 32'b0;
                perf_loaduse <= 32'b0;
                perf_exstall <= 32'b0;
                perf_exception <= 32'b0;
                perf_dual_issue <= 32'b0;
                perf_single_issue <= 32'b0;
                perf_issue_raw <= 32'b0;
                perf_issue_waw <= 32'b0;
                perf_issue_struct <= 32'b0;
                perf_lsu_pair <= 32'b0;
                perf_lane1_control <= 32'b0;
                perf_lsu_conflict <= 32'b0;
            end else if (csr_wen && (csr_waddr == `CSR_PERF_CTRL)) begin
                //控制写本身不计入测量窗口。
            end else if (perf_enable) begin
                perf_cycle <= perf_cycle + 1'b1;
                perf_instret <= perf_instret + {{30{1'b0}}, retire_count};
                if (branch_event) begin
                    perf_branch <= perf_branch + 1'b1;
                    if (branch_mispredict_event) begin
                        perf_brmisp <= perf_brmisp + 1'b1;
                        perf_bpmiss <= perf_bpmiss + 1'b1;
                    end else begin
                        perf_bphit <= perf_bphit + 1'b1;
                    end
                end
                if (load_use_stall_event) begin
                    perf_loaduse <= perf_loaduse + 1'b1;
                end
                if (execute_stall_event) begin
                    perf_exstall <= perf_exstall + 1'b1;
                end
                if (exception_code[5]) begin
                    perf_exception <= perf_exception + 1'b1;
                end
                if (dual_issue_event) begin
                    perf_dual_issue <= perf_dual_issue + 1'b1;
                end
                if (single_issue_event) begin
                    perf_single_issue <= perf_single_issue + 1'b1;
                end
                if (issue_raw_reject_event) begin
                    perf_issue_raw <= perf_issue_raw + 1'b1;
                end
                if (issue_waw_reject_event) begin
                    perf_issue_waw <= perf_issue_waw + 1'b1;
                end
                if (issue_struct_reject_event) begin
                    perf_issue_struct <= perf_issue_struct + 1'b1;
                end
                if (issue_lsu_pair_event) begin
                    perf_lsu_pair <= perf_lsu_pair + 1'b1;
                end
                if (issue_lane1_control_event) begin
                    perf_lane1_control <= perf_lane1_control + 1'b1;
                end
                if (lsu_conflict_event) begin
                    perf_lsu_conflict <= perf_lsu_conflict + 1'b1;
                end
            end
        end
    end

    //CSR寄存器写逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mstatus <= 32'b0;
            misa <= 32'b0;
            mtvec <= 32'b0;
            mepc <= 32'b0;
            mcause <= 32'b0;
            mhartid <= 32'b0;
            mie <= 32'b0;
            mip <= 32'b0;
            mtval <= 32'b0;
            mvendorid <= 32'b0;
            marchid <= 32'b0;
            mimpid <= 32'b0;
            mscratch <= 32'b0;
        end else if (csr_wen) begin
            case (csr_waddr)
                `CSR_MSTATUS: mstatus <= csr_wdata;
                `CSR_MISA: misa <= csr_wdata;
                `CSR_MTVEC: mtvec <= csr_wdata;
                `CSR_MEPC: mepc <= csr_wdata;
                `CSR_MCAUSE: mcause <= csr_wdata;
                `CSR_MHARTID: mhartid <= csr_wdata;
                `CSR_MIE: mie <= csr_wdata;
                `CSR_MIP: mip <= csr_wdata;
                `CSR_MTVAL: mtval <= csr_wdata;
                `CSR_MVENDORID: mvendorid <= csr_wdata;
                `CSR_MARCHID: marchid <= csr_wdata;
                `CSR_MIMPID: mimpid <= csr_wdata;
                `CSR_MSCRATCH: mscratch <= csr_wdata;
                default: ;
            endcase
        end else if (exception_code[5]) begin
            mepc <= csr_wdata; //当发生异常时将异常发生的指令地址写入mepc寄存器
            mcause <= external_irq_flag ? {1'b1, 31'd11} : {27'b0, exception_code[4:0]}; //外部中断按RISC-V语义置mcause[31]
            mtval <= external_irq_flag ? 32'b0 : exception_mtval; //中断不携带mtval
            mstatus[7] <= mstatus[3]; // trap入口：MPIE保存进入trap前的MIE
            mstatus[3] <= 1'b0; // trap入口：关闭MIE
        end else if (mret_flag) begin
            mstatus [3] <= mstatus[7]; //将mstatus寄存器中的MIE位恢复到MIE位之前的值
            mstatus [7] <= 1'b1; //将mstatus寄存器中的MIE位设置为1，允许中断
        end
    end

    //CSR寄存器读逻辑
    always_comb begin
        if (csr_raddr == csr_waddr && csr_wen) begin
            // 如果当前正在写入某个CSR寄存器，并且读地址与写地址相同，则直接返回写入的数据，避免读写冲突
            csr_rdata = csr_wdata;
        end else begin
        case (csr_raddr)
            `CSR_MSTATUS: csr_rdata = mstatus;
            `CSR_MISA: csr_rdata = misa;
            `CSR_MTVEC: csr_rdata = mtvec;
            `CSR_MEPC: csr_rdata = mepc;
            `CSR_MCAUSE: csr_rdata = mcause;
            `CSR_MHARTID: csr_rdata = mhartid;
            `CSR_MIE: csr_rdata = mie;
            `CSR_MIP: csr_rdata = mip;
            `CSR_MTVAL: csr_rdata = mtval;
            `CSR_MVENDORID: csr_rdata = mvendorid;
            `CSR_MARCHID: csr_rdata = marchid;
            `CSR_MIMPID: csr_rdata = mimpid;
            `CSR_MSCRATCH: csr_rdata = mscratch;
            `CSR_CYCLE: csr_rdata = cycle;
            `CSR_INSTRET: csr_rdata = instret;
            `CSR_PERF_CTRL: csr_rdata = {31'b0, perf_enable};
            `CSR_PERF_CYCLE: csr_rdata = perf_cycle;
            `CSR_PERF_INSTRET: csr_rdata = perf_instret;
            `CSR_PERF_BRANCH: csr_rdata = perf_branch;
            `CSR_PERF_BRMISP: csr_rdata = perf_brmisp;
            `CSR_PERF_BPHIT: csr_rdata = perf_bphit;
            `CSR_PERF_BPMISS: csr_rdata = perf_bpmiss;
            `CSR_PERF_LOADUSE: csr_rdata = perf_loaduse;
            `CSR_PERF_EXSTALL: csr_rdata = perf_exstall;
            `CSR_PERF_EXCEPTION: csr_rdata = perf_exception;
            `CSR_PERF_DUAL_ISSUE: csr_rdata = perf_dual_issue;
            `CSR_PERF_SINGLE_ISSUE: csr_rdata = perf_single_issue;
            `CSR_PERF_ISSUE_RAW: csr_rdata = perf_issue_raw;
            `CSR_PERF_ISSUE_WAW: csr_rdata = perf_issue_waw;
            `CSR_PERF_ISSUE_STRUCT: csr_rdata = perf_issue_struct;
            `CSR_PERF_LSU_PAIR: csr_rdata = perf_lsu_pair;
            `CSR_PERF_LANE1_CTRL: csr_rdata = perf_lane1_control;
            `CSR_PERF_LSU_CONFLICT: csr_rdata = perf_lsu_conflict;
            default: csr_rdata = 32'b0;
        endcase
        end
    end

    //异常标志和异常地址逻辑
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            prev_exception_flag <= 1'b0;
        end else if (exception_code[5]) begin
            prev_exception_flag <= 1'b1; //当发生异常时将prev_exception_flag置为1
        end else if (mret_flag) begin
            prev_exception_flag <= 1'b0; //当执行MRET指令时将prev_exception_flag清零
        end
    end
    logic mret_jmp_flag;
    assign mret_jmp_flag = mret_flag && prev_exception_flag; //仅当mret_flag为1且之前发生过异常时mret_jmp_flag才为1
    assign external_irq_enable = mstatus[3] && mie[11]; //MIE与MEIE同时有效时才响应PLIC外部中断
    assign exception_flag = exception_code[5] || mret_jmp_flag;
    assign exception_addr = mret_jmp_flag ? {mepc[31:2], 2'b0} : mtvec; //当mret_jmp_flag为1时异常地址为mepc，否则为mtvec

endmodule
