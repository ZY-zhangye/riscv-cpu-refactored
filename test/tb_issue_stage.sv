`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_issue_stage;
    logic clk;
    logic rst_n;
    logic fs_to_is_valid0;
    logic fs_to_is_valid1;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus0;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1;
    logic is_allowin;
    logic is_to_ds_valid0;
    logic is_to_ds_valid1;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus0;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1;
    logic ds_bundle_allowin;
    logic br_redirect;
    logic exception_flag;
    logic issue_flush;
    logic dual_issue_event;
    logic single_issue_event;
    logic issue_raw_reject_event;
    logic issue_waw_reject_event;
    logic issue_struct_reject_event;
    logic issue_lsu_pair_event;
    logic issue_lane1_control_event;
    logic [31:0] debug_issue_inst0;
    logic [31:0] debug_issue_pc0;
    logic debug_issue_valid0;
    logic [31:0] debug_issue_inst1;
    logic [31:0] debug_issue_pc1;
    logic debug_issue_valid1;
    int failures;

    localparam logic [31:0] ADDI_X1_X0_1 = 32'h0010_0093;
    localparam logic [31:0] ADDI_X2_X0_2 = 32'h0020_0113;
    localparam logic [31:0] ADDI_X2_X1_2 = 32'h0020_8113;
    localparam logic [31:0] ADDI_X1_X0_2 = 32'h0020_0093;
    localparam logic [31:0] LW_X3_0_X0 = 32'h0000_2183;
    localparam logic [31:0] LW_X1_0_X0 = 32'h0000_2083;
    localparam logic [31:0] SW_X3_0_X0 = 32'h0030_2023;
    localparam logic [31:0] BEQ_X1_X2_8 = 32'h0020_8463;
    localparam logic [31:0] CSRRW_X3_MSTATUS_X1 = 32'h3000_91f3;

    issue_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_is_valid0(fs_to_is_valid0),
        .fs_to_is_valid1(fs_to_is_valid1),
        .fs_to_is_bus0(fs_to_is_bus0),
        .fs_to_is_bus1(fs_to_is_bus1),
        .is_allowin(is_allowin),
        .is_to_ds_valid0(is_to_ds_valid0),
        .is_to_ds_valid1(is_to_ds_valid1),
        .is_to_ds_bus0(is_to_ds_bus0),
        .is_to_ds_bus1(is_to_ds_bus1),
        .ds_bundle_allowin(ds_bundle_allowin),
        .br_redirect(br_redirect),
        .exception_flag(exception_flag),
        .issue_flush(issue_flush),
        .dual_issue_event(dual_issue_event),
        .single_issue_event(single_issue_event),
        .issue_raw_reject_event(issue_raw_reject_event),
        .issue_waw_reject_event(issue_waw_reject_event),
        .issue_struct_reject_event(issue_struct_reject_event),
        .issue_lsu_pair_event(issue_lsu_pair_event),
        .issue_lane1_control_event(issue_lane1_control_event),
        .debug_issue_inst0(debug_issue_inst0),
        .debug_issue_pc0(debug_issue_pc0),
        .debug_issue_valid0(debug_issue_valid0),
        .debug_issue_inst1(debug_issue_inst1),
        .debug_issue_pc1(debug_issue_pc1),
        .debug_issue_valid1(debug_issue_valid1)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [`FS_DS_WIDTH-1:0] packet(
        input logic [31:0] inst,
        input logic [31:0] pc
    );
        packet = {inst, pc, 1'b0, 32'b0};
    endfunction

    function automatic logic [31:0] bus_inst(
        input logic [`FS_DS_WIDTH-1:0] bus
    );
        bus_inst = bus[`FS_DS_WIDTH-1 -: 32];
    endfunction

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures++;
            $display("ISSUE_CHECK_FAIL %s time=%0t", name, $time);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            fs_to_is_valid0 = 1'b0;
            fs_to_is_valid1 = 1'b0;
            fs_to_is_bus0 = '0;
            fs_to_is_bus1 = '0;
            ds_bundle_allowin = 1'b1;
            br_redirect = 1'b0;
            exception_flag = 1'b0;
            repeat (2) @(posedge clk);
            #1 rst_n = 1'b1;
        end
    endtask

    task automatic send_pair(
        input logic [31:0] inst0,
        input logic [31:0] inst1
    );
        begin
            @(negedge clk);
            check("input ready", is_allowin);
            fs_to_is_valid0 = 1'b1;
            fs_to_is_valid1 = 1'b1;
            fs_to_is_bus0 = packet(inst0, 32'h8000_0000);
            fs_to_is_bus1 = packet(inst1, 32'h8000_0004);
            @(posedge clk);
            #1;
            fs_to_is_valid0 = 1'b0;
            fs_to_is_valid1 = 1'b0;
        end
    endtask

    initial begin
        failures = 0;

        reset_dut();
        send_pair(ADDI_X1_X0_1, ADDI_X2_X0_2);
        check("independent pair lane0", is_to_ds_valid0);
        check("independent pair lane1", is_to_ds_valid1);
        check("independent pair event", dual_issue_event);
        check("lane0 instruction", bus_inst(is_to_ds_bus0) == ADDI_X1_X0_1);
        check("lane1 instruction", bus_inst(is_to_ds_bus1) == ADDI_X2_X0_2);
        @(posedge clk);
        #1;

        reset_dut();
        send_pair(ADDI_X1_X0_1, ADDI_X2_X1_2);
        check("RAW lane0 issues", is_to_ds_valid0);
        check("RAW lane1 blocked", !is_to_ds_valid1);
        check("RAW reject event", issue_raw_reject_event);
        @(posedge clk);
        #1;
        check("RAW younger preserved", is_to_ds_valid0 &&
              (bus_inst(is_to_ds_bus0) == ADDI_X2_X1_2));

        reset_dut();
        send_pair(ADDI_X1_X0_1, ADDI_X1_X0_2);
        check("WAW lane1 blocked", !is_to_ds_valid1);
        check("WAW reject event", issue_waw_reject_event);

        reset_dut();
        send_pair(ADDI_X1_X0_1, LW_X3_0_X0);
        check("ALU plus load lane0", is_to_ds_valid0);
        check("ALU plus load lane1", is_to_ds_valid1);
        check("ALU plus load dual event", dual_issue_event);

        reset_dut();
        send_pair(LW_X3_0_X0, ADDI_X1_X0_1);
        check("load plus ALU lane0", is_to_ds_valid0);
        check("load plus ALU lane1", is_to_ds_valid1);

        reset_dut();
        send_pair(SW_X3_0_X0, ADDI_X1_X0_1);
        check("store plus ALU lane1", is_to_ds_valid1);

        reset_dut();
        send_pair(ADDI_X1_X0_1, SW_X3_0_X0);
        check("ALU plus store lane1", is_to_ds_valid1);

        reset_dut();
        send_pair(ADDI_X1_X0_1, BEQ_X1_X2_8);
        check("ALU to branch RAW blocked", !is_to_ds_valid1);
        check("ALU to branch RAW event", issue_raw_reject_event);

        reset_dut();
        send_pair(ADDI_X1_X0_1, 32'h0021_8463);
        check("ALU plus independent branch lane1", is_to_ds_valid1);

        reset_dut();
        send_pair(LW_X1_0_X0, ADDI_X2_X1_2);
        check("load to ALU RAW blocked", !is_to_ds_valid1);
        check("load to ALU RAW event", issue_raw_reject_event);

        reset_dut();
        send_pair(ADDI_X1_X0_1, CSRRW_X3_MSTATUS_X1);
        check("CSR lane1 blocked", !is_to_ds_valid1);
        check("CSR struct reject event", issue_struct_reject_event);
        @(posedge clk);
        #1;
        check("CSR younger preserved", is_to_ds_valid0 &&
              (bus_inst(is_to_ds_bus0) == CSRRW_X3_MSTATUS_X1));

        reset_dut();
        ds_bundle_allowin = 1'b0;
        send_pair(ADDI_X1_X0_1, ADDI_X2_X0_2);
        check("backpressure holds lane0", is_to_ds_valid0);
        check("backpressure holds lane1", is_to_ds_valid1);
        check("backpressure no dual event", !dual_issue_event);
        repeat (2) @(posedge clk);
        #1;
        check("backpressure data stable", bus_inst(is_to_ds_bus0) == ADDI_X1_X0_1);
        ds_bundle_allowin = 1'b1;
        @(posedge clk);
        #1;

        reset_dut();
        send_pair(ADDI_X1_X0_1, ADDI_X2_X1_2);
        @(negedge clk);
        br_redirect = 1'b1;
        #1;
        check("flush asserted", issue_flush);
        @(posedge clk);
        #1;
        br_redirect = 1'b0;
        check("flush clears lane0", !is_to_ds_valid0);
        check("flush clears lane1", !is_to_ds_valid1);

        if (failures == 0) begin
            $display("ISSUE_STAGE_TEST_PASSED");
        end else begin
            $fatal(1, "ISSUE_STAGE_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end

endmodule
