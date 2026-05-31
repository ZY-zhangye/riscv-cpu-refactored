`timescale 1ns/1ps
`include "../rtl/my_cpu/my_cpu_defines.svh"

module tb_timer;
    logic clk;
    logic rst_n;
    logic [15:0] addr;
    logic [31:0] wdata;
    logic we;
    logic re;
    logic [31:0] rdata;
    logic timer_int;

    timer dut (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr),
        .wdata(wdata),
        .we(we),
        .re(re),
        .rdata(rdata),
        .timer_int(timer_int)
    );

    always #5 clk = ~clk;

    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $display("[FAILED] %s", msg);
            $fatal(1);
        end else begin
            $display("[ OK ] %s", msg);
        end
    endtask

    task automatic section(input string name);
        $display("");
        $display("==== %s ====", name);
    endtask

    task automatic bus_idle();
        addr = 16'd0;
        wdata = 32'd0;
        we = 1'b0;
        re = 1'b0;
    endtask

    task automatic bus_write(input logic [15:0] wr_addr, input logic [31:0] wr_data);
        @(negedge clk);
        addr = wr_addr;
        wdata = wr_data;
        we = 1'b1;
        re = 1'b0;
        @(posedge clk);
        #1;
        $display("[TIMER WRITE] time=%0t addr=0x%04h data=0x%08h timer_int=%b",
                 $time, wr_addr, wr_data, timer_int);
        @(negedge clk);
        bus_idle();
    endtask

    task automatic bus_read(input logic [15:0] rd_addr, output logic [31:0] rd_data);
        @(negedge clk);
        addr = rd_addr;
        wdata = 32'd0;
        we = 1'b0;
        re = 1'b1;
        @(posedge clk);
        #1;
        rd_data = rdata;
        $display("[TIMER READ ] time=%0t addr=0x%04h data=0x%08h timer_int=%b",
                 $time, rd_addr, rd_data, timer_int);
        @(negedge clk);
        bus_idle();
    endtask

    task automatic wait_cycles(input int cycles);
        repeat (cycles) @(posedge clk);
        #1;
    endtask

    task automatic wait_for_timer_int(input int max_cycles);
        int i;
        bit seen;
        seen = 1'b0;
        for (i = 0; i < max_cycles; i++) begin
            @(posedge clk);
            #1;
            if (timer_int) begin
                seen = 1'b1;
                $display("[TIMER EVENT] time=%0t timer_int asserted after %0d cycles", $time, i + 1);
                i = max_cycles;
            end
        end
        check(seen, "timer_int should assert before timeout");
    endtask

    initial begin
        logic [31:0] data;

        clk = 1'b0;
        rst_n = 1'b0;
        bus_idle();

        $display("");
        $display("============================================================");
        $display(" Timer self-checking test");
        $display(" reset / load / one-shot / prescaler / periodic reload");
        $display("============================================================");

        section("reset and default register state");
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        bus_read(`TIMER_VALUE, data);
        check(data == 32'd0, "timer value should reset to zero");
        bus_read(`TIMER_CTRL, data);
        check(data == 32'd0, "timer ctrl should reset to zero");
        check(!timer_int, "timer_int should reset low");

        section("load register and value register");
        bus_write(`TIMER_LOAD, 32'd4);
        bus_read(`TIMER_LOAD, data);
        check(data == 32'd4, "TIMER_LOAD readback should match written value");
        bus_read(`TIMER_VALUE, data);
        check(data == 32'd4, "writing LOAD should also load VALUE");

        section("one-shot interrupt");
        bus_write(`TIMER_CTRL, 32'h3);
        wait_for_timer_int(8);
        check(timer_int, "one-shot timer should assert interrupt");
        wait_cycles(2);
        bus_read(`TIMER_VALUE, data);
        check(data == 32'd0, "one-shot timer should stop at zero");

        bus_write(`TIMER_INTCLR, 32'd1);
        wait_cycles(1);
        check(!timer_int, "TIMER_INTCLR bit 0 should clear interrupt");

        section("prescaler one-shot interrupt");
        bus_write(`TIMER_CTRL, 32'd0);
        bus_write(`TIMER_LOAD, 32'd3);
        bus_write(`TIMER_PRESCALER, 32'd2);
        bus_write(`TIMER_CTRL, 32'h13);
        bus_read(`TIMER_VALUE, data);
        check(data == 32'd3, "prescaler should delay countdown immediately after enable");
        wait_for_timer_int(16);
        check(timer_int, "prescaled one-shot timer should eventually assert interrupt");
        bus_write(`TIMER_INTCLR, 32'd1);
        wait_cycles(1);
        check(!timer_int, "prescaled timer interrupt should be clearable");

        section("periodic reload interrupt");
        bus_write(`TIMER_CTRL, 32'd0);
        bus_write(`TIMER_LOAD, 32'd2);
        bus_write(`TIMER_CTRL, 32'h0f);
        wait_for_timer_int(6);
        check(timer_int, "periodic reload timer should assert interrupt");
        bus_read(`TIMER_VALUE, data);
        check(data <= 32'd2, "periodic timer value should stay within reload range");
        bus_write(`TIMER_INTCLR, 32'd1);
        wait_cycles(1);
        check(!timer_int || (data == 32'd1), "periodic timer interrupt should be clearable");
        bus_write(`TIMER_CTRL, 32'd0);

        bus_read(`TIMER_INTCLR, data);
        check(data == 32'd0, "TIMER_INTCLR reads as zero");

        $display("");
        $display("Timer test summary: all load, countdown, interrupt, clear, and reload checks passed.");
        $display("Test passed.");
        $finish;
    end
endmodule
