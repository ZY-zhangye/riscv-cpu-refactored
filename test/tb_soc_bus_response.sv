`timescale 1ns/1ps
`include "my_cpu_defines.svh"

// Exercise the actual RAM/bridge/IO/PLIC response chain at the fixed one-cycle
// CPU interface, including consecutive target changes and read side effects.
module tb_soc_bus_response;
    parameter bit RAM_SYNC = 1'b1;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic en = 0;
    logic [31:0] addr = 0, wdata = 0, rdata;
    logic [3:0] wen = 0;
    wire ram_en, io_sel, io_re, plic_sel, plic_re, plic_we;
    wire [31:0] ram_addr, ram_wdata, ram_rdata;
    wire [3:0] ram_wen, io_wen;
    wire [31:0] io_addr, io_wdata, io_rdata;
    wire [31:0] plic_addr, plic_wdata, plic_rdata;
    wire [31:0] led, internal_irq;
    logic [31:0] external_irq = 0;
    wire uart_tx, plic_irq;
    integer checks = 0;

    bridge #(.RAM_SYNCHRONOUS_READ(RAM_SYNC)) dut (
        .clk(clk), .rst_n(rst_n), .cpu_dmem_en(en),
        .cpu_dmem_addr(addr), .cpu_dmem_wen(wen), .cpu_dmem_wdata(wdata),
        .cpu_dmem_rdata(rdata), .ram_en(ram_en), .ram_addr(ram_addr),
        .ram_wen(ram_wen), .ram_wdata(ram_wdata), .ram_rdata(ram_rdata),
        .io_sel(io_sel), .io_re(io_re), .io_wen(io_wen), .io_addr(io_addr),
        .io_wdata(io_wdata), .io_rdata(io_rdata), .plic_sel(plic_sel),
        .plic_re(plic_re), .plic_we(plic_we), .plic_addr(plic_addr),
        .plic_wdata(plic_wdata), .plic_rdata(plic_rdata)
    );
    soc_data_ram #(.WORDS(64), .SYNCHRONOUS_READ(RAM_SYNC)) ram (
        .clk(clk), .addr(ram_addr), .en(ram_en), .wen(ram_wen),
        .wdata(ram_wdata), .rdata(ram_rdata)
    );
    IO io (
        .clk(clk), .rst_n(rst_n), .clk_uart(1'b0), .io_sel(io_sel),
        .io_re(io_re), .io_wen(io_wen), .io_addr(io_addr),
        .io_wdata(io_wdata), .io_rdata(io_rdata), .uart_rx(1'b1),
        .uart_tx(uart_tx), .led(led), .peripheral_interrupts(internal_irq)
    );
    PLIC plic (
        .clk(clk), .rst_n(rst_n), .peripheral_interrupts(external_irq | internal_irq),
        .plic_irq(plic_irq), .plic_sel(plic_sel), .plic_we(plic_we),
        .plic_re(plic_re), .plic_addr(plic_addr), .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
    );

    task automatic put(input logic [31:0] address, value,
                       input logic [3:0] strobe = 4'hf);
        @(negedge clk);
        en = 1; addr = address; wdata = value; wen = strobe;
        @(posedge clk); #1;
    endtask
    task automatic get(input logic [31:0] address, expected);
        @(negedge clk);
        en = 1; addr = address; wen = 0;
        @(posedge clk); #1;
        if (rdata !== expected)
            $fatal(1, "RAM_SYNC=%0d addr=%h expected=%h actual=%h",
                   RAM_SYNC, address, expected, rdata);
        checks++;
    endtask
    task automatic idle;
        @(negedge clk); en = 0; wen = 0;
        @(posedge clk); #1;
        if (rdata !== 0) $fatal(1, "Idle response must be zero");
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        // An isolated first read must return the current peripheral register,
        // not a reset-zero value from a redundant bridge response register.
        get(32'h8001_000c, 868);
        get(32'h8001_0004, 1);
        put(32'h8001_000c, 433);
        put(32'h8001_0008, 32'h14);
        put(32'h8003_0000, 32'h12345678);
        put(32'h8002_0000, 32'h00abcdef);
        put(32'h8030_001c, 5);
        put(32'h8010_0000, 32'hcafebabe);
        put(32'h8010_0004, 32'h10203040);

        // No idle cycles between reads: the response mux must follow each
        // request's registered target while each target updates its response.
        get(32'h8010_0000, 32'hcafebabe);
        get(32'h8001_000c, 433);
        get(32'h8002_0000, 32'h00abcdef);
        get(32'h8003_0000, 32'h12345678);
        get(32'h8030_001c, 5);
        get(32'h8010_0004, 32'h10203040);
        get(32'h8001_0008, 32'h14);
        idle();
        get(32'h8001_000c, 433);
        put(32'h8010_0000, 32'h0000005a, 4'b0001);
        put(32'h8010_0000, 32'h76540000, 4'b1100);
        get(32'h8010_0000, 32'h7654ba5a);
        put(32'h8003_0000, 32'h00aa0000, 4'b0100);
        get(32'h8003_0000, 32'h12aa5678);

        put(32'h8030_2000, 32'h80);
        put(32'h8030_4000, 0);
        idle();
        external_irq[7] = 1;
        repeat (6) @(negedge clk);
        if (!plic_irq) $fatal(1, "PLIC request did not assert");
        get(32'h8030_4004, 7);
        external_irq[7] = 0;
        get(32'h8030_5000, 32'h80);
        idle();
        repeat (4) @(negedge clk);
        get(32'h8030_4004, 0);
        put(32'h8030_4004, 7);
        get(32'h8030_5000, 0);
        get(32'h9000_0000, 0);
        idle();
        $display("SOC_BUS_RESPONSE_PASS RAM_SYNC=%0d checks=%0d", RAM_SYNC, checks);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Bus response test timed out");
    end
endmodule
