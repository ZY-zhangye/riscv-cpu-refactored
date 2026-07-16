`timescale 1ps / 1ps

module tb_soc_irom_v2;

    import "DPI-C" context task tb_wait_for_enter();

    logic i_sys_clk_p;
    logic i_sys_clk_n;
    logic i_uart_rx;
    logic o_uart_tx;
    logic [31:0] virtual_led;
    logic [39:0] virtual_seg;
    logic [31:0] virtual_seg_value;

    logic monitor_armed;
    logic auto_continue;
    logic [31:0] last_led;
    logic [31:0] last_seg;
    logic final_reported;
    logic finish_on_final;
    longint unsigned cpu_cycles;
    longint unsigned stack_hits;
    longint unsigned stack_forwards;
    longint unsigned load_use_stalls;
    integer max_sim_ms;
    integer elapsed_ms;

    top dut (
        .i_sys_clk_p(i_sys_clk_p),
        .i_sys_clk_n(i_sys_clk_n),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx),
        .virtual_led(virtual_led),
        .virtual_seg(virtual_seg),
        .virtual_seg_value(virtual_seg_value)
    );

    initial begin
        i_sys_clk_p = 1'b0;
        i_sys_clk_n = 1'b1;
        i_uart_rx = 1'b1;
        forever begin
            #2500;
            i_sys_clk_p = ~i_sys_clk_p;
            i_sys_clk_n = ~i_sys_clk_n;
        end
    end

    initial begin
        monitor_armed = 1'b0;
        auto_continue = $test$plusargs("AUTO_CONTINUE");
        cpu_cycles = 0;
        final_reported = 1'b0;
        finish_on_final = $test$plusargs("FINISH_ON_FINAL");
        stack_hits = 0;
        stack_forwards = 0;
        load_use_stalls = 0;
        max_sim_ms = 0;
        elapsed_ms = 0;
        void'($value$plusargs("MAX_SIM_MS=%d", max_sim_ms));

        wait (dut.w_clk_rst === 1'b1);
        repeat (4) @(posedge dut.cpu_clk);
        last_led = virtual_led;
        last_seg = virtual_seg_value;
        monitor_armed = 1'b1;
        $display("[SOC] monitor armed at %0.6f ms: SEG=%08h LED=%08h",
                 $realtime / 1ms, virtual_seg_value, virtual_led);
    end

    always @(posedge dut.cpu_clk) begin
        if (dut.w_clk_rst) begin
            cpu_cycles <= cpu_cycles + 1;
            if (dut.my_cpu.u_cpu_top.exe_stack_lw_hit) begin
                stack_hits <= stack_hits + 1;
            end
            if (dut.my_cpu.u_cpu_top.u_exe_stage.es_to_ms_valid &&
                dut.my_cpu.u_cpu_top.ms_allowin &&
                (dut.my_cpu.u_cpu_top.u_exe_stage.stack_src1_fwd ||
                 dut.my_cpu.u_cpu_top.u_exe_stage.stack_src2_fwd)) begin
                stack_forwards <= stack_forwards + 1;
            end
            if (dut.my_cpu.u_cpu_top.u_id_stage.load_use_hazard) begin
                load_use_stalls <= load_use_stalls + 1;
            end
        end

        if (monitor_armed &&
            ((virtual_seg_value !== last_seg) || (virtual_led !== last_led))) begin
            $display("[CHANGE] time=%0.6f ms cycle=%0d SEG %08h -> %08h LED %08h -> %08h CNT=%0d",
                     $realtime / 1ms, cpu_cycles,
                     last_seg, virtual_seg_value,
                     last_led, virtual_led,
                     dut.my_cpu.u_perip_bridge.cnt_rdata);
            last_seg = virtual_seg_value;
            last_led = virtual_led;
            if (!auto_continue) begin
                tb_wait_for_enter();
            end
        end

        if (monitor_armed && !final_reported &&
            (virtual_led == 32'h078b_7323)) begin
            final_reported = 1'b1;
            $display("[SOC] expected final LED value reached at %0.6f ms: SEG=%08h LED=%08h CNT=%0d STACK_HITS=%0d STACK_FORWARDS=%0d LOAD_USE_STALLS=%0d CPU_CYCLES=%0d",
                     $realtime / 1ms, virtual_seg_value, virtual_led,
                     dut.my_cpu.u_perip_bridge.cnt_rdata,
                     stack_hits, stack_forwards, load_use_stalls, cpu_cycles);
            if (finish_on_final) begin
                $finish;
            end
        end
    end

    initial begin
        wait (dut.w_clk_rst === 1'b1);
        forever begin
            #1ms;
            elapsed_ms = elapsed_ms + 1;
            if ((elapsed_ms % 10) == 0) begin
                $display("[10MS] time=%0.3f ms cycle=%0d SEG=%08h LED=%08h CNT=%0d STACK_HITS=%0d LOAD_USE_STALLS=%0d",
                         $realtime / 1ms, cpu_cycles,
                         virtual_seg_value, virtual_led,
                         dut.my_cpu.u_perip_bridge.cnt_rdata,
                         stack_hits, load_use_stalls);
            end
            if ((max_sim_ms > 0) && (elapsed_ms >= max_sim_ms)) begin
                $display("[SOC] MAX_SIM_MS reached: %0d ms SEG=%08h LED=%08h CNT=%0d",
                         max_sim_ms, virtual_seg_value, virtual_led,
                         dut.my_cpu.u_perip_bridge.cnt_rdata);
                $finish;
            end
        end
    end

endmodule
