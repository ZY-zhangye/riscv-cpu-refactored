`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_if_sync_btb;
    logic clk;
    logic rst_n;
    logic [31:0] pc_out;
    logic [31:0] pc_out1;
    logic inst_ren;
    logic [31:0] inst_in;
    logic [31:0] inst_in1;
    logic [3:0] fetch_free_count;
    logic [1:0] fetch_push_count;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_push_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] fetch_push_uop1;
    logic frontend_redirect;
    logic br_taken;
    logic [31:0] br_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic [`BP_TYPE_WIDTH-1:0] bp_update_type;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic exception_flag;
    logic [31:0] exception_addr;

    logic [`FETCH_EPOCH_WIDTH-1:0] epoch0;
    logic [`FETCH_AGE_WIDTH-1:0] age0;
    logic [31:0] out_inst0;
    logic [31:0] out_pc0;
    logic out_pred_taken0;
    logic [31:0] out_pred_target0;
    logic [`BP_TYPE_WIDTH-1:0] out_pred_type0;
    logic out_btb_hit0;
    logic out_ras_valid0;
    logic [31:0] out_ras_target0;

    logic [`FETCH_EPOCH_WIDTH-1:0] epoch1;
    logic [`FETCH_AGE_WIDTH-1:0] age1;
    logic [31:0] out_inst1;
    logic [31:0] out_pc1;
    logic out_pred_taken1;
    logic [31:0] out_pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] out_pred_type1;
    logic out_btb_hit1;
    logic out_ras_valid1;
    logic [31:0] out_ras_target1;
    logic [`FETCH_AGE_WIDTH-1:0] last_age;
    logic have_last_age;
    logic [`FETCH_UOP_WIDTH-1:0] held_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] held_uop1;

    assign {epoch0, age0, out_inst0, out_pc0, out_pred_taken0,
            out_pred_target0, out_pred_type0, out_btb_hit0,
            out_ras_valid0, out_ras_target0} = fetch_push_uop0;
    assign {epoch1, age1, out_inst1, out_pc1, out_pred_taken1,
            out_pred_target1, out_pred_type1, out_btb_hit1,
            out_ras_valid1, out_ras_target1} = fetch_push_uop1;

    if_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .pc_out1(pc_out1),
        .inst_ren(inst_ren),
        .inst_in(inst_in),
        .inst_in1(inst_in1),
        .fetch_free_count(fetch_free_count),
        .fetch_push_count(fetch_push_count),
        .fetch_push_uop0(fetch_push_uop0),
        .fetch_push_uop1(fetch_push_uop1),
        .frontend_redirect(frontend_redirect),
        .br_taken(br_taken),
        .br_target(br_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_type(bp_update_type),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    function automatic logic [31:0] instruction_for_pc(input logic [31:0] pc);
        if (pc == 32'h0000_0B00) begin
            instruction_for_pc = 32'h0000_00EF; // jal x1, 0: RAS call
        end else begin
            instruction_for_pc = 32'hA5A5_0000 ^ pc;
        end
    endfunction

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            inst_in <= `NOP_INST;
            inst_in1 <= `NOP_INST;
        end else if (inst_ren) begin
            inst_in <= instruction_for_pc(pc_out);
            inst_in1 <= instruction_for_pc(pc_out1);
        end
    end

    task automatic train_entry(
        input logic [31:0] pc,
        input logic        taken,
        input logic [31:0] target,
        input logic [`BP_TYPE_WIDTH-1:0] kind
    );
        begin
            @(negedge clk);
            bp_update_valid = 1'b1;
            bp_update_pc = pc;
            bp_update_taken = taken;
            bp_update_target = target;
            bp_update_type = kind;
            @(negedge clk);
            bp_update_valid = 1'b0;
        end
    endtask

    task automatic redirect_to(input logic [31:0] pc);
        begin
            @(negedge clk);
            exception_flag = 1'b1;
            exception_addr = pc;
            @(negedge clk);
            if (!frontend_redirect) begin
                $fatal(1, "frontend redirect was not asserted");
            end
            exception_flag = 1'b0;
        end
    endtask

    task automatic redirect_and_update_same_request(
        input logic [31:0] pc,
        input logic [31:0] target
    );
        begin
            @(negedge clk);
            exception_flag = 1'b1;
            exception_addr = pc;
            @(negedge clk);
            exception_flag = 1'b0;
            bp_update_valid = 1'b1;
            bp_update_pc = pc;
            bp_update_taken = 1'b1;
            bp_update_target = target;
            bp_update_type = `BP_TYPE_JAL;
            @(negedge clk);
            bp_update_valid = 1'b0;
        end
    endtask

    task automatic expect_packet(
        input logic [31:0] expected_pc,
        input logic [1:0]  expected_count,
        input logic        expected_taken0,
        input logic [31:0] expected_target0,
        input logic        expected_taken1,
        input logic [31:0] expected_target1
    );
        integer wait_count;
        begin
            wait_count = 0;
            #1;
            while ((fetch_push_count == 0) && (wait_count < 30)) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            if (fetch_push_count == 0) begin
                $fatal(1, "timeout waiting for packet pc=%08h", expected_pc);
            end
            if (fetch_push_count !== expected_count) begin
                $fatal(1, "packet count mismatch pc=%08h expected=%0d actual=%0d",
                       expected_pc, expected_count, fetch_push_count);
            end
            if ((out_pc0 !== expected_pc) ||
                (out_inst0 !== instruction_for_pc(expected_pc))) begin
                $fatal(1, "lane0 tag mismatch expected pc=%08h actual pc=%08h inst=%08h",
                       expected_pc, out_pc0, out_inst0);
            end
            if (out_pred_taken0 !== expected_taken0) begin
                $fatal(1, "lane0 prediction mismatch pc=%08h", out_pc0);
            end
            if (expected_taken0 && (out_pred_target0 !== expected_target0)) begin
                $fatal(1, "lane0 target mismatch pc=%08h", out_pc0);
            end
            if (expected_count == 2) begin
                if ((out_pc1 !== (expected_pc + 32'd4)) ||
                    (out_inst1 !== instruction_for_pc(expected_pc + 32'd4))) begin
                    $fatal(1, "lane1 tag mismatch expected pc=%08h actual pc=%08h inst=%08h",
                           expected_pc + 32'd4, out_pc1, out_inst1);
                end
                if ((age1 !== (age0 + 1'b1)) || (epoch1 !== epoch0)) begin
                    $fatal(1, "lane age/epoch mismatch age0=%0d age1=%0d", age0, age1);
                end
                if (out_pred_taken1 !== expected_taken1) begin
                    $fatal(1, "lane1 prediction mismatch pc=%08h", out_pc1);
                end
                if (expected_taken1 && (out_pred_target1 !== expected_target1)) begin
                    $fatal(1, "lane1 target mismatch pc=%08h", out_pc1);
                end
            end
            if (have_last_age && (age0 <= last_age)) begin
                $fatal(1, "fetch age did not increase last=%0d current=%0d",
                       last_age, age0);
            end
            last_age = (expected_count == 2) ? age1 : age0;
            have_last_age = 1'b1;
            if (fs_exc_bus !== '0) begin
                $fatal(1, "unexpected IF exception metadata");
            end
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        fetch_free_count = 4'd8;
        br_taken = 1'b0;
        br_target = '0;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_taken = 1'b0;
        bp_update_target = '0;
        bp_update_type = `BP_TYPE_BRANCH;
        exception_flag = 1'b0;
        exception_addr = '0;
        last_age = '0;
        have_last_age = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        expect_packet(`PC_START, 2, 1'b0, 0, 1'b0, 0);

        train_entry(32'h0000_0100, 1'b1, 32'h0000_0200, `BP_TYPE_JAL);
        redirect_to(32'h0000_0100);
        expect_packet(32'h0000_0100, 1, 1'b1, 32'h0000_0200, 1'b0, 0);
        expect_packet(32'h0000_0200, 2, 1'b0, 0, 1'b0, 0);

        train_entry(32'h0000_0304, 1'b1, 32'h0000_0400, `BP_TYPE_BRANCH);
        redirect_to(32'h0000_0300);
        expect_packet(32'h0000_0300, 2, 1'b0, 0, 1'b1, 32'h0000_0400);
        expect_packet(32'h0000_0400, 2, 1'b0, 0, 1'b0, 0);

        redirect_and_update_same_request(32'h0000_0500, 32'h0000_0580);
        expect_packet(32'h0000_0500, 1, 1'b1, 32'h0000_0580, 1'b0, 0);

        train_entry(32'h0000_0600, 1'b1, 32'h0000_0680, `BP_TYPE_JALR);
        redirect_to(32'h0000_0600);
        expect_packet(32'h0000_0600, 1, 1'b1, 32'h0000_0680, 1'b0, 0);

        train_entry(32'h0000_0700, 1'b1, 32'hDEAD_BEEF, `BP_TYPE_RETURN);
        train_entry(32'h0000_0640, 1'b1, 32'h0000_0800, `BP_TYPE_CALL);
        redirect_to(32'h0000_0700);
        expect_packet(32'h0000_0700, 1, 1'b1, 32'h0000_0644, 1'b0, 0);

        redirect_to(32'h0000_0800);
        wait (inst_ren);
        @(negedge clk);
        exception_flag = 1'b1;
        exception_addr = 32'h0000_0900;
        @(negedge clk);
        exception_flag = 1'b0;
        expect_packet(32'h0000_0900, 2, 1'b0, 0, 1'b0, 0);

        // Whole response packet must remain stable until two FIFO slots exist.
        fetch_free_count = 4'd0;
        redirect_to(32'h0000_0A00);
        wait (dut.packet_valid);
        @(negedge clk);
        held_uop0 = fetch_push_uop0;
        held_uop1 = fetch_push_uop1;
        repeat (4) begin
            @(negedge clk);
            if ((fetch_push_count != 0) || !dut.packet_valid ||
                (fetch_push_uop0 !== held_uop0) ||
                (fetch_push_uop1 !== held_uop1)) begin
                $fatal(1, "IF1 packet changed or partially pushed under backpressure");
            end
        end
        fetch_free_count = 4'd8;
        expect_packet(32'h0000_0A00, 2, 1'b0, 0, 1'b0, 0);

        // A fetched call updates speculative RAS, and the simultaneous next
        // request must capture the post-push top.  Redirect restores committed.
        redirect_to(32'h0000_0B00);
        expect_packet(32'h0000_0B00, 2, 1'b0, 0, 1'b0, 0);
        wait (dut.req_valid);
        @(negedge clk);
        if ((dut.ras_count != (dut.ras_commit_count + 1'b1)) ||
            !dut.req_ras_valid ||
            (dut.req_ras_target != 32'h0000_0B04)) begin
            $fatal(1, "speculative RAS push/request bypass mismatch");
        end
        redirect_to(32'h0000_0C00);
        @(negedge clk);
        if (dut.ras_count != dut.ras_commit_count) begin
            $fatal(1, "redirect did not restore speculative RAS from committed state");
        end

        $display("IF SYNC BTB TEST PASSED");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "tb_if_sync_btb timeout");
    end

endmodule
