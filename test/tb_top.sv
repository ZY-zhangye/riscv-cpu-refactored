`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"
`include "../rtl/my_cpu/my_cpu_defines.svh"
module tb_uart_benchmark;
    localparam integer CLK_PERIOD_NS = 20; // 仿真步进；性能换算频率由benchmark邮箱给出
    localparam integer PERF_BASE_WORD = 512; // 0x6000_0800映射到data RAM word 512
    localparam logic [31:0] PERF_MAGIC = 32'h4C33_4A30; // "L3J0"
    localparam logic [31:0] PERF_EXPECTED_SINK = 32'h9D3B_F787;
    localparam integer PERF_REPORT_WORDS = 21;
    localparam integer PERF_REPORT_COUNT = 9;

    reg clk;
    reg clk_uart;
    reg rst_n;
    wire [31:0] led;
    wire uart_tx;
    wire plic_irq;
    wire [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts;
    integer failures;
    integer wait_cycles;
    integer report_index;
    integer perf_phase;
    integer queue_depth_cycles [0:4];
    integer downstream_blocked_cycles;
    integer qfull_downstream_cycles;
    integer qfull_capacity_cycles;
    logic perf_enable_d;
    longint unsigned total_cycles;
    longint unsigned total_instret;
    longint unsigned total_ipc_x1000;

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
        .debug_data(debug_data),
        .debug_commit_valid(),
        .debug_commit_inst(),
        .debug_commit_csr_wen(),
        .debug_commit_csr_addr(),
        .debug_commit_csr_data(),
        .debug_wb_pc1(),
        .debug_wb_rf_addr1(),
        .debug_wb_rf_data1(),
        .debug_wb_rf_wen1(),
        .debug_wb_fpu_rf_wen1(),
        .debug_commit_valid1(),
        .debug_commit_inst1(),
        .debug_commit_csr_wen1(),
        .debug_commit_csr_addr1(),
        .debug_commit_csr_data1(),
        .debug_issue_inst0(),
        .debug_issue_pc0(),
        .debug_issue_valid0(),
        .debug_issue_inst1(),
        .debug_issue_pc1(),
        .debug_issue_valid1(),
        .debug_store_valid(),
        .debug_store_pc(),
        .debug_store_addr(),
        .debug_store_wen(),
        .debug_store_wdata()
        `endif
    );

    initial begin
        clk = 1'b0;
        clk_uart = 1'b0;
        rst_n = 1'b0;
        failures = 0;
        perf_phase = -1;
        perf_enable_d = 1'b0;

        // 覆盖默认riscv-tests镜像，加载benchmark镜像
        $readmemh("riscv_sim_perf_bench/out/inst.hex", u_my_cpu.u_inst_ram.mem);
        $readmemh("riscv_sim_perf_bench/out/data.hex", u_my_cpu.u_data_ram.mem);

        #200;
        rst_n = 1'b1;
    end

    always #(CLK_PERIOD_NS/2) clk = ~clk;
    always #(CLK_PERIOD_NS/2) clk_uart = ~clk_uart;


    always @(posedge clk) begin : queue_profile
        integer depth;
        if (!rst_n) begin
            perf_enable_d <= 1'b0;
            perf_phase <= -1;
            downstream_blocked_cycles <= 0;
            qfull_downstream_cycles <= 0;
            qfull_capacity_cycles <= 0;
            for (depth = 0; depth <= 4; depth = depth + 1) begin
                queue_depth_cycles[depth] <= 0;
            end
        end else begin
            perf_enable_d <= u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable;

            if (u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable && !perf_enable_d) begin
                if (perf_phase >= 0) begin
                    $display("L3J_WINDOW_START phase=%0d fetch_pc=%08h wb_pc=%08h",
                             perf_phase, debug_inst_pc, debug_wb_pc);
                end
                downstream_blocked_cycles <= !u_my_cpu.u_cpu_top.ds_bundle_allowin;
                qfull_downstream_cycles <=
                    u_my_cpu.u_cpu_top.u_issue_stage.queue_full_event_now &&
                    !u_my_cpu.u_cpu_top.ds_bundle_allowin;
                qfull_capacity_cycles <=
                    u_my_cpu.u_cpu_top.u_issue_stage.queue_full_event_now &&
                    u_my_cpu.u_cpu_top.ds_bundle_allowin;
                for (depth = 0; depth <= 4; depth = depth + 1) begin
                    queue_depth_cycles[depth] <=
                        (u_my_cpu.u_cpu_top.u_issue_stage.queue_count == depth) ? 1 : 0;
                end
            end else if (u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable) begin
                queue_depth_cycles[u_my_cpu.u_cpu_top.u_issue_stage.queue_count] <=
                    queue_depth_cycles[u_my_cpu.u_cpu_top.u_issue_stage.queue_count] + 1;
                if (!u_my_cpu.u_cpu_top.ds_bundle_allowin) begin
                    downstream_blocked_cycles <= downstream_blocked_cycles + 1;
                end
                if (u_my_cpu.u_cpu_top.u_issue_stage.queue_full_event_now) begin
                    if (!u_my_cpu.u_cpu_top.ds_bundle_allowin) begin
                        qfull_downstream_cycles <= qfull_downstream_cycles + 1;
                    end else begin
                        qfull_capacity_cycles <= qfull_capacity_cycles + 1;
                    end
                end
            end

            if (!u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable && perf_enable_d) begin
                if (perf_phase >= 0) begin
                    $display("L3J_WINDOW_END phase=%0d fetch_pc=%08h wb_pc=%08h",
                             perf_phase, debug_inst_pc, debug_wb_pc);
                    $display("L3J_QUEUE phase=%0d depth0=%0d depth1=%0d depth2=%0d depth3=%0d depth4=%0d downstream_blocked=%0d qfull_downstream=%0d qfull_capacity=%0d",
                             perf_phase,
                             queue_depth_cycles[0], queue_depth_cycles[1],
                             queue_depth_cycles[2], queue_depth_cycles[3],
                             queue_depth_cycles[4], downstream_blocked_cycles,
                             qfull_downstream_cycles, qfull_capacity_cycles);
                end
                perf_phase <= perf_phase + 1;
            end
        end
    end

    initial begin
        $display("[TB] SoC simulation started.");
    end

    function automatic logic [31:0] perf_word(input integer offset);
        perf_word = u_my_cpu.u_data_ram.mem[PERF_BASE_WORD + offset];
    endfunction

    task automatic display_report(input string report_name, input integer offset);
        logic [31:0] cycles;
        logic [31:0] instret;
        logic [31:0] exceptions;
        longint unsigned instret_wide;
        longint unsigned ipc_x1000;
        begin
            cycles = perf_word(offset + 0);
            instret = perf_word(offset + 1);
            exceptions = perf_word(offset + 8);
            instret_wide = instret;
            ipc_x1000 = (cycles != 0) ? ((instret_wide * 1000) / cycles) : 0;

            $display("L3J_REPORT name=%s cycles=%0d instret=%0d ipc_x1000=%0d branch=%0d brmisp=%0d loaduse=%0d multidep=%0d exstall=%0d dual=%0d single=%0d raw=%0d waw=%0d struct=%0d lsu_pair=%0d lane1_ctrl=%0d lsu_conflict=%0d bitman_pair=%0d cross_packet=%0d qfull=%0d exceptions=%0d",
                     report_name, cycles, instret, ipc_x1000,
                     perf_word(offset + 2), perf_word(offset + 3),
                     perf_word(offset + 6), perf_word(offset + 20),
                     perf_word(offset + 7),
                     perf_word(offset + 9), perf_word(offset + 10),
                     perf_word(offset + 11), perf_word(offset + 12),
                     perf_word(offset + 13), perf_word(offset + 14),
                     perf_word(offset + 15), perf_word(offset + 16),
                     perf_word(offset + 17), perf_word(offset + 18),
                     perf_word(offset + 19), exceptions);

            if ((cycles == 0) || (instret == 0) || (exceptions != 0)) begin
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        wait (rst_n);
        wait_cycles = 0;
        while ((perf_word(0) !== PERF_MAGIC) && (wait_cycles < 5_000_000)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (perf_word(0) !== PERF_MAGIC) begin
            $display("[TB] Timeout waiting for L3J performance mailbox.");
`ifdef DEBUG_EN
            $display("[TB] debug_inst_pc=%08h debug_wb_pc=%08h", debug_inst_pc, debug_wb_pc);
`endif
            $fatal(1, "PERF_BENCHMARK_TIMEOUT");
        end

        $display("L3J_HEADER version=%0d cpu_freq_hz=%0d sink=%08h sim_cycles=%0d",
                 perf_word(1), perf_word(2), perf_word(3), wait_cycles);
        if ((perf_word(1) != 5) || (perf_word(2) == 0) ||
            (perf_word(3) != PERF_EXPECTED_SINK)) begin
            failures = failures + 1;
        end

        display_report("ALU", 4);
        display_report("MEXT", 4 + PERF_REPORT_WORDS);
        display_report("BRANCH_RANDOM", 4 + (2 * PERF_REPORT_WORDS));
        display_report("BRANCH_REGULAR", 4 + (3 * PERF_REPORT_WORDS));
        display_report("BRANCH_SHORT", 4 + (4 * PERF_REPORT_WORDS));
        display_report("BRANCH_CALL", 4 + (5 * PERF_REPORT_WORDS));
        display_report("BRANCH_CAPACITY", 4 + (6 * PERF_REPORT_WORDS));
        display_report("BRANCH_RETURN", 4 + (7 * PERF_REPORT_WORDS));
        display_report("MEMORY", 4 + (8 * PERF_REPORT_WORDS));

        total_cycles = 0;
        total_instret = 0;
        for (report_index = 0; report_index < PERF_REPORT_COUNT;
             report_index = report_index + 1) begin
            total_cycles = total_cycles +
                           perf_word(4 + (report_index * PERF_REPORT_WORDS));
            total_instret = total_instret +
                            perf_word(5 + (report_index * PERF_REPORT_WORDS));
        end
        total_ipc_x1000 = (total_instret * 1000) / total_cycles;
        $display("L3J_OVERALL cycles=%0d instret=%0d ipc_x1000=%0d",
                 total_cycles, total_instret, total_ipc_x1000);

        if (failures == 0) begin
            $display("PERF_BENCHMARK_PASSED");
            $finish;
        end else begin
            $fatal(1, "PERF_BENCHMARK_FAILED failures=%0d", failures);
        end
    end


endmodule
