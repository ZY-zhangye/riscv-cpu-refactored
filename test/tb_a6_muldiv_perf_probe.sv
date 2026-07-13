`timescale 1ns/1ps

// Measurement-only wrapper.  The frozen benchmark testbench and its 21-word
// report layout remain untouched; this probe observes the dedicated A6.4 CSR
// counter at each performance-window falling edge.
module tb_a6_muldiv_perf_probe;
    tb_uart_benchmark u_benchmark();

    logic perf_enable_d;
    integer window_index;
    integer total_muldiv_pairs;

    initial begin
        perf_enable_d = 1'b0;
        window_index = 0;
        total_muldiv_pairs = 0;
    end

    always @(posedge u_benchmark.clk) begin
        perf_enable_d <=
            u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable;
        if (!u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable &&
            perf_enable_d) begin
            if (window_index == 0) begin
                $display("A6_MULDIV_PAIR_BOOT count=%0d",
                         u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair);
            end else begin
                $display("A6_MULDIV_PAIR_WINDOW index=%0d count=%0d",
                         window_index - 1,
                         u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair);
                total_muldiv_pairs = total_muldiv_pairs +
                    u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair;
            end
            window_index = window_index + 1;
        end
    end

    final begin
        $display("A6_MULDIV_PAIR_TOTAL count=%0d windows=%0d",
                 total_muldiv_pairs, window_index - 1);
    end

endmodule
