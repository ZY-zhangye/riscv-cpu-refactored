`include "defines.svh"
module regfiles (
    input logic clk,
    input logic rst_n,
    //写端口
    input logic regfile_wen,
    input logic [4:0] regfile_waddr,
    input logic [31:0] regfile_wdata,
    input logic regfile_wen1,
    input logic [4:0] regfile_waddr1,
    input logic [31:0] regfile_wdata1,
    //读端口1
    input logic [4:0] regfile_raddr1,
    output logic [31:0] regfile_rdata1,
    //读端口2
    input logic [4:0] regfile_raddr2,
    output logic [31:0] regfile_rdata2,
    //lane1读端口
    input logic [4:0] regfile_raddr3,
    output logic [31:0] regfile_rdata3,
    input logic [4:0] regfile_raddr4,
    output logic [31:0] regfile_rdata4
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
            if (regfile_wen && regfile_waddr != 5'b0) begin
                regfile[regfile_waddr] <= regfile_wdata;
            end
            if (regfile_wen1 && regfile_waddr1 != 5'b0) begin
                regfile[regfile_waddr1] <= regfile_wdata1;
            end
        end
    end
    //四读端口均包含双WB端口旁路。lane1写口代表较年轻指令，优先级更高。
    function automatic logic [31:0] read_reg(input logic [4:0] raddr);
        begin
            if (raddr == 5'b0) begin
                read_reg = 32'b0;
            end else if (regfile_wen1 && (regfile_waddr1 == raddr)) begin
                read_reg = regfile_wdata1;
            end else if (regfile_wen && (regfile_waddr == raddr)) begin
                read_reg = regfile_wdata;
            end else begin
                read_reg = regfile[raddr];
            end
        end
    endfunction

    assign regfile_rdata1 = read_reg(regfile_raddr1);
    assign regfile_rdata2 = read_reg(regfile_raddr2);
    assign regfile_rdata3 = read_reg(regfile_raddr3);
    assign regfile_rdata4 = read_reg(regfile_raddr4);
    `ifdef DEBUG_EN
    assign debug_data = regfile[3];
    `endif


endmodule
