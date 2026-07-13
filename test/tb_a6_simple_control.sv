`timescale 1ns/1ps
`include "defines.svh"

module tb_a6_simple_control;
    logic clk;
    logic rst_n;
    logic redirect;
    logic launch_valid;
    logic [`ISSUE_BUNDLE_WIDTH-1:0] launch_bundle;
    logic launch_ready;
    logic busy;
    logic block_legacy;
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
    logic branch_event;
    logic branch_mispredict_event;
    logic branch_redirect;
    logic [31:0] branch_redirect_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic [`BP_TYPE_WIDTH-1:0] bp_update_type;
    logic lane1_control_event;
    logic control0_simple_event;
    logic exception_valid;
    logic [6:0] exception_code;
    logic [31:0] exception_pc;
    logic [31:0] exception_mtval;

    logic seed_wen;
    logic [4:0] seed_waddr;
    logic [31:0] seed_wdata;
    logic write0_wen;
    logic [4:0] write0_waddr;
    logic [31:0] write0_wdata;
    logic [4:0] inspect_raddr0;
    logic [4:0] inspect_raddr1;
    logic [31:0] inspect_rdata0;
    logic [31:0] inspect_rdata1;
    integer control_launch_count;
    integer control0_launch_count;

    assign write0_wen = seed_wen ? 1'b1 :
                        (commit_valid[0] && commit_wen[0]);
    assign write0_waddr = seed_wen ? seed_waddr : commit_waddr0;
    assign write0_wdata = seed_wen ? seed_wdata : commit_wdata0;

    always #5 clk = ~clk;

    regfiles u_regfiles (
        .clk(clk),
        .rst_n(rst_n),
        .write0_wen(write0_wen),
        .write0_waddr(write0_waddr),
        .write0_wdata(write0_wdata),
        .write1_wen(commit_valid[1] && commit_wen[1]),
        .write1_waddr(commit_waddr1),
        .write1_wdata(commit_wdata1),
        .regfile_raddr1(inspect_raddr0),
        .regfile_rdata1(inspect_rdata0),
        .regfile_raddr2(inspect_raddr1),
        .regfile_rdata2(inspect_rdata1),
        .sync_ren(rf_read_en),
        .sync_raddr0(rf_raddr0),
        .sync_raddr1(rf_raddr1),
        .sync_raddr2(rf_raddr2),
        .sync_raddr3(rf_raddr3),
        .sync_rdata0(rf_rdata0),
        .sync_rdata1(rf_rdata1),
        .sync_rdata2(rf_rdata2),
        .sync_rdata3(rf_rdata3)
`ifdef DEBUG_EN
        , .debug_data()
`endif
    );

    dual_alu_pipeline dut (
        .clk(clk), .rst_n(rst_n), .redirect(redirect),
        .launch_valid(launch_valid), .launch_bundle(launch_bundle),
        .launch_ready(launch_ready), .busy(busy),
        .block_legacy(block_legacy),
        .rf_read_en(rf_read_en),
        .rf_raddr0(rf_raddr0), .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2), .rf_raddr3(rf_raddr3),
        .rf_rdata0(rf_rdata0), .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2), .rf_rdata3(rf_rdata3),
        .dmem_rdata(32'b0), .dmem_rvalid(1'b0),
        .lsu_port_ready(1'b1), .dmem_load_en(), .dmem_load_addr(),
        .store_event(), .store_pc(), .store_addr(), .store_wen(),
        .store_wdata(),
        .commit_valid(commit_valid), .commit_wen(commit_wen),
        .commit_waddr0(commit_waddr0), .commit_waddr1(commit_waddr1),
        .commit_wdata0(commit_wdata0), .commit_wdata1(commit_wdata1),
        .retire_count(retire_count), .dependency_event(),
        .pending_stall_event(), .commit_pc0(), .commit_pc1(),
        .commit_inst0(), .commit_inst1(), .commit_age0(), .commit_age1(),
        .commit_epoch0(), .commit_epoch1(),
        .branch_event(branch_event),
        .branch_mispredict_event(branch_mispredict_event),
        .branch_redirect(branch_redirect),
        .branch_redirect_target(branch_redirect_target),
        .bp_update_valid(bp_update_valid), .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken), .bp_update_target(bp_update_target),
        .bp_update_type(bp_update_type),
        .lane1_control_event(lane1_control_event),
        .control0_simple_event(control0_simple_event),
        .lsu_pair_event(),
        .muldiv_pair_event(),
        .exception_valid(exception_valid), .exception_code(exception_code),
        .exception_pc(exception_pc), .exception_mtval(exception_mtval)
    );

    function automatic logic [`FETCH_UOP_WIDTH-1:0] make_uop(
        input logic [31:0] inst,
        input logic [31:0] pc,
        input logic [31:0] age,
        input logic pred_taken,
        input logic [31:0] pred_target
    );
        make_uop = {2'd0, age, inst, pc, pred_taken, pred_target,
                    `BP_TYPE_BRANCH, 1'b0, 1'b0, 32'b0};
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] age0,
        input logic pred_taken1,
        input logic [31:0] pred_target1
    );
        make_pair = {1'b1, 1'b1,
                     make_uop(inst1, pc0 + 32'd4, age0 + 32'd1,
                              pred_taken1, pred_target1),
                     make_uop(inst0, pc0, age0, 1'b0, 32'b0)};
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_control0_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] pc1,
        input logic [31:0] age0,
        input logic pred_taken0,
        input logic [31:0] pred_target0
    );
        make_control0_pair = {
            1'b1, 1'b1,
            make_uop(inst1, pc1, age0 + 32'd1, 1'b0, 32'b0),
            make_uop(inst0, pc0, age0, pred_taken0, pred_target0)
        };
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_control_single(
        input logic [31:0] inst0,
        input logic [31:0] pc0,
        input logic [31:0] age0,
        input logic pred_taken0,
        input logic [31:0] pred_target0
    );
        make_control_single = {
            1'b0, 1'b1, {`FETCH_UOP_WIDTH{1'b0}},
            make_uop(inst0, pc0, age0, pred_taken0, pred_target0)
        };
    endfunction

    task automatic seed_reg(
        input logic [4:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            seed_waddr = addr;
            seed_wdata = data;
            seed_wen = 1'b1;
            @(posedge clk);
            #0.1;
            seed_wen = 1'b0;
        end
    endtask

    task automatic launch_control_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] age0,
        input logic pred_taken1,
        input logic [31:0] pred_target1
    );
        begin
            if (busy) $fatal(1, "control test launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_pair(inst0, inst1, pc0, age0,
                                      pred_taken1, pred_target1);
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en || !lane1_control_event) begin
                $fatal(1, "simple+control pair was not accepted atomically");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
        end
    endtask

    task automatic launch_control0_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] pc1,
        input logic [31:0] age0,
        input logic pred_taken0,
        input logic [31:0] pred_target0
    );
        begin
            if (busy) $fatal(1, "control0 test launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_control0_pair(
                inst0, inst1, pc0, pc1, age0,
                pred_taken0, pred_target0
            );
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en ||
                !control0_simple_event || lane1_control_event) begin
                $fatal(1, "control0+simple1 pair was not accepted atomically");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
        end
    endtask

    task automatic launch_control_single(
        input logic [31:0] inst0,
        input logic [31:0] pc0,
        input logic [31:0] age0,
        input logic pred_taken0,
        input logic [31:0] pred_target0
    );
        begin
            if (busy) $fatal(1, "control singleton launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_control_single(
                inst0, pc0, age0, pred_taken0, pred_target0
            );
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en || lane1_control_event ||
                control0_simple_event) begin
                $fatal(1, "control singleton was not accepted as lane0 only");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
        end
    endtask

    task automatic commit_and_drain;
        begin
            @(posedge clk);
            #0.1;
            if (busy || (commit_valid != 2'b00)) begin
                $fatal(1, "control resident did not drain after commit");
            end
        end
    endtask

    task automatic expect_reg(
        input logic [4:0] addr,
        input logic [31:0] expected,
        input string name
    );
        begin
            inspect_raddr0 = addr;
            #0.1;
            if (inspect_rdata0 !== expected) begin
                $fatal(1, "%s expected=%08h actual=%08h",
                       name, expected, inspect_rdata0);
            end
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            control_launch_count <= 0;
            control0_launch_count <= 0;
        end else begin
            if (lane1_control_event) begin
                control_launch_count <= control_launch_count + 1;
            end
            if (control0_simple_event) begin
                control0_launch_count <= control0_launch_count + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        redirect = 1'b0;
        launch_valid = 1'b0;
        launch_bundle = '0;
        seed_wen = 1'b0;
        seed_waddr = 5'b0;
        seed_wdata = 32'b0;
        inspect_raddr0 = 5'b0;
        inspect_raddr1 = 5'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;

        // BEQ not taken and correctly predicted: no redirect, both retire.
        seed_reg(5'd2, 32'd1);
        seed_reg(5'd3, 32'd2);
        launch_control_pair(32'h0070_0213, 32'h0031_0463,
                            32'h0000_1000, 32'd10, 1'b0, 32'b0);
        if ((commit_valid != 2'b11) || (retire_count != 2) ||
            !commit_wen[0] || commit_wen[1] || !branch_event ||
            branch_redirect || branch_mispredict_event || bp_update_taken ||
            (commit_waddr0 != 5'd4) || (commit_wdata0 != 32'd7)) begin
            $fatal(1, "lane1 BEQ not-taken commit mismatch");
        end
        commit_and_drain();
        expect_reg(5'd4, 32'd7, "older simple before BEQ");

        // Same BEQ taken but predicted not-taken: both retire, then redirect.
        seed_reg(5'd3, 32'd1);
        launch_control_pair(32'h0090_0293, 32'h0031_0463,
                            32'h0000_2000, 32'd20, 1'b0, 32'b0);
        if ((commit_valid != 2'b11) || (retire_count != 2) ||
            !branch_redirect || !branch_mispredict_event ||
            (branch_redirect_target != 32'h0000_200c) ||
            !bp_update_valid || !bp_update_taken ||
            (bp_update_pc != 32'h0000_2004) ||
            (bp_update_target != 32'h0000_200c)) begin
            $fatal(1, "lane1 BEQ mispredict/redirect mismatch");
        end
        commit_and_drain();
        expect_reg(5'd5, 32'd9, "older simple before taken BEQ");

        // JAL call predicted correctly writes its link register without redirect.
        launch_control_pair(32'h00b0_0393, 32'h0080_02ef,
                            32'h0000_3000, 32'd30, 1'b1, 32'h0000_300c);
        if ((commit_valid != 2'b11) || !commit_wen[1] ||
            (commit_waddr1 != 5'd5) || (commit_wdata1 != 32'h0000_3008) ||
            branch_redirect || (bp_update_type != `BP_TYPE_CALL)) begin
            $fatal(1, "lane1 JAL call/link mismatch");
        end
        commit_and_drain();
        expect_reg(5'd5, 32'h0000_3008, "JAL link");

        // JALR return uses the synchronized lane1 source and retains call age.
        seed_reg(5'd1, 32'h0000_4100);
        launch_control_pair(32'h00d0_0413, 32'h0000_8067,
                            32'h0000_4000, 32'd40, 1'b1, 32'h0000_4100);
        if ((commit_valid != 2'b11) || commit_wen[1] || branch_redirect ||
            !bp_update_taken || (bp_update_target != 32'h0000_4100) ||
            (bp_update_type != `BP_TYPE_RETURN)) begin
            $fatal(1, "lane1 JALR return mismatch");
        end
        commit_and_drain();

        // Misaligned lane1 JALR traps precisely: older lane0 retires alone.
        seed_reg(5'd2, 32'h0000_5002);
        launch_control_pair(32'h00f0_0493, 32'h0001_0367,
                            32'h0000_5000, 32'd50, 1'b0, 32'b0);
        if (!exception_valid || (exception_code != `EXC_IAM) ||
            (exception_pc != 32'h0000_5004) ||
            (exception_mtval != 32'h0000_5002) ||
            (commit_valid != 2'b01) || (retire_count != 1) ||
            !commit_wen[0] || commit_wen[1] || branch_redirect) begin
            $fatal(1, "lane1 IAM age/partial-retire mismatch");
        end
        commit_and_drain();
        expect_reg(5'd9, 32'd15, "older simple before lane1 IAM");
        expect_reg(5'd6, 32'd0, "faulting JALR destination");

        // An external redirect kills both lanes before their commit edge.
        launch_control_pair(32'h0110_0513, 32'h0000_0463,
                            32'h0000_6000, 32'd60, 1'b0, 32'b0);
        @(negedge clk);
        redirect = 1'b1;
        #0.1;
        if (commit_valid != 2'b00 || branch_event || bp_update_valid) begin
            $fatal(1, "external redirect did not kill control pair side effects");
        end
        @(posedge clk);
        #0.1;
        redirect = 1'b0;
        expect_reg(5'd10, 32'd0, "externally killed older simple");

        // A7.4.1: an older, correctly predicted not-taken branch retires with
        // its independent younger simple instruction.
        seed_reg(5'd2, 32'd1);
        seed_reg(5'd3, 32'd2);
        launch_control0_pair(32'h0031_0463, 32'h0070_0613,
                             32'h0000_7000, 32'h0000_7004, 32'd70,
                             1'b0, 32'b0);
        if ((commit_valid != 2'b11) || (retire_count != 2) ||
            commit_wen[0] || !commit_wen[1] ||
            (commit_waddr1 != 5'd12) || (commit_wdata1 != 32'd7) ||
            !branch_event || branch_redirect || branch_mispredict_event ||
            !bp_update_valid || bp_update_taken ||
            (bp_update_pc != 32'h0000_7000)) begin
            $fatal(1, "control0 BEQ not-taken commit mismatch");
        end
        commit_and_drain();
        expect_reg(5'd12, 32'd7, "younger simple after correct control0");

        // A predicted-taken branch carries a non-sequential younger PC.  AUIPC
        // must use that own PC rather than assuming lane1 is always pc0+4.
        launch_control0_pair(32'h0021_0463, 32'h0000_0317,
                             32'h0000_8000, 32'h0000_8008, 32'd80,
                             1'b1, 32'h0000_8008);
        if ((commit_valid != 2'b11) || (retire_count != 2) ||
            commit_wen[0] || !commit_wen[1] ||
            (commit_waddr1 != 5'd6) ||
            (commit_wdata1 != 32'h0000_8008) ||
            branch_redirect || branch_mispredict_event ||
            !bp_update_taken || (bp_update_target != 32'h0000_8008)) begin
            $fatal(1, "control0 predicted-taken/AUIPC mismatch");
        end
        commit_and_drain();
        expect_reg(5'd6, 32'h0000_8008,
                   "non-sequential younger AUIPC result");

        // Direction mispredict: the older control retires, while the younger
        // wrong-path simple instruction is suppressed.
        launch_control0_pair(32'h0021_0463, 32'h0630_0693,
                             32'h0000_9000, 32'h0000_9004, 32'd90,
                             1'b0, 32'b0);
        if ((commit_valid != 2'b01) || (retire_count != 1) ||
            (commit_wen != 2'b00) || !branch_redirect ||
            !branch_mispredict_event ||
            (branch_redirect_target != 32'h0000_9008) ||
            !bp_update_taken || (bp_update_pc != 32'h0000_9000)) begin
            $fatal(1, "control0 direction-mispredict age kill mismatch");
        end
        commit_and_drain();
        expect_reg(5'd13, 32'd0, "younger simple after direction mispredict");

        // Target mispredict on a JAL call still commits the older link, but
        // kills the younger instruction fetched from the wrong target.
        launch_control0_pair(32'h0080_02ef, 32'h0550_0713,
                             32'h0000_a000, 32'h0000_a010, 32'd100,
                             1'b1, 32'h0000_a010);
        if ((commit_valid != 2'b01) || (retire_count != 1) ||
            !commit_wen[0] || commit_wen[1] ||
            (commit_waddr0 != 5'd5) ||
            (commit_wdata0 != 32'h0000_a004) ||
            !branch_redirect || !branch_mispredict_event ||
            (branch_redirect_target != 32'h0000_a008) ||
            (bp_update_type != `BP_TYPE_CALL)) begin
            $fatal(1, "control0 JAL target-mispredict/link mismatch");
        end
        commit_and_drain();
        expect_reg(5'd5, 32'h0000_a004, "control0 JAL link");
        expect_reg(5'd14, 32'd0, "younger simple after target mispredict");

        // A correctly predicted return uses lane0's synchronized source and
        // permits the target-path younger simple instruction to retire.
        seed_reg(5'd1, 32'h0000_b100);
        launch_control0_pair(32'h0000_8067, 32'h0090_0793,
                             32'h0000_b000, 32'h0000_b100, 32'd110,
                             1'b1, 32'h0000_b100);
        if ((commit_valid != 2'b11) || (retire_count != 2) ||
            commit_wen[0] || !commit_wen[1] ||
            (commit_waddr1 != 5'd15) || (commit_wdata1 != 32'd9) ||
            branch_redirect || branch_mispredict_event ||
            !bp_update_taken || (bp_update_target != 32'h0000_b100) ||
            (bp_update_type != `BP_TYPE_RETURN)) begin
            $fatal(1, "control0 JALR return mismatch");
        end
        commit_and_drain();
        expect_reg(5'd15, 32'd9, "younger simple after control0 return");

        // A misaligned older JALR traps before either lane retires.
        seed_reg(5'd2, 32'h0000_c002);
        launch_control0_pair(32'h0001_05e7, 32'h00a0_0813,
                             32'h0000_c000, 32'h0000_c004, 32'd120,
                             1'b0, 32'b0);
        if (!exception_valid || (exception_code != `EXC_IAM) ||
            (exception_pc != 32'h0000_c000) ||
            (exception_mtval != 32'h0000_c002) ||
            (commit_valid != 2'b00) || (retire_count != 0) ||
            (commit_wen != 2'b00) || branch_redirect) begin
            $fatal(1, "control0 IAM precise zero-retire mismatch");
        end
        commit_and_drain();
        expect_reg(5'd11, 32'd0, "faulting control0 JALR destination");
        expect_reg(5'd16, 32'd0, "younger simple after control0 IAM");

        // An external redirect kills the complete control0+simple1 resident.
        launch_control0_pair(32'h0000_0463, 32'h00c0_0893,
                             32'h0000_d000, 32'h0000_d008, 32'd130,
                             1'b1, 32'h0000_d008);
        @(negedge clk);
        redirect = 1'b1;
        #0.1;
        if ((commit_valid != 2'b00) || branch_event || bp_update_valid ||
            exception_valid) begin
            $fatal(1, "external redirect did not kill control0 pair effects");
        end
        @(posedge clk);
        #0.1;
        redirect = 1'b0;
        expect_reg(5'd17, 32'd0, "externally killed younger simple");

        // A lane0-only JAL reuses the same precise control path without
        // manufacturing a younger lane or a pair-class event.
        launch_control_single(32'h0080_02ef, 32'h0000_e000, 32'd140,
                              1'b1, 32'h0000_e008);
        if ((commit_valid != 2'b01) || (retire_count != 1) ||
            !commit_wen[0] || commit_wen[1] ||
            (commit_waddr0 != 5'd5) ||
            (commit_wdata0 != 32'h0000_e004) ||
            !branch_event || branch_redirect || branch_mispredict_event ||
            (bp_update_type != `BP_TYPE_CALL)) begin
            $fatal(1, "control singleton JAL commit mismatch");
        end
        commit_and_drain();
        expect_reg(5'd5, 32'h0000_e004, "control singleton JAL link");

        if (control_launch_count != 6) begin
            $fatal(1, "lane1 control launch counter expected 6 got %0d",
                   control_launch_count);
        end
        if (control0_launch_count != 7) begin
            $fatal(1, "control0+simple1 launch counter expected 7 got %0d",
                   control0_launch_count);
        end

        $display("A6 SIMPLE CONTROL TEST PASSED");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "tb_a6_simple_control timeout");
    end

endmodule
