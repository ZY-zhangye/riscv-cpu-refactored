`include "defines.svh"
//双发射改造
module regfiles (
    input logic clk,
    input logic rst_n,
    //写端口
    input logic regfile_wen,
    input logic regfile_wen1,
    input logic [4:0] regfile_waddr,
    input logic [4:0] regfile_waddr1,
    input logic [31:0] regfile_wdata,
    input logic [31:0] regfile_wdata1,
    //读端口1
    input logic [4:0] regfile_raddr1,
    input logic [4:0] regfile_raddr11,
    output logic [31:0] regfile_rdata1,
    output logic [31:0] regfile_rdata11,
    //读端口2
    input logic [4:0] regfile_raddr2,
    input logic [4:0] regfile_raddr21,
    output logic [31:0] regfile_rdata2,
    output logic [31:0] regfile_rdata21
    `ifdef DEBUG_EN
    ,
    //debug接口
    output logic [31:0] debug_data
    `endif
);

    logic [31:0] regfile [31:0];
    task clean_regfile;
        integer i;
        for (i = 0; i < 32; i++) begin
            regfile[i] = 32'b0;
        end
    endtask
    //写寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clean_regfile();
        end else begin
            if (regfile_wen && regfile_waddr != 5'b0) 
                regfile[regfile_waddr] <= regfile_wdata;
            if (regfile_wen1 && regfile_waddr1 != 5'b0) 
                regfile[regfile_waddr1] <= regfile_wdata1;
        end
    end
    //读寄存器（含双WB端口写回数据前递）
    assign regfile_rdata1 = (regfile_raddr1 != 5'b0) ?
        ((regfile_wen && regfile_waddr == regfile_raddr1) ? regfile_wdata :
         (regfile_wen1 && regfile_waddr1 == regfile_raddr1) ? regfile_wdata1 :
         regfile[regfile_raddr1]) : 32'b0;
    assign regfile_rdata11 = (regfile_raddr11 != 5'b0) ?
        ((regfile_wen && regfile_waddr == regfile_raddr11) ? regfile_wdata :
         (regfile_wen1 && regfile_waddr1 == regfile_raddr11) ? regfile_wdata1 :
         regfile[regfile_raddr11]) : 32'b0;
    assign regfile_rdata2 = (regfile_raddr2 != 5'b0) ?
        ((regfile_wen && regfile_waddr == regfile_raddr2) ? regfile_wdata :
         (regfile_wen1 && regfile_waddr1 == regfile_raddr2) ? regfile_wdata1 :
         regfile[regfile_raddr2]) : 32'b0;
    assign regfile_rdata21 = (regfile_raddr21 != 5'b0) ?
        ((regfile_wen && regfile_waddr == regfile_raddr21) ? regfile_wdata :
         (regfile_wen1 && regfile_waddr1 == regfile_raddr21) ? regfile_wdata1 :
         regfile[regfile_raddr21]) : 32'b0;
    `ifdef DEBUG_EN
    assign debug_data = regfile[3];
    `endif


endmodule