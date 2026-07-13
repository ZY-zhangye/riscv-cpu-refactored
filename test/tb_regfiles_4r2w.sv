`timescale 1ns/1ps

module tb_regfiles_4r2w;
    logic clk;
    logic rst_n;
    logic write0_wen;
    logic [4:0] write0_waddr;
    logic [31:0] write0_wdata;
    logic write1_wen;
    logic [4:0] write1_waddr;
    logic [31:0] write1_wdata;
    logic [4:0] legacy_raddr1;
    logic [4:0] legacy_raddr2;
    logic [31:0] legacy_rdata1;
    logic [31:0] legacy_rdata2;
    logic sync_ren;
    logic [4:0] sync_raddr0;
    logic [4:0] sync_raddr1;
    logic [4:0] sync_raddr2;
    logic [4:0] sync_raddr3;
    logic [31:0] sync_rdata0;
    logic [31:0] sync_rdata1;
    logic [31:0] sync_rdata2;
    logic [31:0] sync_rdata3;
    logic [31:0] debug_data_unused;

    regfiles dut (
        .clk(clk),
        .rst_n(rst_n),
        .write0_wen(write0_wen),
        .write0_waddr(write0_waddr),
        .write0_wdata(write0_wdata),
        .write1_wen(write1_wen),
        .write1_waddr(write1_waddr),
        .write1_wdata(write1_wdata),
        .regfile_raddr1(legacy_raddr1),
        .regfile_rdata1(legacy_rdata1),
        .regfile_raddr2(legacy_raddr2),
        .regfile_rdata2(legacy_rdata2),
        .sync_ren(sync_ren),
        .sync_raddr0(sync_raddr0),
        .sync_raddr1(sync_raddr1),
        .sync_raddr2(sync_raddr2),
        .sync_raddr3(sync_raddr3),
        .sync_rdata0(sync_rdata0),
        .sync_rdata1(sync_rdata1),
        .sync_rdata2(sync_rdata2),
        .sync_rdata3(sync_rdata3),
        .debug_data(debug_data_unused)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        write0_wen = 1'b0;
        write0_waddr = '0;
        write0_wdata = '0;
        write1_wen = 1'b0;
        write1_waddr = '0;
        write1_wdata = '0;
        legacy_raddr1 = '0;
        legacy_raddr2 = '0;
        sync_ren = 1'b0;
        sync_raddr0 = '0;
        sync_raddr1 = '0;
        sync_raddr2 = '0;
        sync_raddr3 = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Two independent architectural writes.
        write0_wen = 1'b1;
        write0_waddr = 5'd1;
        write0_wdata = 32'h1111_1111;
        write1_wen = 1'b1;
        write1_waddr = 5'd2;
        write1_wdata = 32'h2222_2222;
        @(posedge clk);
        #1;
        legacy_raddr1 = 5'd1;
        legacy_raddr2 = 5'd2;
        #1;
        if ((legacy_rdata1 !== 32'h1111_1111) ||
            (legacy_rdata2 !== 32'h2222_2222)) begin
            $fatal(1, "two-write GPR update failed");
        end

        // Four synchronous reads see same-edge WB data, including x0.
        @(negedge clk);
        write0_waddr = 5'd3;
        write0_wdata = 32'h3333_3333;
        write1_waddr = 5'd4;
        write1_wdata = 32'h4444_4444;
        sync_ren = 1'b1;
        sync_raddr0 = 5'd3;
        sync_raddr1 = 5'd4;
        sync_raddr2 = 5'd0;
        sync_raddr3 = 5'd2;
        @(posedge clk);
        #1;
        if ((sync_rdata0 !== 32'h3333_3333) ||
            (sync_rdata1 !== 32'h4444_4444) ||
            (sync_rdata2 !== 32'b0) ||
            (sync_rdata3 !== 32'h2222_2222)) begin
            $fatal(1, "synchronous 4R WB bypass mismatch");
        end

        // Explicit younger/write1 priority for an otherwise forbidden WAW.
        @(negedge clk);
        write0_waddr = 5'd5;
        write0_wdata = 32'h5555_0000;
        write1_waddr = 5'd5;
        write1_wdata = 32'hAAAA_0000;
        sync_raddr0 = 5'd5;
        @(posedge clk);
        #1;
        legacy_raddr1 = 5'd5;
        #1;
        if ((sync_rdata0 !== 32'hAAAA_0000) ||
            (legacy_rdata1 !== 32'hAAAA_0000)) begin
            $fatal(1, "write1 WAW priority mismatch");
        end

        // x0 ignores both writes, and disabled synchronous reads hold tags/data.
        @(negedge clk);
        write0_waddr = 5'd0;
        write0_wdata = 32'hDEAD_BEEF;
        write1_waddr = 5'd0;
        write1_wdata = 32'hCAFE_BABE;
        sync_ren = 1'b0;
        sync_raddr0 = 5'd1;
        @(posedge clk);
        #1;
        legacy_raddr1 = 5'd0;
        #1;
        if ((legacy_rdata1 !== 32'b0) ||
            (sync_rdata0 !== 32'hAAAA_0000)) begin
            $fatal(1, "x0 or synchronous read hold mismatch");
        end

        $display("REGFILES 4R2W TEST PASSED");
        $finish;
    end

endmodule
