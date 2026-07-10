`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_multi_issue_l3;
    logic clk;
    logic rst_n;
    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic imem_en;
    logic [31:0] imem_rdata1;
    logic [31:0] imem_addr1;
    logic imem_en1;
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr;
    logic [3:0] dmem_wen;
    logic dmem_en;
    logic [31:0] dmem_wdata;
    logic [31:0] debug_wb_pc;
    logic debug_commit_valid;
    logic [31:0] debug_wb_pc1;
    logic debug_commit_valid1;
    logic debug_store_valid;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];
    int failures;
    int cycles;

    cpu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .imem_rdata1(imem_rdata1),
        .imem_addr1(imem_addr1),
        .imem_en1(imem_en1),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .plic_irq(1'b0),
        .debug_wb_pc(debug_wb_pc),
        .debug_commit_valid(debug_commit_valid),
        .debug_wb_pc1(debug_wb_pc1),
        .debug_commit_valid1(debug_commit_valid1),
        .debug_store_valid(debug_store_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures++;
            $display("L3_CHECK_FAIL %s time=%0t", name, $time);
        end
    endtask

    initial begin
        integer i;
        for (i = 0; i < 64; i++) begin
            imem[i] = `NOP_INST;
            dmem[i] = 32'b0;
        end

        // 连续包内RAW使4项队列产生跨fetch packet配对。
        imem[0]  = 32'h0010_0093; // addi x1,x0,1
        imem[1]  = 32'h0020_8113; // addi x2,x1,2
        imem[2]  = 32'h0030_0193; // addi x3,x0,3
        imem[3]  = 32'h0041_8213; // addi x4,x3,4
        imem[4]  = 32'h0050_0293; // addi x5,x0,5
        imem[5]  = 32'h0062_8313; // addi x6,x5,6
        imem[6]  = 32'h0030_0393; // addi x7,x0,3
        imem[7]  = 32'h0040_0413; // addi x8,x0,4
        imem[8]  = 32'h2083_a4b3; // sh1add x9,x7,x8 = 10
        imem[9]  = 32'h4074_7533; // andn x10,x8,x7 = 4
        imem[10] = 32'h0090_2023; // sw x9,0(x0)
        imem[11] = 32'h2083_a5b3; // sh1add x11,x7,x8 = 10

        // lane1分支循环：首次taken和最终not-taken各误预测一次，中间应命中。
        imem[12] = 32'h0000_0613; // addi x12,x0,0
        imem[13] = 32'h0050_0693; // addi x13,x0,5
        imem[14] = 32'h0016_0613; // addi x12,x12,1
        imem[15] = 32'h0000_0713; // addi x14,x0,0
        imem[16] = 32'h0000_0793; // addi x15,x0,0
        imem[17] = 32'hfed6_4ae3; // blt x12,x13,-12 -> 0x38
        imem[18] = 32'h0000_006f; // jal x0,0
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rdata <= 32'b0;
            imem_rdata1 <= 32'b0;
        end else begin
            if (imem_en) imem_rdata <= imem[imem_addr[7:2]];
            if (imem_en1) imem_rdata1 <= imem[imem_addr1[7:2]];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dmem_rdata <= 32'b0;
        end else if (dmem_en) begin
            if (dmem_wen[0]) dmem[dmem_addr[7:2]][7:0] <= dmem_wdata[7:0];
            if (dmem_wen[1]) dmem[dmem_addr[7:2]][15:8] <= dmem_wdata[15:8];
            if (dmem_wen[2]) dmem[dmem_addr[7:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wen[3]) dmem[dmem_addr[7:2]][31:24] <= dmem_wdata[31:24];
            dmem_rdata <= dmem[dmem_addr[7:2]];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) cycles <= 0;
        else cycles <= cycles + 1;
    end

    initial begin
        failures = 0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        wait (debug_commit_valid1 && (debug_wb_pc1 == 32'h8000_0044) &&
              (dut.u_regfiles.regfile[12] == 32'd5));
        #1;

        check("cross packet x2", dut.u_regfiles.regfile[2] == 32'd3);
        check("cross packet x4", dut.u_regfiles.regfile[4] == 32'd7);
        check("cross packet x6", dut.u_regfiles.regfile[6] == 32'd11);
        check("sh1add lane result", dut.u_regfiles.regfile[9] == 32'd10);
        check("andn lane result", dut.u_regfiles.regfile[10] == 32'd4);
        check("LSU plus bitman result", dut.u_regfiles.regfile[11] == 32'd10);
        check("bitman store", dmem[0] == 32'd10);
        check("loop count", dut.u_regfiles.regfile[12] == 32'd5);

        `ifdef L3_PERF_COUNTERS
        check("five lane1 branches", dut.u_regfile_csr.perf_branch == 32'd5);
        check("lane1 predictor misses", dut.u_regfile_csr.perf_brmisp == 32'd2);
        check("cross packet events", dut.u_regfile_csr.perf_cross_packet >= 32'd2);
        check("bitman pair events", dut.u_regfile_csr.perf_bitman_pair >= 32'd2);
        $display("L3_MEASURE cycles=%0d instret=%0d ipc_x1000=%0d cross_pairs=%0d bitman_pairs=%0d branch_miss=%0d",
                 cycles, dut.u_regfile_csr.instret,
                 (dut.u_regfile_csr.instret * 1000) / cycles,
                 dut.u_regfile_csr.perf_cross_packet,
                 dut.u_regfile_csr.perf_bitman_pair,
                 dut.u_regfile_csr.perf_brmisp);
        `else
        // L2在最终not-taken分支提交前已让顺序JAL进入EX，因此计数包含该JAL。
        check("baseline branch events", dut.u_regfile_csr.perf_branch == 32'd6);
        check("baseline lane1 predictor misses", dut.u_regfile_csr.perf_brmisp == 32'd5);
        $display("L3_BASELINE_MEASURE cycles=%0d instret=%0d ipc_x1000=%0d branch_miss=%0d",
                 cycles, dut.u_regfile_csr.instret,
                 (dut.u_regfile_csr.instret * 1000) / cycles,
                 dut.u_regfile_csr.perf_brmisp);
        `endif

        if (failures == 0) begin
            $display("MULTI_ISSUE_L3_TEST_PASSED");
        end else begin
            $fatal(1, "MULTI_ISSUE_L3_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "MULTI_ISSUE_L3_TEST_TIMEOUT");
    end

endmodule
