`timescale 1ns/1ps
`include "defines.svh"

module tb_a6_lsu_pair;
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
    logic [31:0] dmem_rdata;
    logic dmem_rvalid;
    logic lsu_port_ready;
    logic dmem_load_en;
    logic [31:0] dmem_load_addr;
    logic store_event;
    logic [31:0] store_pc;
    logic [31:0] store_addr;
    logic [3:0] store_wen;
    logic [31:0] store_wdata;
    logic [1:0] commit_valid;
    logic [1:0] commit_wen;
    logic [4:0] commit_waddr0;
    logic [4:0] commit_waddr1;
    logic [31:0] commit_wdata0;
    logic [31:0] commit_wdata1;
    logic [1:0] retire_count;
    logic lsu_pair_event;
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
    logic [4:0] inspect_addr0;
    logic [4:0] inspect_addr1;
    logic [31:0] inspect_data0;
    logic [31:0] inspect_data1;
    integer load_request_count;
    integer store_commit_count;
    integer lsu_pair_count;

    assign write0_wen = seed_wen ? 1'b1 :
                        (commit_valid[0] && commit_wen[0]);
    assign write0_waddr = seed_wen ? seed_waddr : commit_waddr0;
    assign write0_wdata = seed_wen ? seed_wdata : commit_wdata0;

    always #5 clk = ~clk;

    regfiles u_regfiles (
        .clk(clk), .rst_n(rst_n),
        .write0_wen(write0_wen), .write0_waddr(write0_waddr),
        .write0_wdata(write0_wdata),
        .write1_wen(commit_valid[1] && commit_wen[1]),
        .write1_waddr(commit_waddr1), .write1_wdata(commit_wdata1),
        .regfile_raddr1(inspect_addr0), .regfile_rdata1(inspect_data0),
        .regfile_raddr2(inspect_addr1), .regfile_rdata2(inspect_data1),
        .sync_ren(rf_read_en),
        .sync_raddr0(rf_raddr0), .sync_raddr1(rf_raddr1),
        .sync_raddr2(rf_raddr2), .sync_raddr3(rf_raddr3),
        .sync_rdata0(rf_rdata0), .sync_rdata1(rf_rdata1),
        .sync_rdata2(rf_rdata2), .sync_rdata3(rf_rdata3)
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
        .dmem_rdata(dmem_rdata), .dmem_rvalid(dmem_rvalid),
        .lsu_port_ready(lsu_port_ready),
        .dmem_load_en(dmem_load_en), .dmem_load_addr(dmem_load_addr),
        .store_event(store_event), .store_pc(store_pc),
        .store_addr(store_addr), .store_wen(store_wen),
        .store_wdata(store_wdata),
        .commit_valid(commit_valid), .commit_wen(commit_wen),
        .commit_waddr0(commit_waddr0), .commit_waddr1(commit_waddr1),
        .commit_wdata0(commit_wdata0), .commit_wdata1(commit_wdata1),
        .retire_count(retire_count), .dependency_event(),
        .pending_stall_event(), .commit_pc0(), .commit_pc1(),
        .commit_inst0(), .commit_inst1(), .commit_age0(), .commit_age1(),
        .commit_epoch0(), .commit_epoch1(),
        .branch_event(), .branch_mispredict_event(), .branch_redirect(),
        .branch_redirect_target(), .bp_update_valid(), .bp_update_pc(),
        .bp_update_taken(), .bp_update_target(), .bp_update_type(),
        .lane1_control_event(), .control0_simple_event(),
        .lsu_pair_event(lsu_pair_event),
        .muldiv_pair_event(),
        .exception_valid(exception_valid), .exception_code(exception_code),
        .exception_pc(exception_pc), .exception_mtval(exception_mtval)
    );

    function automatic logic [31:0] enc_i(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        enc_i = {immediate, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(
        input logic [11:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        enc_s = {immediate[11:5], rs2, rs1, funct3,
                 immediate[4:0], 7'b0100011};
    endfunction

    function automatic logic [`FETCH_UOP_WIDTH-1:0] make_uop(
        input logic [31:0] inst,
        input logic [31:0] pc,
        input logic [31:0] age
    );
        make_uop = {2'd1, age, inst, pc, 1'b0, 32'b0,
                    `BP_TYPE_BRANCH, 1'b0, 1'b0, 32'b0};
    endfunction

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        make_pair = {1'b1, 1'b1,
                     make_uop(inst1, pc0 + 32'd4, age0 + 32'd1),
                     make_uop(inst0, pc0, age0)};
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

    task automatic expect_reg(
        input logic [4:0] addr,
        input logic [31:0] expected,
        input string name
    );
        begin
            inspect_addr0 = addr;
            #0.1;
            if (inspect_data0 !== expected) begin
                $fatal(1, "%s expected=%08h actual=%08h",
                       name, expected, inspect_data0);
            end
        end
    endtask

    task automatic launch_lsu_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        begin
            if (busy) $fatal(1, "LSU pair launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_pair(inst0, inst1, pc0, age0);
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en || !lsu_pair_event) begin
                $fatal(1, "LSU pair was not accepted atomically");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
            if (!busy || !block_legacy || launch_ready) begin
                $fatal(1, "LSU pair did not establish an exclusive resident");
            end
        end
    endtask

    task automatic complete_active_load(
        input logic [31:0] expected_addr,
        input logic [31:0] response,
        input logic [4:0] expected_rd0,
        input logic [31:0] expected_data0,
        input logic [4:0] expected_rd1,
        input logic [31:0] expected_data1
    );
        integer requests_before;
        begin
            requests_before = load_request_count;
            if (!dmem_load_en || (dmem_load_addr != expected_addr) ||
                store_event || (commit_valid != 2'b00)) begin
                $fatal(1, "Load E0 request mismatch addr=%08h", dmem_load_addr);
            end
            @(posedge clk);
            #0.1;
            if (dmem_load_en || !busy || !block_legacy ||
                (load_request_count != (requests_before + 1))) begin
                $fatal(1, "Load E1 did not hold after exactly one request");
            end
            @(posedge clk);
            #0.1;
            if (!busy || !block_legacy || dmem_load_en ||
                (commit_valid != 2'b00)) begin
                $fatal(1, "Load E2 resident did not hold for its response");
            end
            @(negedge clk);
            dmem_rdata = response;
            dmem_rvalid = 1'b1;
            @(posedge clk);
            #0.1;
            dmem_rvalid = 1'b0;
            if (commit_valid != 2'b00) begin
                $fatal(1, "Load response bypassed the registered MEM boundary");
            end
            @(posedge clk);
            #0.1;
            if ((commit_valid != 2'b11) || (retire_count != 2) ||
                (commit_wen != 2'b11) ||
                (commit_waddr0 != expected_rd0) ||
                (commit_wdata0 != expected_data0) ||
                (commit_waddr1 != expected_rd1) ||
                (commit_wdata1 != expected_data1) ||
                store_event || exception_valid) begin
                $fatal(1, "dual Load MEM commit/result mismatch");
            end
            @(posedge clk);
            #0.1;
            if (busy || block_legacy || (commit_valid != 2'b00)) begin
                $fatal(1, "dual Load did not release after MEM commit");
            end
        end
    endtask

    task automatic complete_store(
        input logic [31:0] expected_pc,
        input logic [31:0] expected_addr,
        input logic [3:0] expected_wen,
        input logic [31:0] expected_wdata,
        input logic [1:0] expected_commit_wen,
        input logic [4:0] expected_simple_rd,
        input logic [31:0] expected_simple_data
    );
        integer stores_before;
        begin
            stores_before = store_commit_count;
            if (dmem_load_en || store_event || (commit_valid != 0)) begin
                $fatal(1, "Store produced an EX-stage side effect");
            end
            @(posedge clk);
            #0.1;
            if (store_event || (commit_valid != 0)) begin
                $fatal(1, "Store side effect appeared before MEM registration");
            end
            @(posedge clk);
            #0.1;
            if (!store_event || (store_pc != expected_pc) ||
                (store_addr != expected_addr) || (store_wen != expected_wen) ||
                (store_wdata != expected_wdata) || (commit_valid != 2'b11) ||
                (commit_wen != expected_commit_wen) ||
                (retire_count != 2) || exception_valid) begin
                $fatal(1, "dual Store MEM commit mismatch");
            end
            if (expected_commit_wen[0] &&
                ((commit_waddr0 != expected_simple_rd) ||
                 (commit_wdata0 != expected_simple_data))) begin
                $fatal(1, "lane0 simple result beside Store mismatch");
            end
            if (expected_commit_wen[1] &&
                ((commit_waddr1 != expected_simple_rd) ||
                 (commit_wdata1 != expected_simple_data))) begin
                $fatal(1, "lane1 simple result beside Store mismatch");
            end
            @(posedge clk);
            #0.1;
            if (busy || block_legacy || store_event ||
                (store_commit_count != (stores_before + 1))) begin
                $fatal(1, "dual Store did not commit exactly once");
            end
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            load_request_count <= 0;
            store_commit_count <= 0;
            lsu_pair_count <= 0;
        end else begin
            if (dmem_load_en) load_request_count <= load_request_count + 1;
            if (store_event) store_commit_count <= store_commit_count + 1;
            if (lsu_pair_event) lsu_pair_count <= lsu_pair_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        redirect = 1'b0;
        launch_valid = 1'b0;
        launch_bundle = '0;
        dmem_rdata = 32'b0;
        dmem_rvalid = 1'b0;
        lsu_port_ready = 1'b1;
        seed_wen = 1'b0;
        seed_waddr = 5'b0;
        seed_wdata = 32'b0;
        inspect_addr0 = 5'b0;
        inspect_addr1 = 5'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;
        seed_reg(5'd1, 32'h0000_1000);
        seed_reg(5'd2, 32'haabb_ccdd);

        // simple + LW: one request, four execution beats, registered MEM commit.
        launch_lsu_pair(enc_i(12'd7, 5'd0, 3'b000, 5'd6, 7'b0010011),
                        enc_i(12'd0, 5'd1, 3'b010, 5'd5, 7'b0000011),
                        32'h0000_1000, 32'd10);
        complete_active_load(32'h0000_1000, 32'h1122_3344,
                             5'd6, 32'd7, 5'd5, 32'h1122_3344);
        expect_reg(5'd6, 32'd7, "simple before lane1 Load");
        expect_reg(5'd5, 32'h1122_3344, "lane1 Load result");

        // LW + simple: the resident waits unstarted while the data port is owned.
        lsu_port_ready = 1'b0;
        launch_lsu_pair(enc_i(12'd4, 5'd1, 3'b010, 5'd7, 7'b0000011),
                        enc_i(12'd9, 5'd0, 3'b000, 5'd8, 7'b0010011),
                        32'h0000_1100, 32'd20);
        repeat (2) begin
            @(posedge clk);
            #0.1;
            if (dmem_load_en || !busy || !block_legacy || commit_valid) begin
                $fatal(1, "blocked dual LSU crossed single-port ownership");
            end
        end
        @(negedge clk);
        lsu_port_ready = 1'b1;
        #0.1;
        complete_active_load(32'h0000_1004, 32'h5566_7788,
                             5'd7, 32'h5566_7788, 5'd8, 32'd9);
        expect_reg(5'd7, 32'h5566_7788, "lane0 Load result");
        expect_reg(5'd8, 32'd9, "simple after lane0 Load");

        // simple + SW: physical write occurs only at the registered MEM boundary.
        launch_lsu_pair(enc_i(12'd11, 5'd0, 3'b000, 5'd9, 7'b0010011),
                        enc_s(12'd8, 5'd2, 5'd1, 3'b010),
                        32'h0000_1200, 32'd30);
        complete_store(32'h0000_1204, 32'h0000_1008, 4'b1111,
                       32'haabb_ccdd, 2'b01, 5'd9, 32'd11);
        expect_reg(5'd9, 32'd11, "simple before lane1 Store");

        // A normal registered MEM resident releases on its commit edge.  A
        // younger simple pair may synchronously read the retiring lane0 value
        // through the 2W-to-4R bypass without opening an age gap.
        launch_lsu_pair(enc_i(12'd21, 5'd0, 3'b000, 5'd16, 7'b0010011),
                        enc_s(12'd12, 5'd2, 5'd1, 3'b010),
                        32'h0000_1250, 32'd35);
        @(posedge clk);
        #0.1;
        @(posedge clk);
        #0.1;
        if (!store_event || (store_addr != 32'h0000_100c) ||
            (commit_valid != 2'b11) || (commit_wen != 2'b01) ||
            !launch_ready) begin
            $fatal(1, "registered MEM resident did not expose its release edge");
        end
        @(negedge clk);
        launch_bundle = make_pair(
            enc_i(12'd1, 5'd16, 3'b000, 5'd17, 7'b0010011),
            enc_i(12'd23, 5'd0, 3'b000, 5'd18, 7'b0010011),
            32'h0000_1258, 32'd37);
        launch_valid = 1'b1;
        #0.1;
        if (!launch_ready || !rf_read_en || lsu_pair_event) begin
            $fatal(1, "younger simple pair missed the MEM release edge");
        end
        @(posedge clk);
        #0.1;
        launch_valid = 1'b0;
        if (store_event || (commit_valid != 2'b11) ||
            (commit_wdata0 != 32'd22) || (commit_wdata1 != 32'd23)) begin
            $fatal(1, "same-edge MEM write-to-read bypass mismatch");
        end
        @(posedge clk);
        #0.1;
        expect_reg(5'd16, 32'd21, "retiring simple beside Store");
        expect_reg(5'd17, 32'd22, "MEM-release dependent simple");
        expect_reg(5'd18, 32'd23, "MEM-release independent simple");

        // SB + simple: lane0 Store and lane1 result retire together in age order.
        launch_lsu_pair(enc_s(12'd1, 5'd2, 5'd1, 3'b000),
                        enc_i(12'd12, 5'd0, 3'b000, 5'd10, 7'b0010011),
                        32'h0000_1300, 32'd40);
        complete_store(32'h0000_1300, 32'h0000_1001, 4'b0010,
                       32'hdddd_dddd, 2'b10, 5'd10, 32'd12);
        expect_reg(5'd10, 32'd12, "simple after lane0 Store");

        // Misaligned lane0 Load faults before both lanes: no retirement or write.
        launch_lsu_pair(enc_i(12'd2, 5'd1, 3'b010, 5'd11, 7'b0000011),
                        enc_i(12'd13, 5'd0, 3'b000, 5'd12, 7'b0010011),
                        32'h0000_1400, 32'd50);
        if (dmem_load_en) $fatal(1, "misaligned Load emitted a request");
        @(posedge clk);
        #0.1;
        @(posedge clk);
        #0.1;
        if (!exception_valid || (exception_code != `EXC_LAM) ||
            (exception_pc != 32'h0000_1400) ||
            (exception_mtval != 32'h0000_1002) ||
            (commit_valid != 2'b00) || store_event) begin
            $fatal(1, "lane0 LAM age suppression mismatch");
        end
        @(posedge clk);
        #0.1;
        expect_reg(5'd11, 32'b0, "faulted lane0 Load");
        expect_reg(5'd12, 32'b0, "younger simple after lane0 LAM");

        // Misaligned lane1 Store lets the older simple retire, then raises SAM.
        launch_lsu_pair(enc_i(12'd14, 5'd0, 3'b000, 5'd13, 7'b0010011),
                        enc_s(12'd1, 5'd2, 5'd1, 3'b001),
                        32'h0000_1500, 32'd60);
        @(posedge clk);
        #0.1;
        @(posedge clk);
        #0.1;
        if (!exception_valid || (exception_code != `EXC_SAM) ||
            (exception_pc != 32'h0000_1504) ||
            (exception_mtval != 32'h0000_1001) ||
            (commit_valid != 2'b01) || (commit_wen != 2'b01) ||
            (commit_waddr0 != 5'd13) || (commit_wdata0 != 32'd14) ||
            store_event) begin
            $fatal(1, "lane1 SAM partial retirement mismatch");
        end
        @(posedge clk);
        #0.1;
        expect_reg(5'd13, 32'd14, "older simple before lane1 SAM");

        // A killed in-flight Load cannot commit; its late response is drained
        // before either backend is allowed to issue again.
        launch_lsu_pair(enc_i(12'd15, 5'd0, 3'b000, 5'd14, 7'b0010011),
                        enc_i(12'd12, 5'd1, 3'b010, 5'd15, 7'b0000011),
                        32'h0000_1600, 32'd70);
        if (!dmem_load_en) $fatal(1, "kill test Load did not request");
        @(posedge clk);
        #0.1;
        @(negedge clk);
        redirect = 1'b1;
        @(posedge clk);
        #0.1;
        redirect = 1'b0;
        if (!busy || !block_legacy || launch_ready || commit_valid) begin
            $fatal(1, "killed Load did not enter stale-response quarantine");
        end
        @(negedge clk);
        dmem_rdata = 32'hdead_beef;
        dmem_rvalid = 1'b1;
        @(posedge clk);
        #0.1;
        dmem_rvalid = 1'b0;
        if (busy || block_legacy || commit_valid || exception_valid ||
            store_event) begin
            $fatal(1, "stale Load response escaped quarantine");
        end
        expect_reg(5'd14, 32'b0, "killed paired simple");
        expect_reg(5'd15, 32'b0, "killed Load destination");

        if ((load_request_count != 3) || (store_commit_count != 3) ||
            (lsu_pair_count != 8)) begin
            $fatal(1, "A6.3 event counts mismatch loads=%0d stores=%0d pairs=%0d",
                   load_request_count, store_commit_count, lsu_pair_count);
        end

        $display("A6 LSU PAIR TEST PASSED");
        $finish;
    end

endmodule
