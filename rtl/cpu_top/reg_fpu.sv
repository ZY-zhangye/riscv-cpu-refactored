module reg_fpu (
    input logic clk,
    input logic rst_n,
    //写端口
    input logic reg_fpu_wen,
    input logic [4:0] reg_fpu_waddr,
    input logic [31:0] reg_fpu_wdata,
    //读端口1
    input logic [4:0] reg_fpu_raddr1,
    output logic [31:0] reg_fpu_rdata1,
    //读端口2
    input logic [4:0] reg_fpu_raddr2,
    output logic [31:0] reg_fpu_rdata2,
    //读端口3
    input logic rs3_fpu_ren,
    input logic [4:0] reg_fpu_raddr3,
    output logic [31:0] reg_fpu_rdata3
);

    logic [31:0] reg_fpu [31:0];
    task clean_reg_fpu;
        integer i;
        for (i = 0; i < 32; i++) begin
            reg_fpu[i] = 32'b0;
        end
    endtask
    //写寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clean_reg_fpu();
        end else if (reg_fpu_wen && reg_fpu_waddr != 5'b0) begin
            reg_fpu[reg_fpu_waddr] <= reg_fpu_wdata;
        end
    end
    //读寄存器
    assign reg_fpu_rdata1 = reg_fpu[reg_fpu_raddr1];
    assign reg_fpu_rdata2 = reg_fpu[reg_fpu_raddr2];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_fpu_rdata3 <= 32'b0;
        end else if (rs3_fpu_ren) begin
            reg_fpu_rdata3 <= reg_fpu[reg_fpu_raddr3];
        end else begin
            reg_fpu_rdata3 <= reg_fpu_rdata3;
        end
    end

endmodule
