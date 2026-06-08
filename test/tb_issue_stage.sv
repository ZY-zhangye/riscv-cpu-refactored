`timescale 1ns/1ps
`include "defines.svh"

module tb_issue_stage;
    localparam int CLK_PERIOD_NS = 10;

    logic clk;
    logic rst_n;
    logic fs_to_is_valid;
    logic is_allowin;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus;
    logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1;
    logic is_to_ds_valid;
    logic ds_allowin;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus;
    logic is_to_ds_valid1;
    logic ds_allowin1;
    logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1;
    logic br_taken;
    logic exception_flag;
    logic is_flush;
    logic is_flush1;

    int failures;

    localparam logic [31:0] INST_ADDI_X1_X0_1 = 32'h0010_0093;
    localparam logic [31:0] INST_ADDI_X2_X0_2 = 32'h0020_0113;
    localparam logic [31:0] INST_ADDI_X3_X0_3 = 32'h0030_0193;
    localparam logic [31:0] INST_ADDI_X2_X1_2 = 32'h0020_8113;
    localparam logic [31:0] INST_ADDI_X1_X0_2 = 32'h0020_0093;
    localparam logic [31:0] INST_LW_X3_0_X0   = 32'h0000_2183;
    localparam logic [31:0] INST_LW_X3_0_X1   = 32'h0000_a183;
    localparam logic [31:0] INST_SW_X1_0_X0   = 32'h0010_2023;
    localparam logic [31:0] INST_SW_X1_0_X2   = 32'h0011_2023;
    localparam logic [31:0] INST_BEQ_X0_X0_8  = 32'h0000_0463;
    localparam logic [31:0] INST_BEXTI_X2_X0_3 = 32'h4830_5113;

    issue_stage u_issue_stage (
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_is_valid(fs_to_is_valid),
        .is_allowin(is_allowin),
        .fs_to_is_bus(fs_to_is_bus),
        .fs_to_is_bus1(fs_to_is_bus1),
        .is_to_ds_valid(is_to_ds_valid),
        .ds_allowin(ds_allowin),
        .is_to_ds_bus(is_to_ds_bus),
        .is_to_ds_valid1(is_to_ds_valid1),
        .ds_allowin1(ds_allowin1),
        .is_to_ds_bus1(is_to_ds_bus1),
        .br_taken(br_taken),
        .exception_flag(exception_flag),
        .is_flush(is_flush),
        .is_flush1(is_flush1)
    );

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    function automatic logic [`FS_DS_WIDTH-1:0] pack_fetch_bus(
        input logic [31:0] inst,
        input logic [31:0] pc
    );
        begin
            pack_fetch_bus = {inst, pc, 1'b0, 32'b0};
        end
    endfunction

    function automatic logic [31:0] bus_inst(input logic [`FS_DS_WIDTH-1:0] bus);
        begin
            bus_inst = bus[`FS_DS_WIDTH-1 -: 32];
        end
    endfunction

    task automatic check(input string name, input bit cond);
        begin
            if (!cond) begin
                failures++;
                $display("ISSUE_CHECK_FAIL %s at t=%0t", name, $time);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            fs_to_is_valid = 1'b0;
            fs_to_is_bus = '0;
            fs_to_is_bus1 = '0;
            ds_allowin = 1'b1;
            ds_allowin1 = 1'b1;
            br_taken = 1'b0;
            exception_flag = 1'b0;
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic send_packet(
        input logic [31:0] inst0,
        input logic [31:0] inst1
    );
        begin
            @(negedge clk);
            check("issue ready before fetch packet", is_allowin);
            fs_to_is_valid = 1'b1;
            fs_to_is_bus = pack_fetch_bus(inst0, 32'h8000_0000);
            fs_to_is_bus1 = pack_fetch_bus(inst1, 32'h8000_0004);
            @(posedge clk);
            #1;
            fs_to_is_valid = 1'b0;
            fs_to_is_bus = '0;
            fs_to_is_bus1 = '0;
            #1;
        end
    endtask

    task automatic test_dual_simple;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X2_X0_2);
            check("simple pair lane0 valid", is_to_ds_valid);
            check("simple pair lane1 valid", is_to_ds_valid1);
            check("simple pair lane0 inst", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            check("simple pair lane1 inst", bus_inst(is_to_ds_bus1) == INST_ADDI_X2_X0_2);
            @(posedge clk);
            #1;
            check("simple pair buffer empty", !u_issue_stage.buf_valid0 && !u_issue_stage.buf_valid1);
        end
    endtask

    task automatic test_raw_serial;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X2_X1_2);
            check("raw lane0 valid", is_to_ds_valid);
            check("raw lane1 blocked", !is_to_ds_valid1);
            check("raw older inst first", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            @(posedge clk);
            #1;
            check("raw younger inst next lane0", is_to_ds_valid &&
                                              (bus_inst(is_to_ds_bus) == INST_ADDI_X2_X1_2));
            check("raw lane1 still blocked", !is_to_ds_valid1);
        end
    endtask

    task automatic test_waw_serial;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X1_X0_2);
            check("waw lane0 valid", is_to_ds_valid);
            check("waw lane1 blocked", !is_to_ds_valid1);
            check("waw older inst first", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            @(posedge clk);
            #1;
            check("waw younger inst next lane0", is_to_ds_valid &&
                                              (bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_2));
        end
    endtask

    task automatic test_serial_classes;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_LW_X3_0_X0);
            check("lane1 load pair lane0 valid", is_to_ds_valid);
            check("lane1 load pair lane1 valid", is_to_ds_valid1);
            check("lane1 load pair older alu", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            check("lane1 load pair younger load", bus_inst(is_to_ds_bus1) == INST_LW_X3_0_X0);

            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_LW_X3_0_X1);
            check("lane1 load raw base blocks lane1", is_to_ds_valid && !is_to_ds_valid1);
            check("lane1 load raw older first", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            @(posedge clk);
            #1;
            check("lane1 load raw younger next lane0", is_to_ds_valid &&
                                                    (bus_inst(is_to_ds_bus) == INST_LW_X3_0_X1));

            reset_dut();
            send_packet(INST_ADDI_X2_X0_2, INST_SW_X1_0_X0);
            check("lane1 store pair lane0 valid", is_to_ds_valid);
            check("lane1 store pair lane1 valid", is_to_ds_valid1);
            check("lane1 store pair older alu", bus_inst(is_to_ds_bus) == INST_ADDI_X2_X0_2);
            check("lane1 store pair younger store", bus_inst(is_to_ds_bus1) == INST_SW_X1_0_X0);

            reset_dut();
            send_packet(INST_ADDI_X2_X0_2, INST_SW_X1_0_X2);
            check("lane1 store raw base blocks lane1", is_to_ds_valid && !is_to_ds_valid1);
            check("lane1 store raw older first", bus_inst(is_to_ds_bus) == INST_ADDI_X2_X0_2);
            @(posedge clk);
            #1;
            check("lane1 store raw younger next lane0", is_to_ds_valid &&
                                                     (bus_inst(is_to_ds_bus) == INST_SW_X1_0_X2));

            reset_dut();
            send_packet(INST_LW_X3_0_X0, INST_ADDI_X2_X0_2);
            check("load lane0 valid", is_to_ds_valid);
            check("load blocks lane1", !is_to_ds_valid1);
            check("load older inst first", bus_inst(is_to_ds_bus) == INST_LW_X3_0_X0);
            @(posedge clk);
            #1;
            check("after load younger inst next lane0", is_to_ds_valid &&
                                                    (bus_inst(is_to_ds_bus) == INST_ADDI_X2_X0_2));

            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_BEQ_X0_X0_8);
            check("lane1 branch pair lane0 valid", is_to_ds_valid);
            check("lane1 branch pair lane1 valid", is_to_ds_valid1);
            check("lane1 branch pair older alu", bus_inst(is_to_ds_bus) == INST_ADDI_X1_X0_1);
            check("lane1 branch pair younger branch", bus_inst(is_to_ds_bus1) == INST_BEQ_X0_X0_8);
            check("lane1 branch pair not flushed early", !is_flush1);

            reset_dut();
            send_packet(INST_BEQ_X0_X0_8, INST_ADDI_X2_X0_2);
            check("lane0 branch blocks lane1", is_to_ds_valid && !is_to_ds_valid1);
            check("lane0 branch older first", bus_inst(is_to_ds_bus) == INST_BEQ_X0_X0_8);
            check("lane0 branch does not locally flush lane1", !is_flush1);
            @(posedge clk);
            #1;
            check("lane0 branch younger next lane0", is_to_ds_valid &&
                                                  (bus_inst(is_to_ds_bus) == INST_ADDI_X2_X0_2));

            reset_dut();
            send_packet(INST_BEQ_X0_X0_8, INST_BEQ_X0_X0_8);
            check("lane0 branch blocks branch lane1", is_to_ds_valid && !is_to_ds_valid1);
            @(posedge clk);
            #1;
            check("lane0 branch lane1 branch next lane0", is_to_ds_valid &&
                                                        (bus_inst(is_to_ds_bus) == INST_BEQ_X0_X0_8));

            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_BEXTI_X2_X0_3);
            check("zbs candidate blocks lane1", is_to_ds_valid && !is_to_ds_valid1);
            @(posedge clk);
            #1;
            check("zbs eventually lane0", is_to_ds_valid &&
                                       (bus_inst(is_to_ds_bus) == INST_BEXTI_X2_X0_3));
        end
    endtask

    task automatic test_lane0_flush_redirect;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X2_X1_2);
            check("raw setup enters lane0-only", is_to_ds_valid && !is_to_ds_valid1);
            @(negedge clk);
            br_taken = 1'b1;
            @(posedge clk);
            #1;
            check("branch flush lane0 asserted", is_flush);
            check("branch flush lane1 asserted", is_flush1);
            check("branch flush carries lane0 valid", is_to_ds_valid);
            check("branch flush suppresses lane1 valid", !is_to_ds_valid1);
            check("branch flush clears both issue slots",
                  !u_issue_stage.buf_valid0 && !u_issue_stage.buf_valid1);
            @(negedge clk);
            br_taken = 1'b0;

            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X2_X1_2);
            @(negedge clk);
            exception_flag = 1'b1;
            @(posedge clk);
            #1;
            check("exception flush lane0 asserted", is_flush);
            check("exception flush lane1 asserted", is_flush1);
            check("exception flush carries lane0 valid", is_to_ds_valid);
            check("exception flush clears both issue slots",
                  !u_issue_stage.buf_valid0 && !u_issue_stage.buf_valid1);
            @(negedge clk);
            exception_flag = 1'b0;
        end
    endtask

    task automatic test_idle_flush_both_lanes;
        begin
            reset_dut();
            send_packet(INST_ADDI_X1_X0_1, INST_ADDI_X2_X0_2);
            @(negedge clk);
            br_taken = 1'b1;
            @(posedge clk);
            #1;
            check("idle flush lane0 asserted", is_flush);
            check("idle flush lane1 asserted", is_flush1);
            check("idle flush carries lane0 valid", is_to_ds_valid);
            check("idle flush carries lane1 valid", is_to_ds_valid1);
            check("idle flush clears both issue slots",
                  !u_issue_stage.buf_valid0 && !u_issue_stage.buf_valid1);
            @(negedge clk);
            br_taken = 1'b0;
        end
    endtask

    initial begin
        failures = 0;
        test_dual_simple();
        test_raw_serial();
        test_waw_serial();
        test_serial_classes();
        test_lane0_flush_redirect();
        test_idle_flush_both_lanes();

        if (failures == 0) begin
            $display("ISSUE_STAGE_TEST_PASS");
        end else begin
            $display("ISSUE_STAGE_TEST_FAIL failures=%0d", failures);
        end
        $finish;
    end

endmodule
