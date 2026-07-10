`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_multi_issue_l2;
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
    logic [31:0] debug_store_pc;
    logic [31:0] debug_store_addr;
    logic [3:0] debug_store_wen;
    logic [31:0] debug_store_wdata;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];
    int failures;
    int store_count;
    logic saw_lane1_branch;
    logic saw_lane1_load;
    logic saw_wrong_path_commit;

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
        .debug_store_valid(debug_store_valid),
        .debug_store_pc(debug_store_pc),
        .debug_store_addr(debug_store_addr),
        .debug_store_wen(debug_store_wen),
        .debug_store_wdata(debug_store_wdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures++;
            $display("L2_CHECK_FAIL %s time=%0t", name, $time);
        end
    endtask

    task automatic clear_program;
        integer i;
        begin
            for (i = 0; i < 64; i++) begin
                imem[i] = `NOP_INST;
            end
        end
    endtask

    initial begin
        integer i;
        for (i = 0; i < 64; i++) begin
            imem[i] = `NOP_INST;
            dmem[i] = 32'b0;
        end

        // EX0/EX1前递、store+ALU、ALU+lane1 load、MEM1 load前递、
        // store/load单端口冲突，以及lane1 taken branch冲刷。
        imem[0]  = 32'h0050_0093; // addi x1,x0,5
        imem[1]  = 32'h0070_0113; // addi x2,x0,7
        imem[2]  = 32'h0020_81b3; // add  x3,x1,x2
        imem[3]  = 32'h0090_0213; // addi x4,x0,9
        imem[4]  = 32'h0030_2023; // sw   x3,0(x0)
        imem[5]  = 32'h0010_0293; // addi x5,x0,1
        imem[6]  = 32'h0020_0313; // addi x6,x0,2
        imem[7]  = 32'h0000_2383; // lw   x7,0(x0)
        imem[8]  = 32'h0053_8433; // add  x8,x7,x5
        imem[9]  = 32'h0030_0493; // addi x9,x0,3
        imem[10] = 32'h0010_0513; // addi x10,x0,1
        imem[11] = 32'h0052_8463; // beq  x5,x5,+8 -> 0x34
        imem[12] = 32'h0630_0593; // wrong path: addi x11,x0,99
        imem[13] = 32'h00b0_0593; // addi x11,x0,11
        imem[14] = 32'h00b0_2223; // sw   x11,4(x0)
        imem[15] = 32'h00c0_0613; // addi x12,x0,12
        imem[16] = 32'h0000_006f; // jal  x0,0
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rdata <= 32'b0;
            imem_rdata1 <= 32'b0;
        end else begin
            if (imem_en) begin
                imem_rdata <= imem[imem_addr[7:2]];
            end
            if (imem_en1) begin
                imem_rdata1 <= imem[imem_addr1[7:2]];
            end
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
        if (!rst_n) begin
            store_count <= 0;
            saw_lane1_branch <= 1'b0;
            saw_lane1_load <= 1'b0;
            saw_wrong_path_commit <= 1'b0;
        end else begin
            if (debug_store_valid) begin
                store_count <= store_count + 1;
                if (store_count == 0) begin
                    check("first store PC", debug_store_pc == 32'h8000_0010);
                    check("first store payload", debug_store_addr == 32'b0 &&
                          debug_store_wen == 4'b1111 && debug_store_wdata == 32'd12);
                end
            end
            if (debug_commit_valid1 && (debug_wb_pc1 == 32'h8000_002c)) begin
                saw_lane1_branch <= 1'b1;
            end
            if (debug_commit_valid1 && (debug_wb_pc1 == 32'h8000_001c)) begin
                saw_lane1_load <= 1'b1;
            end
            if ((debug_commit_valid && (debug_wb_pc == 32'h8000_0030)) ||
                (debug_commit_valid1 && (debug_wb_pc1 == 32'h8000_0030))) begin
                saw_wrong_path_commit <= 1'b1;
            end
        end
    end

    initial begin
        failures = 0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        repeat (120) @(posedge clk);
        #1;

        check("x1", dut.u_regfiles.regfile[1] == 32'd5);
        check("x2", dut.u_regfiles.regfile[2] == 32'd7);
        check("dual EX forwarding x3", dut.u_regfiles.regfile[3] == 32'd12);
        check("x4", dut.u_regfiles.regfile[4] == 32'd9);
        check("x5", dut.u_regfiles.regfile[5] == 32'd1);
        check("x6", dut.u_regfiles.regfile[6] == 32'd2);
        check("lane1 load x7", dut.u_regfiles.regfile[7] == 32'd12);
        check("MEM1 forwarding x8", dut.u_regfiles.regfile[8] == 32'd13);
        check("x9", dut.u_regfiles.regfile[9] == 32'd3);
        check("lane0 before branch x10", dut.u_regfiles.regfile[10] == 32'd1);
        check("wrong path flushed x11", dut.u_regfiles.regfile[11] == 32'd11);
        check("x12", dut.u_regfiles.regfile[12] == 32'd12);
        check("first committed store", dmem[0] == 32'd12);
        check("second committed store", dmem[1] == 32'd11);
        check("two stores", store_count == 2);
        check("lane1 branch retired", saw_lane1_branch);
        check("lane1 load retired", saw_lane1_load);
        check("wrong path never retired", !saw_wrong_path_commit);
        check("LSU pair counted", dut.u_regfile_csr.perf_lsu_pair >= 32'd2);
        check("lane1 control counted", dut.u_regfile_csr.perf_lane1_control >= 32'd1);
        check("store/load conflict counted", dut.u_regfile_csr.perf_lsu_conflict >= 32'd1);

        // lane1发生同步异常时，较老lane0必须正常退休，mepc/mtval使用lane1信息。
        @(negedge clk);
        rst_n = 1'b0;
        clear_program();
        imem[0] = 32'h0010_0093; // lane0: addi x1,x0,1
        imem[1] = 32'h0020_2103; // lane1: lw x2,2(x0)，地址非对齐
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        wait (dut.exception_flag);
        @(posedge clk);
        @(posedge clk);
        #1;
        check("lane1 exception preserves lane0", dut.u_regfiles.regfile[1] == 32'd1);
        check("lane1 excepting load not written", dut.u_regfiles.regfile[2] == 32'd0);
        check("lane1 exception mepc", dut.u_regfile_csr.mepc == 32'h8000_0004);
        check("lane1 exception mtval", dut.u_regfile_csr.mtval == 32'h0000_0002);
        check("lane1 exception cause", dut.u_regfile_csr.mcause == 32'd4);

        // lane0异常是bundle最老事件，必须取消同组lane1的写回和退休。
        @(negedge clk);
        rst_n = 1'b0;
        clear_program();
        imem[0] = 32'h0020_2083; // lane0: lw x1,2(x0)，地址非对齐
        imem[1] = 32'h0020_0113; // lane1: addi x2,x0,2，应被取消
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        wait (dut.exception_flag);
        @(posedge clk);
        @(posedge clk);
        #1;
        check("lane0 excepting load not written", dut.u_regfiles.regfile[1] == 32'd0);
        check("lane0 exception kills lane1", dut.u_regfiles.regfile[2] == 32'd0);
        check("lane0 exception mepc", dut.u_regfile_csr.mepc == 32'h8000_0000);
        check("lane0 exception mtval", dut.u_regfile_csr.mtval == 32'h0000_0002);

        if (failures == 0) begin
            $display("MULTI_ISSUE_L2_TEST_PASSED");
        end else begin
            $fatal(1, "MULTI_ISSUE_L2_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end

endmodule
