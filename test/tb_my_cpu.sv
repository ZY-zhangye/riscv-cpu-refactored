`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"
`include "../rtl/my_cpu/my_cpu_defines.svh"

module tb_my_cpu;
    localparam string MEM_ADDR = "hex/riscv-tests/rv32-p-riscv.hex";
    localparam int CLK_PERIOD_NS = 10;
    // A5 makes every Load occupy E0-E3 and every Store occupy E0-E1.
    // Keep a finite watchdog, but leave enough budget for the mandated LSU
    // residency so a functionally completed ISA test is not classified as a
    // hang solely because it crossed the pre-A5 10 us limit.
    localparam int TIMEOUT_NS = 20000;

    logic clk;
    logic clk_uart;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic [31:0] led;
    logic plic_irq;
    logic [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts;

`ifdef DEBUG_EN
    logic [31:0] debug_inst_pc;
    logic [31:0] debug_wb_pc;
    logic [4:0]  debug_wb_rf_addr;
    logic [31:0] debug_wb_rf_data;
    logic        debug_wb_rf_wen;
    logic        debug_wb_fpu_rf_wen;
    logic [31:0] debug_data;
    logic        debug_commit_valid;
    logic [31:0] debug_commit_inst;
    logic        debug_commit_csr_wen;
    logic [11:0] debug_commit_csr_addr;
    logic [31:0] debug_commit_csr_data;
    logic        debug_store_valid;
    logic [31:0] debug_store_pc;
    logic [31:0] debug_store_addr;
    logic [3:0]  debug_store_wen;
    logic [31:0] debug_store_wdata;
`endif

    assign external_interrupts = '0;
    assign uart_rx = 1'b1;

    my_cpu u_my_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .uart_rx(uart_rx),
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
        .debug_data(debug_data),
        .debug_commit_valid(debug_commit_valid),
        .debug_commit_inst(debug_commit_inst),
        .debug_commit_csr_wen(debug_commit_csr_wen),
        .debug_commit_csr_addr(debug_commit_csr_addr),
        .debug_commit_csr_data(debug_commit_csr_data),
        .debug_store_valid(debug_store_valid),
        .debug_store_pc(debug_store_pc),
        .debug_store_addr(debug_store_addr),
        .debug_store_wen(debug_store_wen),
        .debug_store_wdata(debug_store_wdata)
`endif
    );

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        clk_uart = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk_uart = ~clk_uart;
    end

    initial begin
        rst_n = 1'b0;

`ifdef DEBUG_EN
        $readmemh(MEM_ADDR, u_my_cpu.u_inst_ram.mem);
        $readmemh(MEM_ADDR, u_my_cpu.u_data_ram.mem);
`else
        $fatal(1, "tb_my_cpu requires DEBUG_EN so internal debug RAMs and ports exist.");
`endif

        #20;
        rst_n = 1'b1;
    end

`ifdef DEBUG_EN
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            $display("Time: %0t, Reset asserted", $time);
        end else begin
            $display("Time: %0t", $time);
            $display("debug_inst_pc: %h", debug_inst_pc);
            $display("debug_wb_pc: %h", debug_wb_pc);
            $display("debug_wb_rf_wen: %b", debug_wb_rf_wen);
            $display("debug_wb_rf_wnum: %h", debug_wb_rf_addr);
            $display("debug_wb_rf_data: %h", debug_wb_rf_data);
            $display("debug_data: %h", debug_data);
            $display("debug_wb_fpu_rf_wen: %b", debug_wb_fpu_rf_wen);
            $display("led: %h", led);
            $display("plic_irq: %b", plic_irq);
            $display("--------------------------------------------------");

            if (debug_commit_valid) begin
                $display("COMMIT pc=%08h inst=%08h gpr_wen=%0b gpr_addr=%0d gpr_data=%08h fpr_wen=%0b csr_wen=%0b csr_addr=%03h csr_data=%08h",
                         debug_wb_pc, debug_commit_inst, debug_wb_rf_wen,
                         debug_wb_rf_addr, debug_wb_rf_data, debug_wb_fpu_rf_wen,
                         debug_commit_csr_wen, debug_commit_csr_addr,
                         debug_commit_csr_data);
            end

            if (debug_store_valid) begin
                $display("STORE pc=%08h addr=%08h wen=%01h data=%08h",
                         debug_store_pc, debug_store_addr, debug_store_wen,
                         debug_store_wdata);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n && debug_commit_valid && (debug_wb_pc == 32'h8000_0044)) begin
            $display("---------------------------------------------");
            $display("Time: %0t", $time);
            $display("Simulation finished.");
            $display("----------------------------------------------");
            if (debug_data == 32'h0000_0001) begin
                $display("Test passed.");
            end else begin
                $display("Test failed. Expected 1 in x10, got %08h", debug_data);
            end
            $display("----------------------------------------------");
            $stop;
        end
    end
`endif

    initial begin
        #TIMEOUT_NS;
        $display("Simulation timeout");
`ifdef DEBUG_EN
        $display("debug_inst_pc: %h", debug_inst_pc);
        $display("debug_wb_pc: %h", debug_wb_pc);
        $display("debug_data: %h", debug_data);
`endif
        $finish;
    end

endmodule
