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
    output logic exception_flag,
    output logic [31:0] exception_addr
);

    logic [31:0] mstatus, misa, mtvec, mepc, mcause, mhartid, mie, mip, mtval, mvendorid, marchid, mimpid, mscratch;
    logic mret_flag;
    logic prev_exception_flag;
    assign mret_flag = exception_code == 7'b100_0000; //仅当异常代码为MRET指令引起的异常时mret_flag才为1

    //CSR寄存器写逻辑
    always_ff @(posedge clk or negedge rst_n) begin
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
            mcause <= {27'b0, exception_code[4:0]}; //将异常代码写入mcause寄存器
            mtval <= exception_mtval; //将异常相关的值写入mtval寄存器
        end else if (mret_flag) begin
            mstatus [3] <= mstatus[7]; //将mstatus寄存器中的MIE位恢复到MIE位之前的值
            mstatus [7] <= 1'b1; //将mstatus寄存器中的MIE位设置为1，允许中断
        end
    end

    //CSR寄存器读逻辑
    always_comb begin
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
            default: csr_rdata = 32'b0;
        endcase
    end

    //异常标志和异常地址逻辑
    always_ff @(posedge clk or negedge rst_n) begin
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
    assign exception_flag = exception_code[5] || mret_jmp_flag;
    assign exception_addr = mret_jmp_flag ? mepc : mtvec; //当mret_jmp_flag为1时异常地址为mepc，否则为mtvec

endmodule