`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_issue_bundle_fifo;
    logic clk;
    logic rst_n;
    logic redirect;
    logic [3:0] fetch_count;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_uop1;
    logic [1:0] fetch_pop_count;
    logic issue_bundle_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] issue_bundle;
    logic pair_accepted;
    logic reject_raw;
    logic reject_waw;
    logic reject_struct;
    logic bundle_ready;
    logic bundle_head_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle_head;
    logic bundle_pop;
    logic [2:0] bundle_count;
    logic ds_allowin;
    logic fs_to_ds_valid;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;

    logic head_lane1_valid;
    logic head_lane0_valid;
    logic [`FETCH_UOP_WIDTH-1:0] head_uop1;
    logic [`FETCH_UOP_WIDTH-1:0] head_uop0;
    logic [31:0] out_inst;
    logic [31:0] out_pc;
    logic out_pred_taken;
    logic [31:0] out_pred_target;

    assign {head_lane1_valid, head_lane0_valid, head_uop1, head_uop0} = bundle_head;
    assign {out_inst, out_pc, out_pred_taken, out_pred_target} = fs_to_ds_bus;

    issue_stage issue (
        .redirect(redirect),
        .fetch_count(fetch_count),
        .fetch_uop0(fetch_uop0),
        .fetch_uop1(fetch_uop1),
        .bundle_ready(bundle_ready),
        .fetch_pop_count(fetch_pop_count),
        .bundle_valid(issue_bundle_valid),
        .bundle(issue_bundle),
        .pair_accepted(pair_accepted),
        .reject_raw(reject_raw),
        .reject_waw(reject_waw),
        .reject_struct(reject_struct)
    );

    issue_bundle_fifo fifo (
        .clk(clk),
        .rst_n(rst_n),
        .clear(redirect),
        .push_valid(issue_bundle_valid),
        .push_bundle(issue_bundle),
        .pop_valid(bundle_pop),
        .head_valid(bundle_head_valid),
        .head_bundle(bundle_head),
        .count(bundle_count),
        .push_ready(bundle_ready)
    );

    bundle_decode_adapter adapter (
        .clk(clk),
        .rst_n(rst_n),
        .redirect(redirect),
        .bundle_valid(bundle_head_valid),
        .bundle(bundle_head),
        .bundle_pop(bundle_pop),
        .ds_allowin(ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus)
    );

    function automatic logic [`FETCH_UOP_WIDTH-1:0] make_uop(
        input logic [31:0] inst,
        input logic [31:0] pc,
        input logic [31:0] age
    );
        make_uop = {2'd0, age, inst, pc, 1'b0, 32'd0,
                    `BP_TYPE_BRANCH, 1'b0, 1'b0, 32'd0};
    endfunction

    always #5 clk = ~clk;

    task automatic clear_pipeline;
        begin
            @(negedge clk);
            fetch_count = 0;
            redirect = 1;
            @(posedge clk);
            @(negedge clk);
            redirect = 0;
        end
    endtask

    task automatic present_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [1:0] expected_pop,
        input logic expected_pair,
        input logic expected_raw,
        input logic expected_waw,
        input logic expected_struct
    );
        begin
            @(negedge clk);
            fetch_uop0 = make_uop(inst0, 32'h1000, 0);
            fetch_uop1 = make_uop(inst1, 32'h1004, 1);
            fetch_count = 2;
            #1;
            if ((fetch_pop_count !== expected_pop) ||
                (pair_accepted !== expected_pair) ||
                (reject_raw !== expected_raw) ||
                (reject_waw !== expected_waw) ||
                (reject_struct !== expected_struct)) begin
                $fatal(1, "issue decision mismatch pop=%0d pair=%0d raw=%0d waw=%0d struct=%0d",
                       fetch_pop_count, pair_accepted, reject_raw,
                       reject_waw, reject_struct);
            end
            @(posedge clk);
            @(negedge clk);
            fetch_count = 0;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        redirect = 0;
        fetch_count = 0;
        fetch_uop0 = '0;
        fetch_uop1 = '0;
        ds_allowin = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        // Independent simple+simple is stored atomically and serialized in age order.
        present_pair(32'h00100093, 32'h00200113, 2, 1, 0, 0, 0);
        if ((bundle_count != 1) || !head_lane0_valid || !head_lane1_valid) begin
            $fatal(1, "paired bundle was not stored atomically");
        end
        if (!fs_to_ds_valid || (out_pc != 32'h1000)) begin
            $fatal(1, "adapter did not expose lane0 first");
        end
        ds_allowin = 1;
        @(posedge clk);
        @(negedge clk);
        if (!fs_to_ds_valid || (out_pc != 32'h1004)) begin
            $fatal(1, "adapter did not preserve lane1 age order");
        end
        @(posedge clk);
        @(negedge clk);
        ds_allowin = 0;
        if (fs_to_ds_valid || (bundle_count != 0)) begin
            $fatal(1, "adapter/bundle FIFO did not drain pair");
        end

        // RAW, WAW and structural conflicts each force an atomic lane0-only bundle.
        present_pair(32'h00100193, 32'h00018233, 1, 0, 1, 0, 0);
        if (!head_lane0_valid || head_lane1_valid) $fatal(1, "RAW bundle not lane0-only");
        clear_pipeline();
        present_pair(32'h00100293, 32'h00200293, 1, 0, 0, 1, 0);
        if (!head_lane0_valid || head_lane1_valid) $fatal(1, "WAW bundle not lane0-only");
        clear_pipeline();
        present_pair(32'h00002083, 32'h00200113, 1, 0, 0, 0, 1);
        if (!head_lane0_valid || head_lane1_valid) $fatal(1, "structural bundle not lane0-only");

        // Redirect atomically clears the resident bundle and adapter state.
        clear_pipeline();
        if ((bundle_count != 0) || fs_to_ds_valid) begin
            $fatal(1, "redirect did not clear bundle path");
        end

        $display("ISSUE BUNDLE FIFO TEST PASSED");
        $finish;
    end

endmodule
