`timescale 1ns/1ps

// Questa专项测试使用的同步单端口BRAM模型；Vivado构建仍使用blk_mem_gen_0 OOC IP。
module blk_mem_gen_0 (
    input  logic        clka,
    input  logic        ena,
    input  logic [3:0]  wea,
    input  logic [15:0] addra,
    input  logic [31:0] dina,
    output logic [31:0] douta
);
    logic [31:0] mem [0:255];

    initial begin
        integer i;
        for (i = 0; i < 256; i++) begin
            mem[i] = 32'b0;
        end
        mem[4] = 32'h1122_3344;
        douta = 32'b0;
    end

    always @(posedge clka) begin
        if (ena) begin
            if (wea[0]) mem[addra][7:0]   <= dina[7:0];
            if (wea[1]) mem[addra][15:8]  <= dina[15:8];
            if (wea[2]) mem[addra][23:16] <= dina[23:16];
            if (wea[3]) mem[addra][31:24] <= dina[31:24];
            douta <= mem[addra];
        end
    end
endmodule

module tb_dram_driver;
    logic clk;
    logic [17:0] perip_addr;
    logic [31:0] perip_wdata;
    logic [3:0] perip_mask;
    logic dram_wen;
    logic perip_ren;
    logic [31:0] perip_rdata;
    int failures;

    dram_driver dut (
        .clk(clk),
        .perip_addr(perip_addr),
        .perip_wdata(perip_wdata),
        .perip_mask(perip_mask),
        .dram_wen(dram_wen),
        .perip_ren(perip_ren),
        .perip_rdata(perip_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures++;
            $display("DRAM_DRIVER_CHECK_FAIL %s time=%0t", name, $time);
        end
    endtask

    initial begin
        failures = 0;
        perip_addr = 18'd16;
        perip_wdata = 32'b0;
        perip_mask = 4'b0;
        dram_wen = 1'b0;
        perip_ren = 1'b0;

        // BRAM常开，但返回仍是同步一拍。
        @(posedge clk);
        #1;
        check("BRAM enable tied high", dut.u_dram.ena === 1'b1);
        check("synchronous read", perip_rdata == 32'h1122_3344);

        // 模拟MMIO写：mask非零但dram_wen为0，DRAM内容必须保持。
        @(negedge clk);
        perip_wdata = 32'hdead_beef;
        perip_mask = 4'b1111;
        dram_wen = 1'b0;
        @(posedge clk);
        #1;
        check("non-DRAM write mask blocked", dut.dram_we == 4'b0000);
        check("non-DRAM write does not corrupt", dut.u_dram.mem[4] == 32'h1122_3344);

        // DRAM字节写必须继续遵守perip_mask。
        @(negedge clk);
        perip_wdata = 32'h0000_aa00;
        perip_mask = 4'b0010;
        dram_wen = 1'b1;
        @(posedge clk);
        #1;
        check("DRAM write mask enabled", dut.dram_we == 4'b0010);
        check("byte write committed", dut.u_dram.mem[4] == 32'h1122_aa44);

        @(negedge clk);
        perip_mask = 4'b0000;
        dram_wen = 1'b0;
        perip_ren = 1'b1;
        @(posedge clk);
        #1;
        check("readback after byte write", perip_rdata == 32'h1122_aa44);

        if (failures == 0) begin
            $display("DRAM_DRIVER_TEST_PASSED");
        end else begin
            $fatal(1, "DRAM_DRIVER_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end
endmodule
