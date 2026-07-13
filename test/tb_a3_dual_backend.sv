`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_a3_dual_backend;
    logic clk;
    logic rst_n;
    logic redirect;
    logic launch_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] launch_bundle;
    logic launch_ready;
    logic busy;
    logic rf_read_en;
    logic [4:0] rf_raddr0;
    logic [4:0] rf_raddr1;
    logic [4:0] rf_raddr2;
    logic [4:0] rf_raddr3;
    logic [31:0] rf_rdata0;
    logic [31:0] rf_rdata1;
    logic [31:0] rf_rdata2;
    logic [31:0] rf_rdata3;
    logic [1:0] commit_valid;
    logic [1:0] commit_wen;
    logic [4:0] commit_waddr0;
    logic [4:0] commit_waddr1;
    logic [31:0] commit_wdata0;
    logic [31:0] commit_wdata1;
    logic [1:0] retire_count;
    logic dependency_event;
    logic pending_stall_event;
    logic [31:0] commit_pc0;
    logic [31:0] commit_pc1;
    logic [31:0] commit_inst0;
    logic [31:0] commit_inst1;
    logic [`FETCH_AGE_WIDTH-1:0] commit_age0;
    logic [`FETCH_AGE_WIDTH-1:0] commit_age1;
    logic [`FETCH_EPOCH_WIDTH-1:0] commit_epoch0;
    logic [`FETCH_EPOCH_WIDTH-1:0] commit_epoch1;
    logic [4:0] legacy_raddr1;
    logic [4:0] legacy_raddr2;
    logic [31:0] legacy_rdata1;
    logic [31:0] legacy_rdata2;
    logic [31:0] debug_data_unused;

    logic dispatch_redirect;
    logic dispatch_bundle_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] dispatch_bundle;
    logic dispatch_next_bundle_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] dispatch_next_bundle;
    logic dispatch_legacy_idle;
    logic dispatch_prefer_legacy;
    logic dispatch_dual_mode;
    logic dispatch_dual_candidate;
    logic dispatch_next_dual_candidate;
    logic dispatch_dual_valid;
    logic dispatch_legacy_valid;

    logic sb_consumer_valid;
    logic [3:0] sb_consumer_uses;
    logic [19:0] sb_consumer_rs_flat;
    logic [5:0] sb_producer_valid;
    logic [5:0] sb_producer_kill;
    logic [5:0] sb_producer_pending;
    logic [5:0] sb_producer_result_valid;
    logic [29:0] sb_producer_dest_flat;
    logic sb_dependency;
    logic sb_stall;
    logic [11:0] sb_forward_sel_flat;

    function automatic logic [`FETCH_UOP_WIDTH-1:0] make_uop(
        input logic [`FETCH_EPOCH_WIDTH-1:0] epoch,
        input logic [`FETCH_AGE_WIDTH-1:0] age,
        input logic [31:0] inst,
        input logic [31:0] pc
    );
        make_uop = {epoch, age, inst, pc, 1'b0, 32'b0,
                    `BP_TYPE_BRANCH, 1'b0, 1'b0, 32'b0};
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [`FETCH_AGE_WIDTH-1:0] age0
    );
        make_pair = {1'b1, 1'b1,
                     make_uop(2'd1, age0 + 1'b1, inst1, pc0 + 32'd4),
                     make_uop(2'd1, age0, inst0, pc0)};
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_single(
        input logic [31:0] inst0,
        input logic [31:0] pc0,
        input logic [`FETCH_AGE_WIDTH-1:0] age0
    );
        make_single = {1'b0, 1'b1, {`FETCH_UOP_WIDTH{1'b0}},
                       make_uop(2'd1, age0, inst0, pc0)};
    endfunction

    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .write0_wen(commit_valid[0] && commit_wen[0]),
        .write0_waddr(commit_waddr0),
        .write0_wdata(commit_wdata0),
        .write1_wen(commit_valid[1] && commit_wen[1]),
        .write1_waddr(commit_waddr1),
        .write1_wdata(commit_wdata1),
        .regfile_raddr1(legacy_raddr1),
        .regfile_rdata1(legacy_rdata1),
        .regfile_raddr2(legacy_raddr2),
        .regfile_rdata2(legacy_rdata2),
        .sync_ren(rf_read_en),
        .sync_raddr0(rf_raddr0),
        .sync_raddr1(rf_raddr1),
        .sync_raddr2(rf_raddr2),
        .sync_raddr3(rf_raddr3),
        .sync_rdata0(rf_rdata0),
        .sync_rdata1(rf_rdata1),
        .sync_rdata2(rf_rdata2),
        .sync_rdata3(rf_rdata3),
        .debug_data(debug_data_unused)
    );

    dual_alu_pipeline dut (
        .clk(clk),
        .rst_n(rst_n),
        .redirect(redirect),
        .launch_valid(launch_valid),
        .launch_bundle(launch_bundle),
        .launch_ready(launch_ready),
        .busy(busy),
        .rf_read_en(rf_read_en),
        .rf_raddr0(rf_raddr0),
        .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2),
        .rf_raddr3(rf_raddr3),
        .rf_rdata0(rf_rdata0),
        .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2),
        .rf_rdata3(rf_rdata3),
        .commit_valid(commit_valid),
        .commit_wen(commit_wen),
        .commit_waddr0(commit_waddr0),
        .commit_waddr1(commit_waddr1),
        .commit_wdata0(commit_wdata0),
        .commit_wdata1(commit_wdata1),
        .retire_count(retire_count),
        .dependency_event(dependency_event),
        .pending_stall_event(pending_stall_event),
        .commit_pc0(commit_pc0),
        .commit_pc1(commit_pc1),
        .commit_inst0(commit_inst0),
        .commit_inst1(commit_inst1),
        .commit_age0(commit_age0),
        .commit_age1(commit_age1),
        .commit_epoch0(commit_epoch0),
        .commit_epoch1(commit_epoch1)
    );

    bundle_dispatch u_dispatch (
        .redirect(dispatch_redirect),
        .bundle_valid(dispatch_bundle_valid),
        .bundle(dispatch_bundle),
        .next_bundle_valid(dispatch_next_bundle_valid),
        .next_bundle(dispatch_next_bundle),
        .legacy_idle(dispatch_legacy_idle),
        .prefer_legacy(dispatch_prefer_legacy),
        .dual_mode(dispatch_dual_mode),
        .dual_candidate(dispatch_dual_candidate),
        .next_dual_candidate(dispatch_next_dual_candidate),
        .dual_bundle_valid(dispatch_dual_valid),
        .legacy_bundle_valid(dispatch_legacy_valid)
    );

    dual_scoreboard u_scoreboard (
        .consumer_valid(sb_consumer_valid),
        .consumer_uses(sb_consumer_uses),
        .consumer_rs_flat(sb_consumer_rs_flat),
        .producer_valid(sb_producer_valid),
        .producer_kill(sb_producer_kill),
        .producer_pending(sb_producer_pending),
        .producer_result_valid(sb_producer_result_valid),
        .producer_dest_flat(sb_producer_dest_flat),
        .dependency(sb_dependency),
        .stall(sb_stall),
        .forward_sel_flat(sb_forward_sel_flat)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        redirect = 1'b0;
        launch_valid = 1'b0;
        launch_bundle = '0;
        legacy_raddr1 = '0;
        legacy_raddr2 = '0;
        dispatch_redirect = 1'b0;
        dispatch_bundle_valid = 1'b0;
        dispatch_bundle = '0;
        dispatch_next_bundle_valid = 1'b0;
        dispatch_next_bundle = '0;
        dispatch_legacy_idle = 1'b1;
        dispatch_prefer_legacy = 1'b0;
        dispatch_dual_mode = 1'b0;
        sb_consumer_valid = 1'b0;
        sb_consumer_uses = '0;
        sb_consumer_rs_flat = '0;
        sb_producer_valid = '0;
        sb_producer_kill = '0;
        sb_producer_pending = '0;
        sb_producer_result_valid = '0;
        sb_producer_dest_flat = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // P0 writes x1=5 and x2=7.
        launch_bundle = make_pair(32'h0050_0093, 32'h0070_0113,
                                  32'h0000_0100, 32'd0);
        launch_valid = 1'b1;
        @(posedge clk);
        #1;
        if ((commit_valid !== 2'b11) || (commit_wen !== 2'b11) ||
            (commit_wdata0 !== 32'd5) || (commit_wdata1 !== 32'd7) ||
            (retire_count !== 2'd2) ||
            (commit_age1 != (commit_age0 + 1'b1))) begin
            $fatal(1, "first dual ALU pair result/tag mismatch");
        end

        // P1 consumes both P0 results.  The scoreboard marks a dependency,
        // while same-edge 2W-to-4R bypass keeps launch unstalled.
        @(negedge clk);
        launch_bundle = make_pair(32'h0020_81B3, 32'h4011_0233,
                                  32'h0000_0108, 32'd2);
        #1;
        if (!dependency_event || pending_stall_event || !launch_ready) begin
            $fatal(1, "cross-bundle ready dependency was not forwarded");
        end
        @(posedge clk);
        #1;
        if ((commit_wdata0 !== 32'd12) || (commit_wdata1 !== 32'd2) ||
            (commit_pc0 !== 32'h0000_0108) ||
            (commit_pc1 !== 32'h0000_010C)) begin
            $fatal(1, "cross-bundle WB-to-sync-read bypass failed");
        end

        @(negedge clk);
        launch_valid = 1'b0;
        legacy_raddr1 = 5'd3;
        legacy_raddr2 = 5'd4;
        @(posedge clk);
        #1;
        if ((legacy_rdata1 !== 32'd12) || (legacy_rdata2 !== 32'd2)) begin
            $fatal(1, "dual ALU results did not commit through 2W GPR");
        end

        // LUI and AUIPC cover the no-source dual datapath case.
        @(negedge clk);
        launch_bundle = make_pair(32'h1234_52B7, 32'h0000_1317,
                                  32'h0000_0200, 32'd4);
        launch_valid = 1'b1;
        @(posedge clk);
        #1;
        if ((commit_wdata0 !== 32'h1234_5000) ||
            (commit_wdata1 !== 32'h0000_1204)) begin
            $fatal(1, "dual LUI/AUIPC result mismatch");
        end

        // Arithmetic right shifts keep the sign bit, including a dependency
        // on values written by the immediately preceding pair.
        @(negedge clk);
        launch_bundle = make_pair(32'h8000_04B7, 32'h0010_0513,
                                  32'h0000_0208, 32'd6);
        @(posedge clk);
        #1;
        if ((commit_wdata0 !== 32'h8000_0000) ||
            (commit_wdata1 !== 32'd1)) begin
            $fatal(1, "dual SRA seed pair mismatch");
        end
        @(negedge clk);
        launch_bundle = make_pair(32'h40A4_D5B3, 32'h4014_D613,
                                  32'h0000_0210, 32'd8);
        @(posedge clk);
        #1;
        if ((commit_wdata0 !== 32'hC000_0000) ||
            (commit_wdata1 !== 32'hC000_0000)) begin
            $fatal(1, "dual SRA/SRAI sign extension mismatch");
        end
        @(negedge clk);
        launch_valid = 1'b0;
        @(posedge clk);

        // A redirect kills the resident pair before its architectural edge.
        @(negedge clk);
        launch_bundle = make_pair(32'h0090_0393, 32'h00A0_0413,
                                  32'h0000_0300, 32'd10);
        launch_valid = 1'b1;
        @(posedge clk);
        #1;
        if (commit_valid !== 2'b11) begin
            $fatal(1, "redirect test pair did not become resident");
        end
        @(negedge clk);
        launch_valid = 1'b0;
        redirect = 1'b1;
        #1;
        if ((commit_valid != 0) || (retire_count != 0)) begin
            $fatal(1, "redirect did not suppress resident dual commit");
        end
        @(posedge clk);
        @(negedge clk);
        redirect = 1'b0;
        legacy_raddr1 = 5'd7;
        legacy_raddr2 = 5'd8;
        #1;
        if ((legacy_rdata1 != 0) || (legacy_rdata2 != 0) || busy) begin
            $fatal(1, "killed dual pair changed architectural state");
        end

        // Dispatch accepts only supported pair ALU bundles and waits for the
        // opposite domain to drain before switching.
        dispatch_bundle_valid = 1'b1;
        dispatch_bundle = make_pair(32'h0010_0093, 32'h0020_0113,
                                    32'h0000_0400, 32'd12);
        dispatch_next_bundle_valid = 1'b1;
        dispatch_next_bundle = make_pair(32'h0030_0193, 32'h0040_0213,
                                         32'h0000_0408, 32'd14);
        #1;
        if (!dispatch_dual_candidate || !dispatch_dual_valid ||
            dispatch_legacy_valid) begin
            $fatal(1, "supported dual bundle dispatch mismatch");
        end
        dispatch_legacy_idle = 1'b0;
        #1;
        if (dispatch_dual_valid || dispatch_legacy_valid) begin
            $fatal(1, "dual bundle crossed an active legacy domain");
        end
        dispatch_legacy_idle = 1'b1;

        // Once dual mode is established, FIFO starvation does not force a
        // new lookahead warmup.  A long-latency cooldown can still hand the
        // same supported pair back to the legacy path atomically.
        dispatch_dual_mode = 1'b1;
        dispatch_next_bundle_valid = 1'b0;
        #1;
        if (!dispatch_dual_valid || dispatch_legacy_valid) begin
            $fatal(1, "dual mode did not survive a lookahead gap");
        end
        dispatch_prefer_legacy = 1'b1;
        #1;
        if (dispatch_dual_valid || !dispatch_legacy_valid) begin
            $fatal(1, "legacy cooldown did not override dual mode");
        end
        dispatch_prefer_legacy = 1'b0;
        dispatch_dual_mode = 1'b0;

        dispatch_bundle = make_pair(32'h0220_81B3, 32'h0020_0113,
                                    32'h0000_0410, 32'd16); // MUL unsupported in A3
        #1;
        if (dispatch_dual_candidate || dispatch_dual_valid ||
            !dispatch_legacy_valid) begin
            $fatal(1, "unsupported bundle did not route to legacy backend");
        end
        // A current dual resident may commit while the younger legacy uop
        // enters Decode; retirement remains ordered and non-overlapping.
        #1;
        if (!dispatch_legacy_valid) begin
            $fatal(1, "dual-to-legacy same-edge handoff was not allowed");
        end
        dispatch_bundle = make_single(32'h0010_0493,
                                      32'h0000_0418, 32'd18);
        #1;
        if (dispatch_dual_candidate || !dispatch_legacy_valid) begin
            $fatal(1, "single simple uop escaped the legacy backend");
        end

        // Standalone scoreboard checks pending, result forwarding, kill and
        // youngest-producer priority across the EX/MEM/WB slot model.
        sb_consumer_valid = 1'b1;
        sb_consumer_uses = 4'b0001;
        sb_consumer_rs_flat[4:0] = 5'd9;
        sb_producer_valid[0] = 1'b1;
        sb_producer_pending[0] = 1'b1;
        sb_producer_dest_flat[4:0] = 5'd9;
        #1;
        if (!sb_dependency || !sb_stall) begin
            $fatal(1, "pending producer did not stall consumer");
        end
        sb_producer_pending[0] = 1'b0;
        sb_producer_result_valid[0] = 1'b1;
        #1;
        if (!sb_dependency || sb_stall ||
            (sb_forward_sel_flat[2:0] != 3'd1)) begin
            $fatal(1, "ready producer forwarding select mismatch");
        end
        sb_producer_kill[0] = 1'b1;
        #1;
        if (sb_dependency || sb_stall) begin
            $fatal(1, "killed producer remained in scoreboard");
        end
        sb_producer_kill[0] = 1'b0;
        sb_producer_pending[0] = 1'b1;
        sb_producer_result_valid[0] = 1'b0;
        sb_producer_valid[4] = 1'b1;
        sb_producer_result_valid[4] = 1'b1;
        sb_producer_dest_flat[24:20] = 5'd9;
        #1;
        if (!sb_stall || (sb_forward_sel_flat[2:0] != 0)) begin
            $fatal(1, "older ready producer bypassed younger pending producer");
        end

        $display("A3 DUAL BACKEND TEST PASSED");
        $finish;
    end

endmodule
