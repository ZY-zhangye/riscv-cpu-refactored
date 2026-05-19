`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"
`include "../rtl/my_cpu/my_cpu_defines.svh"
module tb_uart_benchmark;
    localparam integer CLK_PERIOD_NS = 20;     // 50MHz

    reg clk;
    reg clk_uart;
    reg rst_n;
    wire [31:0] led;
    wire uart_tx;
    wire plic_irq;
    wire [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts;

`ifdef DEBUG_EN
    wire [31:0] debug_inst_pc;
    wire [31:0] debug_wb_pc;
    wire        debug_wb_rf_wen;
    wire [4:0]  debug_wb_rf_addr;
    wire [31:0] debug_wb_rf_data;
    wire        debug_wb_fpu_rf_wen;
    wire [31:0] debug_data;
`endif

    assign external_interrupts = '0;

    my_cpu u_my_cpu(
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .uart_rx(1'b1),
        .external_interrupts(external_interrupts),
        .uart_tx(uart_tx),
        .led(led),
        .plic_irq(plic_irq)
        `ifdef DEBUG_EN
        ,
        .debug_inst_pc(debug_inst_pc),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_data(debug_data)
        `endif
    );

    initial begin
        clk = 1'b0;
        clk_uart = 1'b0;
        rst_n = 1'b0;

        // 覆盖默认riscv-tests镜像，加载benchmark镜像
        $readmemh("riscv_sim_perf_bench/out/inst.hex", u_my_cpu.u_inst_ram.mem);
        $readmemh("riscv_sim_perf_bench/out/data.hex", u_my_cpu.u_data_ram.mem);

        #200;
        rst_n = 1'b1;
    end

    always #(CLK_PERIOD_NS/2) clk = ~clk;
    always #(CLK_PERIOD_NS/2) clk_uart = ~clk_uart;

    initial begin
        $display("[TB] SoC simulation started.");
    end

    always @(posedge clk) begin
        if (rst_n) begin
`ifdef DEBUG_EN
            $display("[TB] pc=%08h wb_pc=%08h rf_wen=%b rf_addr=%02h rf_data=%08h debug_data=%08h led=%08h irq=%b",
                     debug_inst_pc, debug_wb_pc, debug_wb_rf_wen,
                     debug_wb_rf_addr, debug_wb_rf_data, debug_data, led, plic_irq);
`else
            $display("[TB] led=%08h irq=%b uart_tx=%b", led, plic_irq, uart_tx);
`endif
        end
    end

    initial begin
        #20_000_000;
        $display("\n[TB] Timeout: SoC simulation reached limit.");
`ifdef DEBUG_EN
        $display("[TB] debug_inst_pc=%08h debug_wb_pc=%08h", debug_inst_pc, debug_wb_pc);
`endif
        $finish;
    end


endmodule
