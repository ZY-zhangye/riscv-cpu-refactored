`timescale 1ns/1ps
`include "defines.svh"

module tb_a6_muldiv_pair;
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
    logic dependency_event;
    logic pending_stall_event;
    logic muldiv_pair_event;

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

    integer mul_start_count;
    integer mul_done_count;
    integer div_start_count;
    integer div_done_count;
    integer pair_event_count;
    integer pair_commit_count;

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
        .block_legacy(block_legacy), .rf_read_en(rf_read_en),
        .rf_raddr0(rf_raddr0), .rf_raddr1(rf_raddr1),
        .rf_raddr2(rf_raddr2), .rf_raddr3(rf_raddr3),
        .rf_rdata0(rf_rdata0), .rf_rdata1(rf_rdata1),
        .rf_rdata2(rf_rdata2), .rf_rdata3(rf_rdata3),
        .dmem_rdata(32'b0), .dmem_rvalid(1'b0),
        .lsu_port_ready(1'b1), .dmem_load_en(), .dmem_load_addr(),
        .store_event(), .store_pc(), .store_addr(), .store_wen(),
        .store_wdata(), .commit_valid(commit_valid),
        .commit_wen(commit_wen), .commit_waddr0(commit_waddr0),
        .commit_waddr1(commit_waddr1), .commit_wdata0(commit_wdata0),
        .commit_wdata1(commit_wdata1), .retire_count(retire_count),
        .dependency_event(dependency_event),
        .pending_stall_event(pending_stall_event),
        .commit_pc0(), .commit_pc1(), .commit_inst0(), .commit_inst1(),
        .commit_age0(), .commit_age1(), .commit_epoch0(), .commit_epoch1(),
        .branch_event(), .branch_mispredict_event(), .branch_redirect(),
        .branch_redirect_target(), .bp_update_valid(), .bp_update_pc(),
        .bp_update_taken(), .bp_update_target(), .bp_update_type(),
        .lane1_control_event(), .control0_simple_event(), .lsu_pair_event(),
        .muldiv_pair_event(muldiv_pair_event),
        .exception_valid(), .exception_code(), .exception_pc(),
        .exception_mtval()
    );

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        enc_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] enc_addi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        enc_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [`FETCH_UOP_WIDTH-1:0] make_uop(
        input logic [31:0] inst,
        input logic [31:0] pc,
        input logic [31:0] age
    );
        make_uop = {2'd2, age, inst, pc, 1'b0, 32'b0,
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

    function automatic logic [`ISSUE_BUNDLE_WIDTH-1:0] make_single(
        input logic [31:0] inst0,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        make_single = {1'b0, 1'b1, {`FETCH_UOP_WIDTH{1'b0}},
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

    task automatic run_single_mul(
        input logic [31:0] inst0,
        input logic [4:0] expected_rd0,
        input logic [31:0] expected_data0,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        integer starts_before;
        integer dones_before;
        integer events_before;
        integer commits_before;
        integer guard;
        begin
            starts_before = mul_start_count;
            dones_before = mul_done_count;
            events_before = pair_event_count;
            commits_before = pair_commit_count;
            if (busy) $fatal(1, "MUL singleton launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_single(inst0, pc0, age0);
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en || muldiv_pair_event) begin
                $fatal(1, "MUL singleton launch or pair-event mismatch");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
            guard = 0;
            while (commit_valid == 2'b00) begin
                @(posedge clk);
                #0.1;
                guard = guard + 1;
                if (guard > 12) $fatal(1, "MUL singleton timed out");
            end
            if ((commit_valid != 2'b01) || (retire_count != 1) ||
                (commit_wen != 2'b01) ||
                (commit_waddr0 != expected_rd0) ||
                (commit_wdata0 != expected_data0)) begin
                $fatal(1, "MUL singleton precise commit mismatch");
            end
            @(posedge clk);
            #0.1;
            expect_reg(expected_rd0, expected_data0, "MUL singleton");
            if ((mul_start_count != (starts_before + 1)) ||
                (mul_done_count != (dones_before + 1)) ||
                (pair_event_count != events_before) ||
                (pair_commit_count != commits_before)) begin
                $fatal(1, "MUL singleton event ownership mismatch");
            end
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

    task automatic launch_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        begin
            if (busy) $fatal(1, "MUL/DIV pair launched into a busy resident");
            @(negedge clk);
            launch_bundle = make_pair(inst0, inst1, pc0, age0);
            launch_valid = 1'b1;
            #0.1;
            if (!launch_ready || !rf_read_en || !muldiv_pair_event) begin
                $fatal(1, "MUL/DIV pair was not accepted atomically");
            end
            @(posedge clk);
            #0.1;
            launch_valid = 1'b0;
            if (!busy || !block_legacy || launch_ready ||
                (commit_valid != 2'b00)) begin
                $fatal(1, "MUL/DIV pair did not establish a pending resident");
            end
        end
    endtask

    task automatic run_pair(
        input string name,
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic [4:0] expected_rd0,
        input logic [31:0] expected_data0,
        input logic [4:0] expected_rd1,
        input logic [31:0] expected_data1,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        integer mul_starts_before;
        integer mul_dones_before;
        integer div_starts_before;
        integer div_dones_before;
        integer events_before;
        integer commits_before;
        integer wait_cycles;
        logic [2:0] operation;
        logic operation_is_div;
        logic [31:0] stable_data0;
        logic [31:0] stable_data1;
        begin
            operation = (inst0[31:25] == 7'b0000001) ?
                        inst0[14:12] : inst1[14:12];
            operation_is_div = operation[2];
            mul_starts_before = mul_start_count;
            mul_dones_before = mul_done_count;
            div_starts_before = div_start_count;
            div_dones_before = div_done_count;
            events_before = pair_event_count;
            commits_before = pair_commit_count;

            launch_pair(inst0, inst1, pc0, age0);
            wait_cycles = 0;
            while (commit_valid == 2'b00) begin
                @(posedge clk);
                #0.1;
                wait_cycles = wait_cycles + 1;
                if ((commit_valid == 2'b00) &&
                    (!busy || !block_legacy || launch_ready)) begin
                    $fatal(1, "%s released either lane before MUL/DIV done", name);
                end
                if (wait_cycles > 40) begin
                    $fatal(1, "%s timed out waiting for shared-unit completion", name);
                end
            end

            if ((commit_valid != 2'b11) || (retire_count != 2'd2) ||
                (commit_wen != 2'b11) ||
                (commit_waddr0 != expected_rd0) ||
                (commit_waddr1 != expected_rd1) ||
                (commit_wdata0 != expected_data0) ||
                (commit_wdata1 != expected_data1)) begin
                $fatal(1, "%s precise pair commit mismatch", name);
            end
            if (block_legacy || !launch_ready) begin
                $fatal(1, "%s did not expose the completion-edge handoff", name);
            end

            stable_data0 = commit_wdata0;
            stable_data1 = commit_wdata1;
            #2;
            if ((commit_valid != 2'b11) ||
                (commit_wdata0 != stable_data0) ||
                (commit_wdata1 != stable_data1)) begin
                $fatal(1, "%s result changed inside the completion cycle", name);
            end
            @(negedge clk);
            #0.1;
            if ((commit_wdata0 != stable_data0) ||
                (commit_wdata1 != stable_data1)) begin
                $fatal(1, "%s result was not stable through retirement", name);
            end
            @(posedge clk);
            #0.1;

            expect_reg(expected_rd0, expected_data0, {name, " lane0"});
            expect_reg(expected_rd1, expected_data1, {name, " lane1"});
            if ((pair_event_count != (events_before + 1)) ||
                (pair_commit_count != (commits_before + 1))) begin
                $fatal(1, "%s event or retirement pulse was not exactly once", name);
            end
            if (operation_is_div) begin
                if ((div_start_count != (div_starts_before + 1)) ||
                    (div_done_count != (div_dones_before + 1)) ||
                    (mul_start_count != mul_starts_before) ||
                    (mul_done_count != mul_dones_before)) begin
                    $fatal(1, "%s divider start/done ownership mismatch", name);
                end
            end else begin
                if ((mul_start_count != (mul_starts_before + 1)) ||
                    (mul_done_count != (mul_dones_before + 1)) ||
                    (div_start_count != div_starts_before) ||
                    (div_done_count != div_dones_before)) begin
                    $fatal(1, "%s multiplier start/done ownership mismatch", name);
                end
            end
        end
    endtask

    task automatic kill_pair(
        input string name,
        input logic [31:0] inst0,
        input logic [31:0] inst1,
        input logic use_divider,
        input logic [4:0] killed_rd0,
        input logic [4:0] killed_rd1,
        input logic [31:0] pc0,
        input logic [31:0] age0
    );
        integer starts_before;
        integer dones_before;
        integer guard;
        begin
            starts_before = use_divider ? div_start_count : mul_start_count;
            dones_before = use_divider ? div_done_count : mul_done_count;
            launch_pair(inst0, inst1, pc0, age0);
            guard = 0;
            while (!(use_divider ? dut.div_busy : dut.mul_busy)) begin
                @(posedge clk);
                #0.1;
                guard = guard + 1;
                if (guard > 4) $fatal(1, "%s never started", name);
            end
            @(negedge clk);
            redirect = 1'b1;
            #0.1;
            if (commit_valid != 2'b00) begin
                $fatal(1, "%s exposed a result before redirect kill", name);
            end
            @(posedge clk);
            #0.1;
            if (busy || block_legacy || (commit_valid != 2'b00) ||
                dut.mul_busy || dut.div_busy) begin
                $fatal(1, "%s did not atomically kill both lanes", name);
            end
            @(negedge clk);
            redirect = 1'b0;
            repeat (3) begin
                @(posedge clk);
                #0.1;
                if (commit_valid != 2'b00) begin
                    $fatal(1, "%s leaked a late completion", name);
                end
            end
            if ((use_divider ? div_start_count : mul_start_count) !=
                (starts_before + 1)) begin
                $fatal(1, "%s start pulse count mismatch", name);
            end
            if ((use_divider ? div_done_count : mul_done_count) !=
                dones_before) begin
                $fatal(1, "%s killed unit emitted done", name);
            end
            expect_reg(killed_rd0, 32'b0, {name, " killed lane0"});
            expect_reg(killed_rd1, 32'b0, {name, " killed lane1"});
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mul_start_count <= 0;
            mul_done_count <= 0;
            div_start_count <= 0;
            div_done_count <= 0;
            pair_event_count <= 0;
            pair_commit_count <= 0;
        end else begin
            if (dut.mul_start) mul_start_count <= mul_start_count + 1;
            if (dut.mul_done) mul_done_count <= mul_done_count + 1;
            if (dut.div_start) div_start_count <= div_start_count + 1;
            if (dut.div_done) div_done_count <= div_done_count + 1;
            if (muldiv_pair_event) pair_event_count <= pair_event_count + 1;
            if (commit_valid == 2'b11) begin
                pair_commit_count <= pair_commit_count + 1;
            end
        end
    end

    initial begin
        integer starts_before;
        integer dones_before;
        integer commits_before;
        integer guard;

        clk = 1'b0;
        rst_n = 1'b0;
        redirect = 1'b0;
        launch_valid = 1'b0;
        launch_bundle = '0;
        seed_wen = 1'b0;
        seed_waddr = 5'b0;
        seed_wdata = 32'b0;
        inspect_addr0 = 5'b0;
        inspect_addr1 = 5'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // All eight RV32M operations alternate lane ownership.
        seed_reg(5'd1, 32'd7);
        seed_reg(5'd2, 32'd9);
        run_pair("MUL lane1",
                 enc_addi(12'd5, 5'd0, 5'd11),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd10),
                 5'd11, 32'd5, 5'd10, 32'd63, 32'h1000, 32'd1);

        seed_reg(5'd1, 32'hffff_fffe);
        seed_reg(5'd2, 32'd3);
        run_pair("MULH lane0",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b001, 5'd12),
                 enc_addi(12'd6, 5'd0, 5'd13),
                 5'd12, 32'hffff_ffff, 5'd13, 32'd6,
                 32'h1010, 32'd3);
        run_pair("MULHSU lane1",
                 enc_addi(12'd7, 5'd0, 5'd15),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b010, 5'd14),
                 5'd15, 32'd7, 5'd14, 32'hffff_ffff,
                 32'h1020, 32'd5);
        run_pair("MULHU lane0",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b011, 5'd16),
                 enc_addi(12'd8, 5'd0, 5'd17),
                 5'd16, 32'd2, 5'd17, 32'd8,
                 32'h1030, 32'd7);

        seed_reg(5'd1, 32'hffff_ffec);
        seed_reg(5'd2, 32'd3);
        run_pair("DIV lane1",
                 enc_addi(12'd9, 5'd0, 5'd19),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd18),
                 5'd19, 32'd9, 5'd18, 32'hffff_fffa,
                 32'h1040, 32'd9);
        seed_reg(5'd1, 32'd20);
        run_pair("DIVU lane0",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd20),
                 enc_addi(12'd10, 5'd0, 5'd21),
                 5'd20, 32'd6, 5'd21, 32'd10,
                 32'h1050, 32'd11);
        seed_reg(5'd1, 32'hffff_ffec);
        run_pair("REM lane1",
                 enc_addi(12'd11, 5'd0, 5'd23),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd22),
                 5'd23, 32'd11, 5'd22, 32'hffff_fffe,
                 32'h1060, 32'd13);
        seed_reg(5'd1, 32'd20);
        run_pair("REMU lane0",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b111, 5'd24),
                 enc_addi(12'd12, 5'd0, 5'd25),
                 5'd24, 32'd2, 5'd25, 32'd12,
                 32'h1070, 32'd15);

        // Architectural DIV/REM special cases complete through the same pair
        // boundary even though the divider can answer immediately.
        seed_reg(5'd1, 32'h1234_5678);
        seed_reg(5'd2, 32'b0);
        run_pair("DIV by zero",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd3),
                 enc_addi(12'd13, 5'd0, 5'd4),
                 5'd3, 32'hffff_ffff, 5'd4, 32'd13,
                 32'h1080, 32'd17);
        run_pair("REM by zero",
                 enc_addi(12'd14, 5'd0, 5'd6),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd5),
                 5'd6, 32'd14, 5'd5, 32'h1234_5678,
                 32'h1090, 32'd19);
        seed_reg(5'd1, 32'h8000_0000);
        seed_reg(5'd2, 32'hffff_ffff);
        run_pair("DIV overflow",
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd7),
                 enc_addi(12'd15, 5'd0, 5'd8),
                 5'd7, 32'h8000_0000, 5'd8, 32'd15,
                 32'h10a0, 32'd21);
        run_pair("REM overflow",
                 enc_addi(12'd16, 5'd0, 5'd10),
                 enc_r(7'b0000001, 5'd2, 5'd1, 3'b110, 5'd9),
                 5'd10, 32'd16, 5'd9, 32'b0,
                 32'h10b0, 32'd23);

        // A lane0-only MUL reuses the same resident but must not increment the
        // architectural MULDIV-pair event or manufacture a lane1 retirement.
        seed_reg(5'd1, 32'd6);
        seed_reg(5'd2, 32'd7);
        run_single_mul(enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd26),
                       5'd26, 32'd42, 32'h10b8, 32'd24);

        // External redirects kill the resident and suppress both lane writes.
        seed_reg(5'd1, 32'd6);
        seed_reg(5'd2, 32'd7);
        kill_pair("MUL redirect",
                  enc_addi(12'd1, 5'd0, 5'd28),
                  enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd29),
                  1'b0, 5'd28, 5'd29, 32'h10c0, 32'd25);
        kill_pair("DIV redirect",
                  enc_r(7'b0000001, 5'd2, 5'd1, 3'b100, 5'd30),
                  enc_addi(12'd2, 5'd0, 5'd31),
                  1'b1, 5'd30, 5'd31, 32'h10d0, 32'd27);

        // Completion-edge launch consumes both results through the 2W->4R
        // bypass; before done the scoreboard keeps the younger pair pending.
        starts_before = mul_start_count;
        dones_before = mul_done_count;
        commits_before = pair_commit_count;
        launch_pair(enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd20),
                    enc_addi(12'd4, 5'd0, 5'd21),
                    32'h10e0, 32'd29);
        @(negedge clk);
        launch_bundle = make_pair(enc_addi(12'd1, 5'd20, 5'd22),
                                  enc_addi(12'd2, 5'd21, 5'd23),
                                  32'h10e8, 32'd31);
        launch_valid = 1'b1;
        #0.1;
        if (launch_ready || !dependency_event || !pending_stall_event) begin
            $fatal(1, "dependent pair was not held behind pending MUL/DIV");
        end
        guard = 0;
        while (!launch_ready) begin
            @(posedge clk);
            #0.1;
            guard = guard + 1;
            if (!launch_ready && (commit_valid != 2'b00)) begin
                $fatal(1, "pending dependent pair observed premature commit");
            end
            if (guard > 12) $fatal(1, "completion-edge launch timed out");
        end
        if ((commit_valid != 2'b11) || !rf_read_en ||
            (commit_waddr0 != 5'd20) || (commit_wdata0 != 32'd42) ||
            (commit_waddr1 != 5'd21) || (commit_wdata1 != 32'd4)) begin
            $fatal(1, "producer pair or same-edge RF request mismatch");
        end
        @(posedge clk);
        #0.1;
        launch_valid = 1'b0;
        if ((commit_valid != 2'b11) || (commit_waddr0 != 5'd22) ||
            (commit_wdata0 != 32'd43) || (commit_waddr1 != 5'd23) ||
            (commit_wdata1 != 32'd6)) begin
            $fatal(1, "completion-edge dependent bypass produced wrong result");
        end
        @(posedge clk);
        #0.1;
        expect_reg(5'd20, 32'd42, "producer MUL");
        expect_reg(5'd21, 32'd4, "producer simple");
        expect_reg(5'd22, 32'd43, "dependent lane0");
        expect_reg(5'd23, 32'd6, "dependent lane1");
        if ((mul_start_count != (starts_before + 1)) ||
            (mul_done_count != (dones_before + 1)) ||
            (pair_commit_count != (commits_before + 2))) begin
            $fatal(1, "completion-edge sequence pulse counts mismatch");
        end

        if (busy || block_legacy || (commit_valid != 2'b00)) begin
            $fatal(1, "A6.4 backend did not return idle");
        end
        $display("A6 MULDIV PAIR TEST PASSED");
        $finish;
    end

endmodule
