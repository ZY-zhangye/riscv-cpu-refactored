`timescale 1ns/1ps
`include "defines.svh"

module tb_if_sync_btb_single;
    logic clk;
    logic rst_n;
    logic [31:0] pc_out;
    logic inst_ren;
    logic [31:0] inst_in;
    logic ds_allowin;
    logic fs_to_ds_valid;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;
    logic br_taken;
    logic [31:0] br_target;
    logic bp_update_valid;
    logic [31:0] bp_update_pc;
    logic bp_update_taken;
    logic [31:0] bp_update_target;
    logic bp_update_is_jalr;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic exception_flag;
    logic [31:0] exception_addr;

    logic [31:0] out_inst;
    logic [31:0] out_pc;
    logic out_pred_taken;
    logic [31:0] out_pred_target;
    logic [`FS_DS_WIDTH-1:0] held_bus;

    assign {out_inst, out_pc, out_pred_taken, out_pred_target} =
        fs_to_ds_bus;

    if_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .inst_ren(inst_ren),
        .inst_in(inst_in),
        .ds_allowin(ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        .br_taken(br_taken),
        .br_target(br_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    function automatic logic [31:0] instruction_for_pc(
        input logic [31:0] pc
    );
        instruction_for_pc = 32'hA5A5_0000 ^ pc;
    endfunction

    always #5 clk = ~clk;

    // Same fixed one-cycle behavior as soc_inst_ram and the board XPM IROM.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            inst_in <= `NOP_INST;
        end else if (inst_ren) begin
            inst_in <= instruction_for_pc(pc_out);
        end
    end

    task automatic drive_update(
        input logic [31:0] pc,
        input logic taken,
        input logic [31:0] target,
        input logic is_jalr
    );
        begin
            @(negedge clk);
            bp_update_valid = 1'b1;
            bp_update_pc = pc;
            bp_update_taken = taken;
            bp_update_target = target;
            bp_update_is_jalr = is_jalr;
            @(negedge clk);
            bp_update_valid = 1'b0;
            bp_update_is_jalr = 1'b0;
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic redirect_branch(input logic [31:0] target);
        begin
            @(negedge clk);
            br_taken = 1'b1;
            br_target = target;
            @(negedge clk);
            br_taken = 1'b0;
        end
    endtask

    task automatic redirect_exception(input logic [31:0] target);
        begin
            @(negedge clk);
            exception_flag = 1'b1;
            exception_addr = target;
            @(negedge clk);
            exception_flag = 1'b0;
        end
    endtask

    task automatic expect_uop(
        input logic [31:0] expected_pc,
        input logic expected_taken,
        input logic [31:0] expected_target
    );
        integer wait_count;
        begin
            wait_count = 0;
            while (!fs_to_ds_valid && wait_count < 30) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end
            if (!fs_to_ds_valid) begin
                $fatal(1, "timeout waiting for pc=%08h", expected_pc);
            end
            if (out_pc !== expected_pc) begin
                $fatal(1, "pc mismatch expected=%08h actual=%08h",
                       expected_pc, out_pc);
            end
            if (out_inst !== instruction_for_pc(expected_pc)) begin
                $fatal(1, "instruction/pc mismatch pc=%08h inst=%08h",
                       out_pc, out_inst);
            end
            if (out_pred_taken !== expected_taken) begin
                $fatal(1, "prediction mismatch pc=%08h expected=%0d actual=%0d",
                       out_pc, expected_taken, out_pred_taken);
            end
            if (expected_taken && out_pred_target !== expected_target) begin
                $fatal(1, "target mismatch pc=%08h expected=%08h actual=%08h",
                       out_pc, expected_target, out_pred_target);
            end
            if (fs_exc_bus !== '0) begin
                $fatal(1, "unexpected IF exception metadata pc=%08h", out_pc);
            end
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic expect_counter(
        input logic [31:0] pc,
        input logic [1:0] expected
    );
        logic [6:0] index;
        logic [1:0] actual;
        begin
            index = pc[8:2];
            actual = dut.bp_update_mem[index][33:32];
            if (actual !== expected) begin
                $fatal(1, "counter mismatch pc=%08h expected=%b actual=%b",
                       pc, expected, actual);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ds_allowin = 1'b1;
        br_taken = 1'b0;
        br_target = '0;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_taken = 1'b0;
        bp_update_target = '0;
        bp_update_is_jalr = 1'b0;
        exception_flag = 1'b0;
        exception_addr = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Cold sequential fetch sustains one aligned request/response per cycle.
        expect_uop(`PC_START, 1'b0, 32'b0);
        if (!inst_ren) begin
            $fatal(1, "steady-state fetch did not launch a replacement request");
        end
        expect_uop(`PC_START + 32'd4, 1'b0, 32'b0);
        expect_uop(`PC_START + 32'd8, 1'b0, 32'b0);

        // Counter allocation, saturation and decay.
        drive_update(32'h0000_0100, 1'b1, 32'h0000_0180, 1'b0);
        expect_counter(32'h0000_0100, 2'b10);
        drive_update(32'h0000_0100, 1'b1, 32'h0000_0180, 1'b0);
        expect_counter(32'h0000_0100, 2'b11);
        drive_update(32'h0000_0100, 1'b1, 32'h0000_0180, 1'b0);
        expect_counter(32'h0000_0100, 2'b11);
        drive_update(32'h0000_0100, 1'b0, 32'h0000_0180, 1'b0);
        expect_counter(32'h0000_0100, 2'b10);
        drive_update(32'h0000_0100, 1'b0, 32'h0000_0180, 1'b0);
        expect_counter(32'h0000_0100, 2'b01);

        redirect_branch(32'h0000_0100);
        expect_uop(32'h0000_0100, 1'b0, 32'b0);

        // A same-index replacement invalidates the old tag's prediction.
        drive_update(32'h0000_0300, 1'b1, 32'h0000_0380, 1'b0);
        redirect_exception(32'h0000_0100);
        expect_uop(32'h0000_0100, 1'b0, 32'b0);
        redirect_exception(32'h0000_0300);
        expect_uop(32'h0000_0300, 1'b1, 32'h0000_0380);

        // Registered training and a request to the same index are write-through.
        @(negedge clk);
        exception_flag = 1'b1;
        exception_addr = 32'h0000_0440;
        bp_update_valid = 1'b1;
        bp_update_pc = 32'h0000_0440;
        bp_update_taken = 1'b1;
        bp_update_target = 32'h0000_04C0;
        bp_update_is_jalr = 1'b0;
        @(negedge clk);
        exception_flag = 1'b0;
        bp_update_valid = 1'b0;
        expect_uop(32'h0000_0440, 1'b1, 32'h0000_04C0);

        // JALR updates remain excluded from this BTB.
        drive_update(32'h0000_0700, 1'b1, 32'h0000_0780, 1'b1);
        redirect_exception(32'h0000_0700);
        expect_uop(32'h0000_0700, 1'b0, 32'b0);

        // Decode backpressure holds the complete response and stops requests.
        redirect_exception(32'h0000_0A00);
        @(negedge clk);
        ds_allowin = 1'b0;
        while (!fs_to_ds_valid) begin
            @(negedge clk);
        end
        held_bus = fs_to_ds_bus;
        repeat (4) begin
            @(negedge clk);
            if (!fs_to_ds_valid || fs_to_ds_bus !== held_bus) begin
                $fatal(1, "IF response changed while Decode was stalled");
            end
            if (inst_ren) begin
                $fatal(1, "IF launched a request while holding a response");
            end
        end
        ds_allowin = 1'b1;
        expect_uop(32'h0000_0A00, 1'b0, 32'b0);
        expect_uop(32'h0000_0A04, 1'b0, 32'b0);

        // Redirect kills a held response even while Decode remains stalled.
        ds_allowin = 1'b0;
        while (!fs_to_ds_valid) begin
            @(negedge clk);
        end
        @(negedge clk);
        br_taken = 1'b1;
        br_target = 32'h0000_0C00;
        #1;
        if (fs_to_ds_valid) begin
            $fatal(1, "redirect did not suppress the held response immediately");
        end
        @(negedge clk);
        br_taken = 1'b0;
        ds_allowin = 1'b1;
        expect_uop(32'h0000_0C00, 1'b0, 32'b0);

        // Simultaneous exception and branch redirect must select the exception.
        @(negedge clk);
        exception_flag = 1'b1;
        exception_addr = 32'h0000_0D00;
        br_taken = 1'b1;
        br_target = 32'h0000_0E00;
        @(negedge clk);
        exception_flag = 1'b0;
        br_taken = 1'b0;
        expect_uop(32'h0000_0D00, 1'b0, 32'b0);

        $display("IF SYNC 128-ENTRY BTB TEST PASSED");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "tb_if_sync_btb_single timeout");
    end

endmodule
