`include "defines.svh"
module if_stage (
    input logic clk,
    input logic rst_n,
    //取指端口
    output logic [`ADDR_WIDTH-1:0] pc_out,
    output logic inst_ren,
    input logic [`DATA_WIDTH-1:0] inst_in,
    //与译码阶段的数据接口
    input logic ds_allowin,
    output logic fs_to_ds_valid,
    output logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    //分支跳转接口
    input logic br_taken,
    input logic [`ADDR_WIDTH-1:0] br_target,
    //异常包接口
    output logic [`EXC_WIDTH-1:0] fs_exc_bus,
    //异常跳转接口
    input logic exception_flag,
    input logic [`ADDR_WIDTH-1:0] exception_addr
);

    logic [`ADDR_WIDTH-1:0] seq_pc;
    logic [`ADDR_WIDTH-1:0] next_pc;
    logic [`ADDR_WIDTH-1:0] fs_out_pc;
    logic [`DATA_WIDTH-1:0] fs_out_inst;
    logic [31:0] fs_pc;
    assign seq_pc = fs_out_pc + 4;
    assign next_pc = exception_flag ? exception_addr :
                     br_taken ? br_target :
                     seq_pc;
    logic fs_valid;
    logic fs_ready_go;
    logic fs_allowin;
    assign fs_ready_go = 1'b1;
    assign fs_allowin = !fs_valid || fs_ready_go && ds_allowin;
    assign fs_to_ds_valid = fs_valid && fs_ready_go;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_valid <= 1'b0;
        end else if (fs_allowin) begin
            fs_valid <= 1'b1;
        end
        if (!rst_n) begin
            fs_pc <= `PC_START - 4;
        end else if (fs_allowin) begin
            fs_pc <= next_pc;
        end
    end
    assign pc_out = next_pc;
    assign fs_out_inst = br_taken ? `NOP_INST : inst_in; // 分支指令在分支预测失败时用NOP占位
    assign inst_ren = fs_allowin;
    assign fs_out_pc = fs_pc;
    assign fs_to_ds_bus = {fs_out_inst, fs_out_pc};

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_out_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000; 
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_out_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule