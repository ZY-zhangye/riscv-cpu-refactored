`timescale 1ns/1ps

module tb_dual_issue_simple;
    localparam int CLK_PERIOD_NS = 10;

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
    logic [4:0] debug_wb_rf_addr;
    logic [31:0] debug_wb_rf_data;
    logic debug_wb_rf_wen;
    logic debug_wb_fpu_rf_wen;
    logic [31:0] debug_data;
    logic saw_lane1_x3;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    cpu_top u_cpu_top (
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
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_data(debug_data)
    );

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        for (int i = 0; i < 64; i++) begin
            imem[i] = 32'h0000_0013; // nop
            dmem[i] = 32'h0;
        end

        // 8000_0000: addi x1, x0, 1
        // 8000_0004: addi x2, x0, 2
        // 8000_0008: addi x3, x0, 3
        // The first two instructions are independent and should be eligible
        // for lane0/lane1 issue when the second fetch port is active.
        imem[0] = 32'h0010_0093;
        imem[1] = 32'h0020_0113;
        imem[2] = 32'h0030_0193;

        imem_rdata = 32'h0000_0013;
        imem_rdata1 = 32'h0000_0013;
        dmem_rdata = 32'h0;
        saw_lane1_x3 = 1'b0;
        rst_n = 1'b0;
        #20;
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            imem_rdata <= 32'h0000_0013;
            imem_rdata1 <= 32'h0000_0013;
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
            dmem_rdata <= 32'h0;
        end else if (dmem_en) begin
            if (dmem_wen[0]) dmem[dmem_addr[7:2]][7:0] <= dmem_wdata[7:0];
            if (dmem_wen[1]) dmem[dmem_addr[7:2]][15:8] <= dmem_wdata[15:8];
            if (dmem_wen[2]) dmem[dmem_addr[7:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wen[3]) dmem[dmem_addr[7:2]][31:24] <= dmem_wdata[31:24];
            dmem_rdata <= dmem[dmem_addr[7:2]];
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (u_cpu_top.regfile_wen1 &&
                (u_cpu_top.regfile_waddr1 == 5'd3) &&
                (u_cpu_top.regfile_wdata1_wb == 32'h0000_0003)) begin
                saw_lane1_x3 <= 1'b1;
            end

            $display("t=%0t if0=%08h en0=%b if1=%08h en1=%b wb0_pc=%08h wb0_we=%b wb0_rd=%0d wb0_data=%08h wb1_we=%b wb1_rd=%0d wb1_data=%08h x3=%08h saw_l1_x3=%b",
                     $time, imem_addr, imem_en, imem_addr1, imem_en1,
                     debug_wb_pc, debug_wb_rf_wen, debug_wb_rf_addr,
                     debug_wb_rf_data, u_cpu_top.regfile_wen1,
                     u_cpu_top.regfile_waddr1, u_cpu_top.regfile_wdata1_wb,
                     debug_data, saw_lane1_x3);
        end
    end

    initial begin
        #300;
        if (saw_lane1_x3 && (debug_data == 32'h0000_0003)) begin
            $display("DUAL_ISSUE_SIMPLE_PASS");
            $finish;
        end
        $display("DUAL_ISSUE_SIMPLE_FAIL saw_lane1_x3=%b x3=%08h",
                 saw_lane1_x3, debug_data);
        $finish;
    end
endmodule
