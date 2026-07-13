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
    longint unsigned domain_exit_prefer;
    longint unsigned domain_exit_non_lsu;
    longint unsigned domain_exit_lsu_gap;
    longint unsigned domain_exit_lsu_fast;
    longint unsigned domain_exit_lsu_follower;
    longint unsigned domain_exit_muldiv_follower;
    longint unsigned domain_exit_other_follower;
    longint unsigned raw_simple_simple;
    longint unsigned raw_simple_control;
    longint unsigned raw_control_simple;
    longint unsigned raw_simple_lsu;
    longint unsigned raw_lsu_simple;
    longint unsigned raw_simple_muldiv;
    longint unsigned raw_muldiv_simple;
    longint unsigned raw_unsupported;
    longint unsigned raw_waw_overlap;
    longint unsigned raw_rs1_match;
    longint unsigned raw_rs2_match;
    longint unsigned mul_launches;
    longint unsigned divrem_launches;
    longint unsigned mul_wait_cycles;
    longint unsigned divrem_wait_cycles;
    longint unsigned raw_only_simple_simple;
    longint unsigned raw_only_simple_control;
    longint unsigned raw_only_simple_lsu;
    longint unsigned raw_only_lsu_simple;
    longint unsigned raw_only_muldiv_simple;
    longint unsigned raw_only_other;

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
    longint unsigned total_domain_exit_prefer;
    longint unsigned total_domain_exit_non_lsu;
    longint unsigned total_domain_exit_lsu_gap;
    longint unsigned total_domain_exit_lsu_fast;
    longint unsigned total_domain_exit_lsu_follower;
    longint unsigned total_domain_exit_muldiv_follower;
    longint unsigned total_domain_exit_other_follower;
    longint unsigned total_raw_simple_simple;
    longint unsigned total_raw_simple_control;
    longint unsigned total_raw_control_simple;
    longint unsigned total_raw_simple_lsu;
    longint unsigned total_raw_lsu_simple;
    longint unsigned total_raw_simple_muldiv;
    longint unsigned total_raw_muldiv_simple;
    longint unsigned total_raw_unsupported;
    longint unsigned total_raw_waw_overlap;
    longint unsigned total_raw_rs1_match;
    longint unsigned total_raw_rs2_match;
    longint unsigned total_mul_launches;
    longint unsigned total_divrem_launches;
    longint unsigned total_mul_wait_cycles;
    longint unsigned total_divrem_wait_cycles;
    longint unsigned total_raw_only_simple_simple;
    longint unsigned total_raw_only_simple_control;
    longint unsigned total_raw_only_simple_lsu;
    longint unsigned total_raw_only_lsu_simple;
    longint unsigned total_raw_only_muldiv_simple;
    longint unsigned total_raw_only_other;

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
            domain_exit_prefer = 0;
            domain_exit_non_lsu = 0;
            domain_exit_lsu_gap = 0;
            domain_exit_lsu_fast = 0;
            domain_exit_lsu_follower = 0;
            domain_exit_muldiv_follower = 0;
            domain_exit_other_follower = 0;
            raw_simple_simple = 0;
            raw_simple_control = 0;
            raw_control_simple = 0;
            raw_simple_lsu = 0;
            raw_lsu_simple = 0;
            raw_simple_muldiv = 0;
            raw_muldiv_simple = 0;
            raw_unsupported = 0;
            raw_waw_overlap = 0;
            raw_rs1_match = 0;
            raw_rs2_match = 0;
            mul_launches = 0;
            divrem_launches = 0;
            mul_wait_cycles = 0;
            divrem_wait_cycles = 0;
            raw_only_simple_simple = 0;
            raw_only_simple_control = 0;
            raw_only_simple_lsu = 0;
            raw_only_lsu_simple = 0;
            raw_only_muldiv_simple = 0;
            raw_only_other = 0;
        end
    endtask

    task automatic check_window_invariants;
        longint unsigned class_launches;
        longint unsigned raw_class_total;
        longint unsigned raw_only_total;
        begin
            class_launches = simple_pair_launches +
                simple_singleton_launches +
                control_singleton_launches +
                muldiv_singleton_launches +
                lane1_control_launches +
                control0_simple_launches +
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_lsu_pair +
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_muldiv_pair;
            raw_class_total = raw_simple_simple + raw_simple_control +
                raw_control_simple + raw_simple_lsu + raw_lsu_simple +
                raw_simple_muldiv + raw_muldiv_simple + raw_unsupported;
            raw_only_total = raw_only_simple_simple +
                raw_only_simple_control + raw_only_simple_lsu +
                raw_only_lsu_simple + raw_only_muldiv_simple +
                raw_only_other;
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
            if (raw_class_total !=
                u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_issue_raw) begin
                $fatal(1,
                       "A7 RAW class identity failed: classified=%0d csr=%0d",
                       raw_class_total,
                       u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.perf_issue_raw);
            end
            if (raw_class_total != (raw_only_total + raw_waw_overlap)) begin
                $fatal(1,
                       "A7 RAW subset identity failed: total=%0d raw_only=%0d waw_overlap=%0d",
                       raw_class_total, raw_only_total, raw_waw_overlap);
            end
            if ((mul_launches + divrem_launches) !=
                (muldiv_singleton_launches +
                 u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.
                     perf_muldiv_pair)) begin
                $fatal(1,
                       "A7 MULDIV launch identity failed: classified=%0d singleton=%0d pair=%0d",
                       mul_launches + divrem_launches,
                       muldiv_singleton_launches,
                       u_benchmark.u_my_cpu.u_cpu_top.u_regfile_csr.
                           perf_muldiv_pair);
            end
            if (dual_to_legacy_transitions !=
                (domain_exit_prefer + domain_exit_non_lsu +
                 domain_exit_lsu_gap + domain_exit_lsu_fast +
                 domain_exit_lsu_follower +
                 domain_exit_muldiv_follower +
                 domain_exit_other_follower)) begin
                $fatal(1,
                       "A7 profile domain-exit identity failed: total=%0d classified=%0d",
                       dual_to_legacy_transitions,
                       domain_exit_prefer + domain_exit_non_lsu +
                       domain_exit_lsu_gap + domain_exit_lsu_fast +
                       domain_exit_lsu_follower +
                       domain_exit_muldiv_follower +
                       domain_exit_other_follower);
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
            $display("A7_DOMAIN_EXIT_WINDOW index=%0d name=%s total=%0d prefer=%0d non_lsu=%0d lsu_gap=%0d lsu_fast=%0d lsu_follower=%0d muldiv_follower=%0d other_follower=%0d",
                     report_index, perf_window_name(report_index),
                     dual_to_legacy_transitions, domain_exit_prefer,
                     domain_exit_non_lsu, domain_exit_lsu_gap,
                     domain_exit_lsu_fast, domain_exit_lsu_follower,
                     domain_exit_muldiv_follower,
                     domain_exit_other_follower);
            $display("A7_RAW_REJECT_WINDOW index=%0d name=%s total=%0d simple_simple=%0d simple_control=%0d control_simple=%0d simple_lsu=%0d lsu_simple=%0d simple_muldiv=%0d muldiv_simple=%0d unsupported=%0d waw_overlap=%0d rs1_match=%0d rs2_match=%0d",
                     report_index, perf_window_name(report_index),
                     raw_simple_simple + raw_simple_control +
                     raw_control_simple + raw_simple_lsu +
                     raw_lsu_simple + raw_simple_muldiv +
                     raw_muldiv_simple + raw_unsupported,
                     raw_simple_simple, raw_simple_control,
                     raw_control_simple, raw_simple_lsu, raw_lsu_simple,
                     raw_simple_muldiv, raw_muldiv_simple, raw_unsupported,
                     raw_waw_overlap, raw_rs1_match, raw_rs2_match);
            $display("A7_MULDIV_WINDOW index=%0d name=%s mul_launch=%0d divrem_launch=%0d mul_wait=%0d divrem_wait=%0d",
                     report_index, perf_window_name(report_index),
                     mul_launches, divrem_launches,
                     mul_wait_cycles, divrem_wait_cycles);
            $display("A7_RAW_ONLY_WINDOW index=%0d name=%s total=%0d simple_simple=%0d simple_control=%0d simple_lsu=%0d lsu_simple=%0d muldiv_simple=%0d other=%0d",
                     report_index, perf_window_name(report_index),
                     raw_only_simple_simple + raw_only_simple_control +
                     raw_only_simple_lsu + raw_only_lsu_simple +
                     raw_only_muldiv_simple + raw_only_other,
                     raw_only_simple_simple, raw_only_simple_control,
                     raw_only_simple_lsu, raw_only_lsu_simple,
                     raw_only_muldiv_simple, raw_only_other);
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
            total_domain_exit_prefer += domain_exit_prefer;
            total_domain_exit_non_lsu += domain_exit_non_lsu;
            total_domain_exit_lsu_gap += domain_exit_lsu_gap;
            total_domain_exit_lsu_fast += domain_exit_lsu_fast;
            total_domain_exit_lsu_follower += domain_exit_lsu_follower;
            total_domain_exit_muldiv_follower +=
                domain_exit_muldiv_follower;
            total_domain_exit_other_follower += domain_exit_other_follower;
            total_raw_simple_simple += raw_simple_simple;
            total_raw_simple_control += raw_simple_control;
            total_raw_control_simple += raw_control_simple;
            total_raw_simple_lsu += raw_simple_lsu;
            total_raw_lsu_simple += raw_lsu_simple;
            total_raw_simple_muldiv += raw_simple_muldiv;
            total_raw_muldiv_simple += raw_muldiv_simple;
            total_raw_unsupported += raw_unsupported;
            total_raw_waw_overlap += raw_waw_overlap;
            total_raw_rs1_match += raw_rs1_match;
            total_raw_rs2_match += raw_rs2_match;
            total_mul_launches += mul_launches;
            total_divrem_launches += divrem_launches;
            total_mul_wait_cycles += mul_wait_cycles;
            total_divrem_wait_cycles += divrem_wait_cycles;
            total_raw_only_simple_simple += raw_only_simple_simple;
            total_raw_only_simple_control += raw_only_simple_control;
            total_raw_only_simple_lsu += raw_only_simple_lsu;
            total_raw_only_lsu_simple += raw_only_lsu_simple;
            total_raw_only_muldiv_simple += raw_only_muldiv_simple;
            total_raw_only_other += raw_only_other;
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
        total_domain_exit_prefer = 0;
        total_domain_exit_non_lsu = 0;
        total_domain_exit_lsu_gap = 0;
        total_domain_exit_lsu_fast = 0;
        total_domain_exit_lsu_follower = 0;
        total_domain_exit_muldiv_follower = 0;
        total_domain_exit_other_follower = 0;
        total_raw_simple_simple = 0;
        total_raw_simple_control = 0;
        total_raw_control_simple = 0;
        total_raw_simple_lsu = 0;
        total_raw_lsu_simple = 0;
        total_raw_simple_muldiv = 0;
        total_raw_muldiv_simple = 0;
        total_raw_unsupported = 0;
        total_raw_waw_overlap = 0;
        total_raw_rs1_match = 0;
        total_raw_rs2_match = 0;
        total_mul_launches = 0;
        total_divrem_launches = 0;
        total_mul_wait_cycles = 0;
        total_divrem_wait_cycles = 0;
        total_raw_only_simple_simple = 0;
        total_raw_only_simple_control = 0;
        total_raw_only_simple_lsu = 0;
        total_raw_only_lsu_simple = 0;
        total_raw_only_muldiv_simple = 0;
        total_raw_only_other = 0;
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
                    if (u_benchmark.u_my_cpu.u_cpu_top.
                            prefer_legacy_dispatch) begin
                        domain_exit_prefer += 1;
                    end else if (!u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.lsu_candidate) begin
                        domain_exit_non_lsu += 1;
                    end else if (!u_benchmark.u_my_cpu.u_cpu_top.
                                     bundle_next_valid) begin
                        domain_exit_lsu_gap += 1;
                    end else if (u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.
                                     next_fast_continuation) begin
                        domain_exit_lsu_fast += 1;
                    end else if (u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.next_lsu0 ||
                                 u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.next_lsu1) begin
                        domain_exit_lsu_follower += 1;
                    end else if (u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.next_muldiv0 ||
                                 u_benchmark.u_my_cpu.u_cpu_top.
                                     u_bundle_dispatch.next_muldiv1) begin
                        domain_exit_muldiv_follower += 1;
                    end else begin
                        domain_exit_other_follower += 1;
                    end
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
                if (u_benchmark.u_my_cpu.u_cpu_top.issue_reject_raw) begin
                    case (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.
                              candidate_class)
                        `PAIR_SIMPLE_SIMPLE:  raw_simple_simple += 1;
                        `PAIR_SIMPLE_CONTROL: raw_simple_control += 1;
                        `PAIR_CONTROL_SIMPLE: raw_control_simple += 1;
                        `PAIR_SIMPLE_LSU:     raw_simple_lsu += 1;
                        `PAIR_LSU_SIMPLE:     raw_lsu_simple += 1;
                        `PAIR_SIMPLE_MULDIV:  raw_simple_muldiv += 1;
                        `PAIR_MULDIV_SIMPLE:  raw_muldiv_simple += 1;
                        default:              raw_unsupported += 1;
                    endcase
                    if (u_benchmark.u_my_cpu.u_cpu_top.
                            issue_reject_waw) begin
                        raw_waw_overlap += 1;
                    end else begin
                        case (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.
                                  candidate_class)
                            `PAIR_SIMPLE_SIMPLE:
                                raw_only_simple_simple += 1;
                            `PAIR_SIMPLE_CONTROL:
                                raw_only_simple_control += 1;
                            `PAIR_SIMPLE_LSU:
                                raw_only_simple_lsu += 1;
                            `PAIR_LSU_SIMPLE:
                                raw_only_lsu_simple += 1;
                            `PAIR_MULDIV_SIMPLE:
                                raw_only_muldiv_simple += 1;
                            default: raw_only_other += 1;
                        endcase
                    end
                    if (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.
                            uses_rs1_1 &&
                        (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.rs1_1 ==
                         u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.rd_0)) begin
                        raw_rs1_match += 1;
                    end
                    if (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.
                            uses_rs2_1 &&
                        (u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.rs2_1 ==
                         u_benchmark.u_my_cpu.u_cpu_top.u_issue_stage.rd_0)) begin
                        raw_rs2_match += 1;
                    end
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.dual_bundle_pop &&
                    (u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                         launch_muldiv0 ||
                     u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                         launch_muldiv1)) begin
                    if ((u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                             launch_muldiv0 &&
                         u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                             launch_inst0[14]) ||
                        (u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                             launch_muldiv1 &&
                         u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                             launch_inst1[14])) begin
                        divrem_launches += 1;
                    end else begin
                        mul_launches += 1;
                    end
                end
                if (u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                        idex_valid &&
                    u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                        idex_has_muldiv &&
                    !u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                         muldiv_done) begin
                    if (u_benchmark.u_my_cpu.u_cpu_top.u_dual_alu_pipeline.
                            muldiv_instruction[14]) begin
                        divrem_wait_cycles += 1;
                    end else begin
                        mul_wait_cycles += 1;
                    end
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
        $display("A7_DOMAIN_EXIT_TOTAL total=%0d prefer=%0d non_lsu=%0d lsu_gap=%0d lsu_fast=%0d lsu_follower=%0d muldiv_follower=%0d other_follower=%0d",
                 total_dual_to_legacy_transitions,
                 total_domain_exit_prefer, total_domain_exit_non_lsu,
                 total_domain_exit_lsu_gap, total_domain_exit_lsu_fast,
                 total_domain_exit_lsu_follower,
                 total_domain_exit_muldiv_follower,
                 total_domain_exit_other_follower);
        $display("A7_RAW_REJECT_TOTAL total=%0d simple_simple=%0d simple_control=%0d control_simple=%0d simple_lsu=%0d lsu_simple=%0d simple_muldiv=%0d muldiv_simple=%0d unsupported=%0d waw_overlap=%0d rs1_match=%0d rs2_match=%0d",
                 total_raw_simple_simple + total_raw_simple_control +
                 total_raw_control_simple + total_raw_simple_lsu +
                 total_raw_lsu_simple + total_raw_simple_muldiv +
                 total_raw_muldiv_simple + total_raw_unsupported,
                 total_raw_simple_simple, total_raw_simple_control,
                 total_raw_control_simple, total_raw_simple_lsu,
                 total_raw_lsu_simple, total_raw_simple_muldiv,
                 total_raw_muldiv_simple, total_raw_unsupported,
                 total_raw_waw_overlap, total_raw_rs1_match,
                 total_raw_rs2_match);
        $display("A7_MULDIV_TOTAL mul_launch=%0d divrem_launch=%0d mul_wait=%0d divrem_wait=%0d",
                 total_mul_launches, total_divrem_launches,
                 total_mul_wait_cycles, total_divrem_wait_cycles);
        $display("A7_RAW_ONLY_TOTAL total=%0d simple_simple=%0d simple_control=%0d simple_lsu=%0d lsu_simple=%0d muldiv_simple=%0d other=%0d",
                 total_raw_only_simple_simple +
                 total_raw_only_simple_control +
                 total_raw_only_simple_lsu + total_raw_only_lsu_simple +
                 total_raw_only_muldiv_simple + total_raw_only_other,
                 total_raw_only_simple_simple,
                 total_raw_only_simple_control,
                 total_raw_only_simple_lsu,
                 total_raw_only_lsu_simple,
                 total_raw_only_muldiv_simple,
                 total_raw_only_other);
        if (window_index != 10) begin
            $error("A7 profile expected boot plus 9 windows, got %0d closures",
                   window_index);
        end
    end

endmodule
