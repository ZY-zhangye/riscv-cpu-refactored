`include "defines.svh"

module if_stage (
    input logic clk,
    input logic rst_n,
    //取指端口
    output logic [`ADDR_WIDTH-1:0] pc_out,
    output logic inst_ren,
    input logic inst_ready,
    input logic [`DATA_WIDTH-1:0] inst_in,
    input logic inst_valid,
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

    logic [`ADDR_WIDTH-1:0] fetch_pc;
    logic [`ADDR_WIDTH-1:0] fetch_seq_pc;
    logic [`ADDR_WIDTH-1:0] fetch_next_pc;

    logic req_valid;
    logic [`ADDR_WIDTH-1:0] req_pc;
    logic req_pred_taken;
    logic [`ADDR_WIDTH-1:0] req_pred_target;

    logic fs_valid;
    logic [`ADDR_WIDTH-1:0] fs_pc;
    logic [`DATA_WIDTH-1:0] fs_inst;
    logic fs_pred_taken;
    logic [`ADDR_WIDTH-1:0] fs_pred_target;

    logic skid_valid;
    logic [`ADDR_WIDTH-1:0] skid_pc;
    logic [`DATA_WIDTH-1:0] skid_inst;
    logic skid_pred_taken;
    logic [`ADDR_WIDTH-1:0] skid_pred_target;

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

    assign bp_lookup_index = fetch_pc[BP_INDEX_WIDTH+1:2];
    assign bp_lookup_tag = fetch_pc[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign bp_hit = bp_valid[bp_lookup_index] && (bp_tag[bp_lookup_index] == bp_lookup_tag);
    assign bp_pred_taken = bp_hit && bp_taken[bp_lookup_index];
    assign bp_pred_target = bp_target[bp_lookup_index];

    assign fetch_seq_pc = fetch_pc + 32'd4;
    assign fetch_next_pc = bp_pred_taken ? bp_pred_target : fetch_seq_pc;

    logic fs_allowin;
    logic redirect;
    logic [`ADDR_WIDTH-1:0] redirect_pc;
    logic resp_fire;
    logic issue_fetch;

    assign redirect = exception_flag || br_taken;
    assign redirect_pc = exception_flag ? exception_addr : br_target;
    assign fs_allowin = !fs_valid || ds_allowin;
    assign resp_fire = req_valid && inst_valid;
    assign issue_fetch = !redirect && inst_ready && (!req_valid || resp_fire) &&
                         fs_allowin && !skid_valid;

    assign pc_out = fetch_pc;
    assign inst_ren = issue_fetch;
    assign fs_to_ds_valid = fs_valid && !redirect;
    assign fs_to_ds_bus = {fs_inst, fs_pc, fs_pred_taken, fs_pred_target};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_valid <= 1'b0;
            fs_pc <= `PC_START;
            fs_inst <= `NOP_INST;
            fs_pred_taken <= 1'b0;
            fs_pred_target <= 32'b0;
            skid_valid <= 1'b0;
            skid_pc <= 32'b0;
            skid_inst <= `NOP_INST;
            skid_pred_taken <= 1'b0;
            skid_pred_target <= 32'b0;
            req_valid <= 1'b0;
            req_pc <= 32'b0;
            req_pred_taken <= 1'b0;
            req_pred_target <= 32'b0;
            fetch_pc <= `PC_START;
        end else if (redirect) begin
            fs_valid <= 1'b0;
            skid_valid <= 1'b0;
            req_valid <= 1'b0;
            fetch_pc <= redirect_pc;
        end else begin
            if (fs_allowin) begin
                if (skid_valid) begin
                    fs_valid <= 1'b1;
                    fs_pc <= skid_pc;
                    fs_inst <= skid_inst;
                    fs_pred_taken <= skid_pred_taken;
                    fs_pred_target <= skid_pred_target;
                    skid_valid <= 1'b0;
                end else if (resp_fire) begin
                    fs_valid <= 1'b1;
                    fs_pc <= req_pc;
                    fs_inst <= inst_in;
                    fs_pred_taken <= req_pred_taken;
                    fs_pred_target <= req_pred_target;
                end else if (ds_allowin || !fs_valid) begin
                    fs_valid <= 1'b0;
                end
            end else if (resp_fire) begin
                skid_valid <= 1'b1;
                skid_pc <= req_pc;
                skid_inst <= inst_in;
                skid_pred_taken <= req_pred_taken;
                skid_pred_target <= req_pred_target;
            end

            req_valid <= (req_valid && !resp_fire) || issue_fetch;
            if (issue_fetch) begin
                req_pc <= fetch_pc;
                req_pred_taken <= bp_pred_taken;
                req_pred_target <= bp_pred_target;
                fetch_pc <= fetch_next_pc;
            end
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

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000;
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule
