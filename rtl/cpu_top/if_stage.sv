`include "defines.svh"
module if_stage #(
    parameter int BP_INDEX_WIDTH = 6
) (
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
    logic redirect_valid;
    logic [`ADDR_WIDTH-1:0] redirect_target;
    logic redirect_valid_reg;
    logic [`ADDR_WIDTH-1:0] redirect_target_reg;

    logic bp_pred_taken0;
    logic [`ADDR_WIDTH-1:0] bp_pred_target0;
    logic bp_pred_taken1;
    logic [`ADDR_WIDTH-1:0] bp_pred_target1;
    logic fetch_kill;
    logic lane0_fetch_valid;
    logic lane1_fetch_valid;
    logic lane0_pred_valid;
    logic lane1_pred_valid;
    logic selected_pred_valid;
    logic [`ADDR_WIDTH-1:0] selected_pred_target;

    branch_predictor #(
        .INDEX_WIDTH(BP_INDEX_WIDTH)
    ) u_branch_predictor (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_pc0(fs_out_pc),
        .pred_taken0(bp_pred_taken0),
        .pred_target0(bp_pred_target0),
        .lookup_pc1(fs_out_pc + 32'd4),
        .pred_taken1(bp_pred_taken1),
        .pred_target1(bp_pred_target1),
        .update_valid(bp_update_valid),
        .update_pc(bp_update_pc),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target),
        .update_is_jalr(bp_update_is_jalr)
    );

    assign redirect_valid = br_taken;
    assign redirect_target = br_target;
    assign redirect_valid_reg = br_taken_reg;
    assign redirect_target_reg = br_target_reg;

    assign seq_pc = fs_pc + 8; // 如果上一周期两条指令都被译码阶段接受，则下一周期取两条指令，否则只取一条
    assign fetch_kill = redirect_valid || redirect_valid_reg || exception_flag || redirect_pending;
    assign lane0_fetch_valid = !fetch_kill;
    assign lane0_pred_valid = bp_pred_taken0 && lane0_fetch_valid;
    assign lane1_fetch_valid = lane0_fetch_valid && !lane0_pred_valid;
    assign lane1_pred_valid = bp_pred_taken1 && lane1_fetch_valid;
    assign selected_pred_valid = lane0_pred_valid || lane1_pred_valid;
    assign selected_pred_target = lane0_pred_valid ? bp_pred_target0 : bp_pred_target1;
    assign next_pc = exception_flag ? exception_addr :
                     redirect_pending ? redirect_pending_target :
                     redirect_valid_reg ? redirect_target_reg :
                     selected_pred_valid ? selected_pred_target :
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
        end else if (redirect_valid) begin
            redirect_pending <= 1'b1;
            redirect_pending_target <= redirect_target;
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
            br_taken_reg <= redirect_valid;
            br_target_reg <= redirect_target;
        end
    end

    // The instruction RAM is synchronous: pc_out requests the next fetch pair,
    // while fs_pc tracks the address of the instruction data returning now.
    assign pc_out = next_pc;
    assign fs_out_inst = lane0_fetch_valid ? inst_in : `NOP_INST; // 分支指令在分支预测失败时用NOP占位
    assign inst_ren = fs_allowin;
    assign fs_out_pc = fs_pc;
    assign fs_to_ds_bus = {fs_out_inst, fs_out_pc, lane0_pred_valid, bp_pred_target0};

    assign pc_out1 = next_pc + 32'd4;
    assign inst_ren1 = fs_allowin;
    assign fs_to_ds_bus1 = {(lane1_fetch_valid ? inst_in1 : `NOP_INST), fs_pc + 32'd4,
                            lane1_pred_valid,
                            bp_pred_target1}; // 预留的第二条指令总线

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_out_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000; 
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_out_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule
