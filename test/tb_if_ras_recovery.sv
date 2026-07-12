`timescale 1ns/1ps
`include "defines.svh"

module tb_if_ras_recovery;
    logic clk;
    logic rst_n;
    logic [`ADDR_WIDTH-1:0] pc_out;
    logic inst_ren;
    logic [`DATA_WIDTH-1:0] inst_in;
    logic [`ADDR_WIDTH-1:0] pc_out1;
    logic inst_ren1;
    logic [`DATA_WIDTH-1:0] inst_in1;
    logic ds_allowin;
    logic fs_to_ds_valid;
    logic fs_to_ds_valid1;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus;
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus1;
    logic br_taken;
    logic [`ADDR_WIDTH-1:0] br_target;
    logic bp_update_valid;
    logic [`ADDR_WIDTH-1:0] bp_update_pc;
    logic bp_update_taken;
    logic [`ADDR_WIDTH-1:0] bp_update_target;
    logic bp_update_is_jalr;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic [`EXC_WIDTH-1:0] fs_exc_bus;
    logic exception_flag;
    logic [`ADDR_WIDTH-1:0] exception_addr;
    integer failures;

    if_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc_out(pc_out),
        .inst_ren(inst_ren),
        .inst_in(inst_in),
        .pc_out1(pc_out1),
        .inst_ren1(inst_ren1),
        .inst_in1(inst_in1),
        .ds_allowin(ds_allowin),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_valid1(fs_to_ds_valid1),
        .fs_to_ds_bus(fs_to_ds_bus),
        .fs_to_ds_bus1(fs_to_ds_bus1),
        .br_taken(br_taken),
        .br_target(br_target),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .bp_update_is_jalr(bp_update_is_jalr),
        .bp_update_is_call(bp_update_is_call),
        .bp_update_is_return(bp_update_is_return),
        .fs_exc_bus(fs_exc_bus),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr)
    );

    always #5 clk = ~clk;

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures = failures + 1;
            $display("FAIL: %s", name);
        end
    endtask

    task automatic redirect_update(input logic is_call, input logic is_return);
        @(negedge clk);
        bp_update_valid = 1'b1;
        bp_update_taken = 1'b1;
        bp_update_is_jalr = is_return;
        bp_update_is_call = is_call;
        bp_update_is_return = is_return;
        br_taken = 1'b1;
        @(posedge clk);
        #1;
        bp_update_valid = 1'b0;
        bp_update_is_call = 1'b0;
        bp_update_is_return = 1'b0;
        br_taken = 1'b0;
        @(posedge clk);
        #1;
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        inst_in = `NOP_INST;
        inst_in1 = `NOP_INST;
        ds_allowin = 1'b1;
        br_taken = 1'b0;
        br_target = 32'h8000_0100;
        bp_update_valid = 1'b0;
        bp_update_pc = 32'h8000_0020;
        bp_update_taken = 1'b0;
        bp_update_target = 32'h8000_0100;
        bp_update_is_jalr = 1'b0;
        bp_update_is_call = 1'b0;
        bp_update_is_return = 1'b0;
        exception_flag = 1'b0;
        exception_addr = '0;
        failures = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        redirect_update(1'b1, 1'b0);
        check("call committed once", dut.ras_commit_count == 1);
        check("call recovered once", dut.ras_spec_count == 1);

        bp_update_pc = 32'h8000_0040;
        redirect_update(1'b0, 1'b1);
        check("return committed once", dut.ras_commit_count == 0);
        check("return recovered once", dut.ras_spec_count == 0);

        if (failures == 0) begin
            $display("IF_RAS_RECOVERY_TEST_PASSED");
        end else begin
            $fatal(1, "IF_RAS_RECOVERY_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end
endmodule
