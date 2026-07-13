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
    logic ds_allowin;
    logic fs_to_ds_valid;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;
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

    logic [31:0] out_inst;
    logic [31:0] out_pc;
    logic out_pred_taken;
    logic [31:0] out_pred_target;
    logic [`FS_DS_WIDTH-1:0] held_bus;

    assign {out_inst, out_pc, out_pred_taken, out_pred_target} = fs_to_ds_bus;

    if_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .pc_out1(pc_out1),
        .inst_ren(inst_ren),
        .inst_in(inst_in),
        .inst_in1(inst_in1),
        .ds_allowin(ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
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
        instruction_for_pc = 32'hA5A5_0000 ^ pc;
    endfunction

    always #5 clk = ~clk;

    // Same one-cycle synchronous behavior as soc_inst_ram.
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

    task automatic expect_uop(
        input logic [31:0] expected_pc,
        input logic        expected_taken,
        input logic [31:0] expected_target
    );
        integer wait_count;
        begin
            wait_count = 0;
            while (!fs_to_ds_valid && (wait_count < 30)) begin
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
                $fatal(1, "instruction/tag mismatch pc=%08h inst=%08h",
                       out_pc, out_inst);
            end
            if (out_pred_taken !== expected_taken) begin
                $fatal(1, "prediction mismatch pc=%08h expected=%0d actual=%0d",
                       out_pc, expected_taken, out_pred_taken);
            end
            if (expected_taken && (out_pred_target !== expected_target)) begin
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
        bp_update_type = `BP_TYPE_BRANCH;
        exception_flag = 1'b0;
        exception_addr = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Cold BTB: one dual packet is serialized in age order.
        expect_uop(`PC_START, 1'b0, 32'b0);
        expect_uop(`PC_START + 32'd4, 1'b0, 32'b0);

        // Lane0 JAL prediction invalidates lane1 and redirects the next packet.
        train_entry(32'h0000_0100, 1'b1, 32'h0000_0200, `BP_TYPE_JAL);
        redirect_to(32'h0000_0100);
        expect_uop(32'h0000_0100, 1'b1, 32'h0000_0200);
        expect_uop(32'h0000_0200, 1'b0, 32'b0);

        // Lane1 taken: lane0 and lane1 both retire through the old single-uop IF/ID.
        train_entry(32'h0000_0304, 1'b1, 32'h0000_0400, `BP_TYPE_BRANCH);
        redirect_to(32'h0000_0300);
        expect_uop(32'h0000_0300, 1'b0, 32'b0);
        expect_uop(32'h0000_0304, 1'b1, 32'h0000_0400);
        expect_uop(32'h0000_0400, 1'b0, 32'b0);

        // BTB read/update collision is explicitly write-through.
        redirect_and_update_same_request(32'h0000_0500, 32'h0000_0580);
        expect_uop(32'h0000_0500, 1'b1, 32'h0000_0580);

        // Generic JALR uses the last resolved target stored in the BTB.
        train_entry(32'h0000_0600, 1'b1, 32'h0000_0680, `BP_TYPE_JALR);
        redirect_to(32'h0000_0600);
        expect_uop(32'h0000_0600, 1'b1, 32'h0000_0680);

        // Install a return entry, then push a resolved call.  The return uses RAS.
        train_entry(32'h0000_0700, 1'b1, 32'hDEAD_BEEF, `BP_TYPE_RETURN);
        train_entry(32'h0000_0640, 1'b1, 32'h0000_0800, `BP_TYPE_CALL);
        redirect_to(32'h0000_0700);
        expect_uop(32'h0000_0700, 1'b1, 32'h0000_0644);

        // Redirect while a request is in flight must discard the old epoch response.
        redirect_to(32'h0000_0800);
        wait (inst_ren);
        @(negedge clk);
        exception_flag = 1'b1;
        exception_addr = 32'h0000_0900;
        @(negedge clk);
        exception_flag = 1'b0;
        expect_uop(32'h0000_0900, 1'b0, 32'b0);

        // Backpressure holds the active uop stable while the next response uses
        // the one-packet prefetch slot.  Release preserves strict age order.
        redirect_to(32'h0000_0A00);
        @(negedge clk);
        ds_allowin = 1'b0;
        while (!fs_to_ds_valid) begin
            @(negedge clk);
        end
        held_bus = fs_to_ds_bus;
        repeat (4) begin
            @(negedge clk);
            if (!fs_to_ds_valid || (fs_to_ds_bus !== held_bus)) begin
                $fatal(1, "IF1 output changed while Decode was stalled");
            end
        end
        if (!dut.prefetch_valid) begin
            $fatal(1, "prefetch slot did not capture response during stall");
        end
        ds_allowin = 1'b1;
        expect_uop(32'h0000_0A00, 1'b0, 32'b0);
        expect_uop(32'h0000_0A04, 1'b0, 32'b0);
        expect_uop(32'h0000_0A08, 1'b0, 32'b0);

        $display("IF SYNC BTB TEST PASSED");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "tb_if_sync_btb timeout");
    end

endmodule
