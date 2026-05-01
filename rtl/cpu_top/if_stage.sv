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

    localparam BP_INDEX_WIDTH = 4;
    localparam BP_ENTRIES = 1 << BP_INDEX_WIDTH;
    localparam BP_TAG_WIDTH = `ADDR_WIDTH - BP_INDEX_WIDTH - 2;

    logic bp_valid [BP_ENTRIES-1:0];
    logic bp_taken [BP_ENTRIES-1:0];
    logic [BP_TAG_WIDTH-1:0] bp_tag [BP_ENTRIES-1:0];
    logic [`ADDR_WIDTH-1:0] bp_target [BP_ENTRIES-1:0];

    logic [BP_INDEX_WIDTH-1:0] bp_lookup_index;
    logic [BP_TAG_WIDTH-1:0] bp_lookup_tag;
    logic bp_hit;
    logic bp_pred_taken;
    logic [`ADDR_WIDTH-1:0] bp_pred_target;

    assign bp_lookup_index = fs_out_pc[BP_INDEX_WIDTH+1:2];
    assign bp_lookup_tag = fs_out_pc[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign bp_hit = bp_valid[bp_lookup_index] && (bp_tag[bp_lookup_index] == bp_lookup_tag);
    assign bp_pred_taken = bp_hit && bp_taken[bp_lookup_index];
    assign bp_pred_target = bp_target[bp_lookup_index];

    assign seq_pc = fs_out_pc + 4;
    assign next_pc = exception_flag ? exception_addr :
                     br_taken_reg ? br_target_reg :
                     bp_pred_taken ? bp_pred_target :
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
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            br_taken_reg <= 1'b0;
            br_target_reg <= 32'b0;
        end else if (fs_allowin) begin
            br_taken_reg <= br_taken;
            br_target_reg <= br_target;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i = 0; i < BP_ENTRIES; i = i + 1) begin
                bp_valid[i] <= 1'b0;
                bp_taken[i] <= 1'b0;
                bp_tag[i] <= '0;
                bp_target[i] <= '0;
            end
        end else if (bp_update_valid && !bp_update_is_jalr) begin
            bp_valid[bp_update_pc[BP_INDEX_WIDTH+1:2]] <= 1'b1;
            bp_taken[bp_update_pc[BP_INDEX_WIDTH+1:2]] <= bp_update_taken;
            bp_tag[bp_update_pc[BP_INDEX_WIDTH+1:2]] <= bp_update_pc[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
            bp_target[bp_update_pc[BP_INDEX_WIDTH+1:2]] <= bp_update_target;
        end
    end

    assign pc_out = next_pc;
    assign fs_out_inst = (br_taken || br_taken_reg) ? `NOP_INST : inst_in; // 分支指令在分支预测失败时用NOP占位
    assign inst_ren = fs_allowin;
    assign fs_out_pc = fs_pc;
    assign fs_to_ds_bus = {fs_out_inst, fs_out_pc, (bp_pred_taken && !br_taken && !br_taken_reg && !exception_flag), bp_pred_target};

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_out_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000; 
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_out_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule
