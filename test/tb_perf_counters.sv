`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_perf_counters;
    logic clk;
    logic rst_n;
    logic csr_wen;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [11:0] csr_raddr;
    logic [31:0] csr_rdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic [1:0] retire_count;
    logic branch_event;
    logic branch_mispredict_event;
    logic load_use_stall_event;
    logic execute_stall_event;
    logic dual_issue_event;
    logic single_issue_event;
    logic issue_raw_reject_event;
    logic issue_waw_reject_event;
    logic issue_struct_reject_event;
    logic exception_flag;
    logic [31:0] exception_addr;
    logic external_irq_enable;

    regfile_csr dut (
        .clk(clk),
        .rst_n(rst_n),
        .csr_wen(csr_wen),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .csr_raddr(csr_raddr),
        .csr_rdata(csr_rdata),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .retire_count(retire_count),
        .branch_event(branch_event),
        .branch_mispredict_event(branch_mispredict_event),
        .load_use_stall_event(load_use_stall_event),
        .execute_stall_event(execute_stall_event),
        .dual_issue_event(dual_issue_event),
        .single_issue_event(single_issue_event),
        .issue_raw_reject_event(issue_raw_reject_event),
        .issue_waw_reject_event(issue_waw_reject_event),
        .issue_struct_reject_event(issue_struct_reject_event),
        .exception_flag(exception_flag),
        .exception_addr(exception_addr),
        .external_irq_enable(external_irq_enable)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic drive_cycle(
        input logic csr_write,
        input logic [11:0] write_addr,
        input logic [31:0] write_data,
        input logic [1:0] retired,
        input logic branch,
        input logic mispredict,
        input logic load_use,
        input logic ex_stall,
        input logic [6:0] exc
    );
        begin
            @(negedge clk);
            csr_wen = csr_write;
            csr_waddr = write_addr;
            csr_wdata = write_data;
            retire_count = retired;
            branch_event = branch;
            branch_mispredict_event = mispredict;
            load_use_stall_event = load_use;
            execute_stall_event = ex_stall;
            exception_code = exc;
            @(posedge clk);
            #1;
            csr_wen = 1'b0;
            csr_waddr = 12'b0;
            csr_wdata = 32'b0;
            retire_count = 2'b0;
            branch_event = 1'b0;
            branch_mispredict_event = 1'b0;
            load_use_stall_event = 1'b0;
            execute_stall_event = 1'b0;
            exception_code = `EXC_NONE;
        end
    endtask

    task automatic expect_csr(
        input logic [11:0] addr,
        input logic [31:0] expected,
        input string name
    );
        begin
            csr_raddr = addr;
            #1ps;
            if (csr_rdata !== expected) begin
                $fatal(1, "%s mismatch: expected %0d (0x%08h), got %0d (0x%08h)",
                       name, expected, expected, csr_rdata, csr_rdata);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        csr_wen = 1'b0;
        csr_waddr = 12'b0;
        csr_wdata = 32'b0;
        csr_raddr = 12'b0;
        exception_code = `EXC_NONE;
        exception_mtval = 32'b0;
        retire_count = 2'b0;
        branch_event = 1'b0;
        branch_mispredict_event = 1'b0;
        load_use_stall_event = 1'b0;
        execute_stall_event = 1'b0;
        dual_issue_event = 1'b0;
        single_issue_event = 1'b0;
        issue_raw_reject_event = 1'b0;
        issue_waw_reject_event = 1'b0;
        issue_struct_reject_event = 1'b0;

        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;

        //清零并关闭窗口，再显式打开，控制写周期不计数。
        drive_cycle(1'b1, `CSR_PERF_CTRL, 32'h0000_0002,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        drive_cycle(1'b1, `CSR_PERF_CTRL, 32'h0000_0001,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);

        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd1, 1'b1, 1'b0, 1'b1, 1'b0, `EXC_NONE);
        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd1, 1'b1, 1'b1, 1'b0, 1'b1, `EXC_IAM);
        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b1, `EXC_NONE);

        expect_csr(`CSR_PERF_CYCLE,     32'd3, "perf_cycle");
        expect_csr(`CSR_PERF_INSTRET,   32'd2, "perf_instret");
        expect_csr(`CSR_PERF_BRANCH,    32'd2, "perf_branch");
        expect_csr(`CSR_PERF_BRMISP,    32'd1, "perf_brmisp");
        expect_csr(`CSR_PERF_BPHIT,     32'd1, "perf_bphit");
        expect_csr(`CSR_PERF_BPMISS,    32'd1, "perf_bpmiss");
        expect_csr(`CSR_PERF_LOADUSE,   32'd1, "perf_loaduse");
        expect_csr(`CSR_PERF_EXSTALL,   32'd2, "perf_exstall");
        expect_csr(`CSR_PERF_EXCEPTION, 32'd1, "perf_exception");
        expect_csr(`CSR_INSTRET,        32'd2, "instret");

        //关闭性能窗口后，标准instret继续按退休数运行。
        drive_cycle(1'b1, `CSR_PERF_CTRL, 32'h0000_0000,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd2, 1'b1, 1'b1, 1'b1, 1'b1, `EXC_IAM);

        expect_csr(`CSR_PERF_CYCLE,     32'd3, "frozen_perf_cycle");
        expect_csr(`CSR_PERF_INSTRET,   32'd2, "frozen_perf_instret");
        expect_csr(`CSR_INSTRET,        32'd4, "dual_ready_instret");

        drive_cycle(1'b1, `CSR_PERF_CTRL, 32'h0000_0002,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        expect_csr(`CSR_PERF_CYCLE,     32'd0, "cleared_perf_cycle");
        expect_csr(`CSR_PERF_INSTRET,   32'd0, "cleared_perf_instret");
        expect_csr(`CSR_PERF_BRANCH,    32'd0, "cleared_perf_branch");
        expect_csr(`CSR_PERF_EXCEPTION, 32'd0, "cleared_perf_exception");

        drive_cycle(1'b1, `CSR_PERF_CTRL, 32'h0000_0001,
                    2'd0, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        dual_issue_event = 1'b1;
        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd2, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        dual_issue_event = 1'b0;
        single_issue_event = 1'b1;
        issue_raw_reject_event = 1'b1;
        issue_waw_reject_event = 1'b1;
        issue_struct_reject_event = 1'b1;
        drive_cycle(1'b0, 12'b0, 32'b0,
                    2'd1, 1'b0, 1'b0, 1'b0, 1'b0, `EXC_NONE);
        single_issue_event = 1'b0;
        issue_raw_reject_event = 1'b0;
        issue_waw_reject_event = 1'b0;
        issue_struct_reject_event = 1'b0;

        expect_csr(`CSR_PERF_DUAL_ISSUE,   32'd1, "perf_dual_issue");
        expect_csr(`CSR_PERF_SINGLE_ISSUE, 32'd1, "perf_single_issue");
        expect_csr(`CSR_PERF_ISSUE_RAW,    32'd1, "perf_issue_raw");
        expect_csr(`CSR_PERF_ISSUE_WAW,    32'd1, "perf_issue_waw");
        expect_csr(`CSR_PERF_ISSUE_STRUCT, 32'd1, "perf_issue_struct");

        $display("PERF COUNTER TEST PASSED");
        $finish;
    end

endmodule
