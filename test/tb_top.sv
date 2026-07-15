`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"
`include "../rtl/my_cpu/my_cpu_defines.svh"

module tb_uart_benchmark;
    localparam integer CLK_PERIOD_NS = 20;
    localparam integer PERF_BASE_WORD = 512;
    localparam logic [31:0] PERF_MAGIC = 32'h5045_5246;
    localparam logic [31:0] EXPECTED_SINK = 32'hF5B4_D4AE;
    localparam integer TIMEOUT_CYCLES = 2_000_000;

    logic clk;
    logic clk_uart;
    logic rst_n;
    logic uart_tx;
    logic [31:0] led;
    logic plic_irq;
    logic [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts;
    integer elapsed_cycles;

`ifdef DEBUG_EN
    logic [31:0] debug_inst_pc;
    logic [31:0] debug_wb_pc;
    logic        debug_wb_rf_wen;
    logic [4:0]  debug_wb_rf_addr;
    logic [31:0] debug_wb_rf_data;
    logic        debug_wb_fpu_rf_wen;
    logic [31:0] debug_data;
`endif

    assign external_interrupts = '0;

    my_cpu u_my_cpu (
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
        elapsed_cycles = 0;

        $readmemh("riscv_sim_perf_bench/out/inst.hex", u_my_cpu.u_inst_ram.mem);
        $readmemh("riscv_sim_perf_bench/out/data.hex", u_my_cpu.u_data_ram.mem);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[PERF] RTL benchmark started");
    end

    always #(CLK_PERIOD_NS / 2) clk = ~clk;
    always #(CLK_PERIOD_NS / 2) clk_uart = ~clk_uart;

    always @(posedge clk) begin
        if (rst_n) begin
            elapsed_cycles <= elapsed_cycles + 1;

            if (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD] == PERF_MAGIC) begin
                $display("[PERF] ALU    cycles=%0d instret=%0d CPI(x1000)=%0d",
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 2],
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 3],
                         (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 2] * 1000) /
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 3]);
                $display("[PERF] BRANCH cycles=%0d instret=%0d CPI(x1000)=%0d",
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 4],
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 5],
                         (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 4] * 1000) /
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 5]);
                $display("[PERF] MEMORY cycles=%0d instret=%0d CPI(x1000)=%0d",
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 6],
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 7],
                         (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 6] * 1000) /
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 7]);
                $display("[PERF] OVERALL cycles=%0d instret=%0d CPI(x1000)=%0d",
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 8],
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 9],
                         (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 8] * 1000) /
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 9]);
                $display("[PERF] sink=%08h rtl_elapsed_cycles=%0d",
                         u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 10], elapsed_cycles);

                if (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 1] != 32'd1) begin
                    $fatal(1, "[PERF] unsupported result version");
                end
                if (u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + 10] != EXPECTED_SINK) begin
                    $fatal(1, "[PERF] sink mismatch: expected %08h", EXPECTED_SINK);
                end

                $display("[PERF] PASS");
                $finish;
            end

            if (elapsed_cycles >= TIMEOUT_CYCLES) begin
`ifdef DEBUG_EN
                $display("[PERF] timeout pc=%08h wb_pc=%08h", debug_inst_pc, debug_wb_pc);
`endif
                $fatal(1, "[PERF] benchmark timeout");
            end
        end
    end
endmodule
