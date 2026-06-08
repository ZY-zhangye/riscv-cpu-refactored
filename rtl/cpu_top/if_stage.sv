`include "defines.svh"
module if_stage (
    input logic clk,
    input logic rst_n,
    //取指端口0
    output logic [`ADDR_WIDTH-1:0] pc_out,
    output logic inst_ren,
    input logic [`DATA_WIDTH-1:0] inst_in,
    //取指端口1（预留）
    output logic [`ADDR_WIDTH-1:0] pc_out1,
    output logic inst_ren1,
    input logic [`DATA_WIDTH-1:0] inst_in1,
    //与issue阶段的数据接口
    input logic ds_allowin,
    output logic fs_to_ds_valid,
    output logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    output logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus1,
    //分支跳转接口
    input logic br_taken,
    input logic [`ADDR_WIDTH-1:0] br_target,
    //分支预测器更新接口
    input logic bp_update_valid,
    input logic [`ADDR_WIDTH-1:0] bp_update_pc,
    input logic bp_update_taken,
    input logic [`ADDR_WIDTH-1:0] bp_update_target,
    input logic bp_update_is_jalr,
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
    logic br_taken_reg;
    logic [31:0] br_target_reg;
    logic redirect_pending;
    logic [31:0] redirect_pending_target;
    logic fetch_accept;

    logic bp_pred_taken;
    logic [`ADDR_WIDTH-1:0] bp_pred_target;

    branch_predictor u_branch_predictor (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_pc(fs_out_pc),
        .pred_taken(bp_pred_taken),
        .pred_target(bp_pred_target),
        .update_valid(bp_update_valid),
        .update_pc(bp_update_pc),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target),
        .update_is_jalr(bp_update_is_jalr)
    );

    assign seq_pc = fs_pc + 8; // 如果上一周期两条指令都被译码阶段接受，则下一周期取两条指令，否则只取一条
    assign next_pc = exception_flag ? exception_addr :
                     redirect_pending ? redirect_pending_target :
                     br_taken_reg ? br_target_reg :
                     bp_pred_taken ? bp_pred_target :
                     seq_pc;
    logic fs_valid;
    logic fs_ready_go;
    logic fs_allowin;
    assign fs_ready_go = 1'b1;
    assign fs_allowin = !fs_valid || fs_ready_go && ds_allowin;
    assign fs_to_ds_valid = fs_valid && fs_ready_go;
    assign fetch_accept = redirect_pending && fs_allowin;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_valid <= 1'b0;
        end else begin
            if (fs_allowin) 
                fs_valid <= 1'b1;
        end
        if (!rst_n) begin
            fs_pc <= `PC_START - 8;
        end else if (fs_allowin) begin
            fs_pc <= next_pc;
        end
    end


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            redirect_pending <= 1'b0;
            redirect_pending_target <= 32'b0;
        end else if (exception_flag) begin
            redirect_pending <= 1'b1;
            redirect_pending_target <= exception_addr;
        end else if (br_taken) begin
            redirect_pending <= 1'b1;
            redirect_pending_target <= br_target;
        end else if (fetch_accept) begin
            redirect_pending <= 1'b0;
            redirect_pending_target <= 32'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            br_taken_reg <= 1'b0;
            br_target_reg <= 32'b0;
        end else if (fs_allowin) begin
            br_taken_reg <= br_taken;
            br_target_reg <= br_target;
        end
    end

    assign pc_out = next_pc;
    assign fs_out_inst = (br_taken || br_taken_reg || exception_flag || redirect_pending) ? `NOP_INST : inst_in; // 分支指令在分支预测失败时用NOP占位
    assign inst_ren = fs_allowin;
    assign fs_out_pc = fs_pc;
    assign fs_to_ds_bus = {fs_out_inst, fs_out_pc, (bp_pred_taken && !br_taken && !br_taken_reg && !exception_flag && !redirect_pending), bp_pred_target};

    assign pc_out1 = next_pc + 32'd4; // 预留的第二条指令地址
    assign inst_ren1 = fs_allowin;
    assign fs_to_ds_bus1 = {(redirect_pending ? `NOP_INST : inst_in1), fs_pc + 32'd4, 1'b0, 32'b0}; // 预留的第二条指令总线

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_out_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000; 
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_out_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule
