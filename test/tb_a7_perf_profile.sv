`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

// Measurement-only wrapper for the frozen nine-window benchmark.  It observes
// existing internal events and does not alter RTL, the benchmark mailbox, or
// the 21-word report emitted by tb_uart_benchmark.
module tb_a7_perf_profile;
    tb_uart_benchmark u_benchmark();

    logic perf_enable_d;
    integer window_index;

    longint unsigned imem_requests;
    longint unsigned fetch_packets;
    longint unsigned fetch_uops;
    longint unsigned fetch_single_packets;
    longint unsigned fetch_empty_cycles;
    longint unsigned dual_launches;
    longint unsigned simple_pair_launches;
    longint unsigned simple_singleton_launches;
    longint unsigned control_singleton_launches;
    longint unsigned muldiv_singleton_launches;
    longint unsigned lane1_control_launches;
    longint unsigned control0_simple_launches;
    longint unsigned control0_lane1_kills;
    longint unsigned dual_retire1_cycles;
    longint unsigned dual_retire2_cycles;
    longint unsigned zero_retire_cycles;
    longint unsigned dispatch_zero_retire_cycles;
    longint unsigned legacy_control_singletons;
    longint unsigned legacy_muldiv_singletons;
    longint unsigned legacy_to_dual_transitions;
    longint unsigned dual_to_legacy_transitions;
    longint unsigned legacy_pair_fallbacks;
    longint unsigned legacy_prefer_fallbacks;
    longint unsigned legacy_drain_wait_cycles;
    longint unsigned dual_backend_wait_cycles;

    longint unsigned total_imem_requests;
    longint unsigned total_fetch_packets;
    longint unsigned total_fetch_uops;
    longint unsigned total_fetch_single_packets;
    longint unsigned total_fetch_empty_cycles;
    longint unsigned total_dual_launches;
    longint unsigned total_simple_pair_launches;
    longint unsigned total_simple_singleton_launches;
    longint unsigned total_control_singleton_launches;
    longint unsigned total_muldiv_singleton_launches;
    longint unsigned total_lane1_control_launches;
    longint unsigned total_control0_simple_launches;
    longint unsigned total_control0_lane1_kills;
    longint unsigned total_dual_retire1_cycles;
    longint unsigned total_dual_retire2_cycles;
    longint unsigned total_zero_retire_cycles;
    longint unsigned total_dispatch_zero_retire_cycles;
    longint unsigned total_legacy_control_singletons;
    longint unsigned total_legacy_muldiv_singletons;
    longint unsigned total_legacy_to_dual_transitions;
    longint unsigned total_dual_to_legacy_transitions;
    longint unsigned total_legacy_pair_fallbacks;
    longint unsigned total_legacy_prefer_fallbacks;
    longint unsigned total_legacy_drain_wait_cycles;
    longint unsigned total_dual_backend_wait_cycles;

    function automatic string perf_window_name(input integer index);
        begin
            case (index)
                0: perf_window_name = "ALU";
                1: perf_window_name = "MEXT";
                2: perf_window_name = "BRANCH_RANDOM";
                3: perf_window_name = "BRANCH_REGULAR";
                4: perf_window_name = "BRANCH_SHORT";
                5: perf_window_name = "BRANCH_CALL";
                6: perf_window_name = "BRANCH_CAPACITY";
                7: perf_window_name = "BRANCH_RETURN";
                8: perf_window_name = "MEMORY";
                default: perf_window_name = "UNKNOWN";
            endcase
        end
    endfunction

    task automatic clear_window_counters;
        begin
            imem_requests = 0;
            fetch_packets = 0;
            fetch_uops = 0;
            fetch_single_packets = 0;
            fetch_empty_cycles = 0;
            dual_launches = 0;
            simple_pair_launches = 0;
            simple_singleton_launches = 0;
            control_singleton_launches = 0;
            muldiv_singleton_launches = 0;
            lane1_control_launches = 0;
            control0_simple_launches = 0;
            control0_lane1_kills = 0;
            dual_retire1_cycles = 0;
            dual_retire2_cycles = 0;
            zero_retire_cycles = 0;
            dispatch_zero_retire_cycles = 0;
            legacy_control_singletons = 0;
            legacy_muldiv_singletons = 0;
            legacy_to_dual_transitions = 0;
            dual_to_legacy_transitions = 0;
            legacy_pair_fallbacks = 0;
            legacy_prefer_fallbacks = 0;
            legacy_drain_wait_cycles = 0;
            dual_backend_wait_cycles = 0;
        end
    endtask

    task automatic check_window_invariants;
        longint unsigned class_launches;
        begin
            class_launches = simple_pair_launches +
                simple_singleton_launches +
                control_singleton_launches +
                muldiv_singleton_launches +
                lane1_control_launches +
                control0_simple_launches +
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_lsu_pair +
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair;
            if (fetch_uops != ((2 * fetch_packets) - fetch_single_packets)) begin
                $fatal(1,
                       "A7 profile fetch identity failed: uops=%0d packets=%0d single=%0d",
                       fetch_uops, fetch_packets, fetch_single_packets);
            end
            if (dual_launches != class_launches) begin
                $fatal(1,
                       "A7 profile launch identity failed: launch=%0d simple_pair=%0d simple_single=%0d control_single=%0d muldiv_single=%0d control1=%0d control0=%0d lsu=%0d muldiv_pair=%0d",
                       dual_launches, simple_pair_launches,
                       simple_singleton_launches,
                       control_singleton_launches,
                       muldiv_singleton_launches,
                       lane1_control_launches,
                       control0_simple_launches,
                       u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_lsu_pair,
                       u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair);
            end
            if (dual_launches !=
                (dual_retire1_cycles + dual_retire2_cycles)) begin
                $fatal(1,
                       "A7 profile retire identity failed: launch=%0d retire1=%0d retire2=%0d",
                       dual_launches, dual_retire1_cycles,
                       dual_retire2_cycles);
            end
            if (legacy_prefer_fallbacks > legacy_pair_fallbacks) begin
                $fatal(1,
                       "A7 profile fallback subset failed: prefer=%0d total=%0d",
                       legacy_prefer_fallbacks, legacy_pair_fallbacks);
            end
        end
    endtask

    task automatic print_window(input integer report_index);
        begin
            $display("A7_PROFILE_WINDOW index=%0d name=%s cycles=%0d instret=%0d issue_pair=%0d issue_single=%0d imem_req=%0d packets=%0d fetch_uops=%0d single_packet=%0d fetch_empty=%0d dual_launch=%0d simple_pair=%0d simple_single=%0d control_single=%0d muldiv_single=%0d control1_pair=%0d control1_csr=%0d control0_pair=%0d control0_kill=%0d lsu_pair=%0d muldiv_pair=%0d retire1=%0d retire2=%0d zero_retire=%0d dispatch_zero=%0d legacy_control_single=%0d legacy_muldiv_single=%0d legacy_to_dual=%0d dual_to_legacy=%0d legacy_pair=%0d legacy_prefer=%0d legacy_nonprefer=%0d wait_legacy=%0d wait_dual=%0d",
                     report_index, perf_window_name(report_index),
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_cycle,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_instret,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_dual_issue,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_single_issue,
                     imem_requests, fetch_packets, fetch_uops,
                     fetch_single_packets, fetch_empty_cycles,
                     dual_launches, simple_pair_launches,
                     simple_singleton_launches,
                     control_singleton_launches,
                     muldiv_singleton_launches,
                     lane1_control_launches,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_lane1_control,
                     control0_simple_launches, control0_lane1_kills,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_lsu_pair,
                     u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair,
                     dual_retire1_cycles, dual_retire2_cycles,
                     zero_retire_cycles, dispatch_zero_retire_cycles,
                     legacy_control_singletons, legacy_muldiv_singletons,
                     legacy_to_dual_transitions, dual_to_legacy_transitions,
                     legacy_pair_fallbacks,
                     legacy_prefer_fallbacks,
                     legacy_pair_fallbacks - legacy_prefer_fallbacks,
                     legacy_drain_wait_cycles, dual_backend_wait_cycles);
        end
    endtask

    task automatic add_window_to_totals;
        begin
            total_imem_requests += imem_requests;
            total_fetch_packets += fetch_packets;
            total_fetch_uops += fetch_uops;
            total_fetch_single_packets += fetch_single_packets;
            total_fetch_empty_cycles += fetch_empty_cycles;
            total_dual_launches += dual_launches;
            total_simple_pair_launches += simple_pair_launches;
            total_simple_singleton_launches += simple_singleton_launches;
            total_control_singleton_launches += control_singleton_launches;
            total_muldiv_singleton_launches += muldiv_singleton_launches;
            total_lane1_control_launches += lane1_control_launches;
            total_control0_simple_launches += control0_simple_launches;
            total_control0_lane1_kills += control0_lane1_kills;
            total_dual_retire1_cycles += dual_retire1_cycles;
            total_dual_retire2_cycles += dual_retire2_cycles;
            total_zero_retire_cycles += zero_retire_cycles;
            total_dispatch_zero_retire_cycles += dispatch_zero_retire_cycles;
            total_legacy_control_singletons += legacy_control_singletons;
            total_legacy_muldiv_singletons += legacy_muldiv_singletons;
            total_legacy_to_dual_transitions += legacy_to_dual_transitions;
            total_dual_to_legacy_transitions += dual_to_legacy_transitions;
            total_legacy_pair_fallbacks += legacy_pair_fallbacks;
            total_legacy_prefer_fallbacks += legacy_prefer_fallbacks;
            total_legacy_drain_wait_cycles += legacy_drain_wait_cycles;
            total_dual_backend_wait_cycles += dual_backend_wait_cycles;
        end
    endtask

    initial begin
        perf_enable_d = 1'b0;
        window_index = 0;
        clear_window_counters();
        total_imem_requests = 0;
        total_fetch_packets = 0;
        total_fetch_uops = 0;
        total_fetch_single_packets = 0;
        total_fetch_empty_cycles = 0;
        total_dual_launches = 0;
        total_simple_pair_launches = 0;
        total_simple_singleton_launches = 0;
        total_control_singleton_launches = 0;
        total_muldiv_singleton_launches = 0;
        total_lane1_control_launches = 0;
        total_control0_simple_launches = 0;
        total_control0_lane1_kills = 0;
        total_dual_retire1_cycles = 0;
        total_dual_retire2_cycles = 0;
        total_zero_retire_cycles = 0;
        total_dispatch_zero_retire_cycles = 0;
        total_legacy_control_singletons = 0;
        total_legacy_muldiv_singletons = 0;
        total_legacy_to_dual_transitions = 0;
        total_dual_to_legacy_transitions = 0;
        total_legacy_pair_fallbacks = 0;
        total_legacy_prefer_fallbacks = 0;
        total_legacy_drain_wait_cycles = 0;
        total_dual_backend_wait_cycles = 0;
    end

    always @(posedge u_benchmark.clk) begin
        if (!u_benchmark.rst_n) begin
            perf_enable_d = 1'b0;
            window_index = 0;
            clear_window_counters();
        end else begin
            // Keep the testbench-only classification counters aligned with the
            // architectural performance counters.  Software may clear and
            // enable the first window after reset; launches before that clear
            // must not survive only in the testbench side of the identity.
            if (u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.csr_wen &&
                (u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.csr_waddr ==
                 `CSR_PERF_CTRL) &&
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.csr_wdata[1]) begin
                clear_window_counters();
            end
            if (u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable &&
                !(u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.csr_wen &&
                  (u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.csr_waddr ==
                   `CSR_PERF_CTRL))) begin
                if (u_benchmark.u_my_cpu.u_cpu_top.imem_en) begin
                    imem_requests += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.fetch_push_count != 0) begin
                    fetch_packets += 1;
                    fetch_uops +=
                        u_benchmark.u_my_cpu.u_cpu_top.fetch_push_count;
                    if (u_benchmark.u_my_cpu.u_cpu_top.fetch_push_count == 1) begin
                        fetch_single_packets += 1;
                    end
                end
                if (!u_benchmark.u_my_cpu.u_cpu_top.frontend_redirect &&
                    u_benchmark.u_my_cpu.u_cpu_top.bundle_push_ready &&
                    (u_benchmark.u_my_cpu.u_cpu_top.fetch_count == 0)) begin
                    fetch_empty_cycles += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_bundle_pop) begin
                    dual_launches += 1;
                    if (u_benchmark.u_my_cpu.u_cpu_top.dual_lane1_control_event) begin
                        lane1_control_launches += 1;
                    end
                    if (u_benchmark.u_my_cpu.u_cpu_top.dual_control0_simple_event) begin
                        control0_simple_launches += 1;
                    end
                    if (!u_benchmark.u_my_cpu.u_cpu_top.bundle_head[
                            `ISSUE_BUNDLE_WIDTH-1]) begin
                        if (u_benchmark.u_my_cpu.u_cpu_top.
                                u_dual_alu_pipeline.launch_control0) begin
                            control_singleton_launches += 1;
                        end else if (u_benchmark.u_my_cpu.u_cpu_top.
                                u_dual_alu_pipeline.launch_muldiv0) begin
                            muldiv_singleton_launches += 1;
                        end else begin
                            simple_singleton_launches += 1;
                        end
                    end else if (!u_benchmark.u_my_cpu.u_cpu_top.dual_lane1_control_event &&
                        !u_benchmark.u_my_cpu.u_cpu_top.dual_control0_simple_event &&
                        !u_benchmark.u_my_cpu.u_cpu_top.dual_lsu_pair_event &&
                        !u_benchmark.u_my_cpu.u_cpu_top.dual_muldiv_pair_event) begin
                        simple_pair_launches += 1;
                    end
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_branch_event &&
                    u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.idex_control0 &&
                    u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.idex_lane1_valid &&
                    (u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.branch_mispredict ||
                     u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.branch_exception_valid)) begin
                    control0_lane1_kills += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_retire_count == 1) begin
                    dual_retire1_cycles += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_retire_count == 2) begin
                    dual_retire2_cycles += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.retire_count == 0) begin
                    zero_retire_cycles += 1;
                    if (!u_benchmark.u_my_cpu.u_cpu_top.frontend_redirect &&
                        u_benchmark.u_my_cpu.u_cpu_top.bundle_head_valid &&
                        !u_benchmark.u_my_cpu.u_cpu_top.bundle_pop) begin
                        dispatch_zero_retire_cycles += 1;
                    end
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_bundle_pop &&
                    !u_benchmark.u_my_cpu.u_cpu_top.dual_mode) begin
                    legacy_to_dual_transitions += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.legacy_bundle_pop &&
                    u_benchmark.u_my_cpu.u_cpu_top.dual_mode) begin
                    dual_to_legacy_transitions += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.legacy_bundle_pop &&
                    u_benchmark.u_my_cpu.u_cpu_top.bundle_head[
                        `ISSUE_BUNDLE_WIDTH-1]) begin
                    legacy_pair_fallbacks += 1;
                    if (u_benchmark.u_my_cpu.u_cpu_top.prefer_legacy_dispatch) begin
                        legacy_prefer_fallbacks += 1;
                    end
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.legacy_bundle_pop &&
                    !u_benchmark.u_my_cpu.u_cpu_top.bundle_head[
                        `ISSUE_BUNDLE_WIDTH-1] &&
                    u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                        launch_control0) begin
                    legacy_control_singletons += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.legacy_bundle_pop &&
                    !u_benchmark.u_my_cpu.u_cpu_top.bundle_head[
                        `ISSUE_BUNDLE_WIDTH-1] &&
                    u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                        launch_muldiv0) begin
                    legacy_muldiv_singletons += 1;
                end
                if (!u_benchmark.u_my_cpu.u_cpu_top.frontend_redirect &&
                    u_benchmark.u_my_cpu.u_cpu_top.bundle_head_valid &&
                    u_benchmark.u_my_cpu.u_cpu_top.dual_candidate &&
                    !u_benchmark.u_my_cpu.u_cpu_top.legacy_domain_idle &&
                    !u_benchmark.u_my_cpu.u_cpu_top.legacy_bundle_pop) begin
                    legacy_drain_wait_cycles += 1;
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_bundle_valid &&
                    !u_benchmark.u_my_cpu.u_cpu_top.dual_launch_ready) begin
                    dual_backend_wait_cycles += 1;
                end
            end

            if (!u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable &&
                perf_enable_d) begin
                check_window_invariants();
                if (window_index == 0) begin
                    $display("A7_PROFILE_BOOT cycles=%0d instret=%0d",
                             u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_cycle,
                             u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_instret);
                end else begin
                    print_window(window_index - 1);
                    add_window_to_totals();
                end
                window_index += 1;
                clear_window_counters();
            end
            perf_enable_d =
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_enable;
        end
    end

    final begin
        $display("A7_PROFILE_TOTAL windows=%0d imem_req=%0d packets=%0d fetch_uops=%0d single_packet=%0d fetch_empty=%0d dual_launch=%0d simple_pair=%0d simple_single=%0d control_single=%0d muldiv_single=%0d control1_pair=%0d control0_pair=%0d control0_kill=%0d retire1=%0d retire2=%0d zero_retire=%0d dispatch_zero=%0d legacy_control_single=%0d legacy_muldiv_single=%0d legacy_to_dual=%0d dual_to_legacy=%0d legacy_pair=%0d legacy_prefer=%0d legacy_nonprefer=%0d wait_legacy=%0d wait_dual=%0d",
                 window_index - 1, total_imem_requests, total_fetch_packets,
                 total_fetch_uops, total_fetch_single_packets,
                 total_fetch_empty_cycles, total_dual_launches,
                 total_simple_pair_launches,
                 total_simple_singleton_launches,
                 total_control_singleton_launches,
                 total_muldiv_singleton_launches,
                 total_lane1_control_launches,
                 total_control0_simple_launches,
                 total_control0_lane1_kills,
                 total_dual_retire1_cycles, total_dual_retire2_cycles,
                 total_zero_retire_cycles,
                 total_dispatch_zero_retire_cycles,
                 total_legacy_control_singletons,
                 total_legacy_muldiv_singletons,
                 total_legacy_to_dual_transitions,
                 total_dual_to_legacy_transitions,
                 total_legacy_pair_fallbacks, total_legacy_prefer_fallbacks,
                 total_legacy_pair_fallbacks - total_legacy_prefer_fallbacks,
                 total_legacy_drain_wait_cycles,
                 total_dual_backend_wait_cycles);
        if (window_index != 10) begin
            $error("A7 profile expected boot plus 9 windows, got %0d closures",
                   window_index);
        end
    end

endmodule
