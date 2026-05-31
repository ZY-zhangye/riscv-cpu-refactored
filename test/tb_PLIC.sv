`timescale 1ns/1ps
`include "../rtl/my_cpu/my_cpu_defines.svh"

module tb_PLIC;
    logic clk;
    logic rst_n;
    logic [`PLIC_NUM_INTERRUPTS-1:0] peripheral_interrupts;
    logic plic_irq;
    logic plic_sel;
    logic plic_we;
    logic plic_re;
    logic [31:0] plic_addr;
    logic [31:0] plic_wdata;
    logic [31:0] plic_rdata;

    PLIC dut (
        .clk(clk),
        .rst_n(rst_n),
        .peripheral_interrupts(peripheral_interrupts),
        .plic_irq(plic_irq),
        .plic_sel(plic_sel),
        .plic_we(plic_we),
        .plic_re(plic_re),
        .plic_addr(plic_addr),
        .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
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
        plic_sel = 1'b0;
        plic_we = 1'b0;
        plic_re = 1'b0;
        plic_addr = 32'd0;
        plic_wdata = 32'd0;
    endtask

    task automatic bus_write(input logic [31:0] addr, input logic [31:0] data);
        @(negedge clk);
        plic_sel = 1'b1;
        plic_we = 1'b1;
        plic_re = 1'b0;
        plic_addr = addr;
        plic_wdata = data;
        @(posedge clk);
        #1;
        $display("[PLIC WRITE] time=%0t addr=0x%08h data=0x%08h", $time, addr, data);
        @(negedge clk);
        bus_idle();
    endtask

    task automatic bus_read(input logic [31:0] addr, output logic [31:0] data);
        @(negedge clk);
        plic_sel = 1'b1;
        plic_we = 1'b0;
        plic_re = 1'b1;
        plic_addr = addr;
        plic_wdata = 32'd0;
        @(posedge clk);
        #1;
        data = plic_rdata;
        $display("[PLIC READ ] time=%0t addr=0x%08h data=0x%08h", $time, addr, data);
        @(negedge clk);
        bus_idle();
    endtask

    task automatic pulse_irq(input int unsigned id);
        check((id > 0) && (id < `PLIC_NUM_INTERRUPTS), "interrupt id is valid for pulse_irq");
        $display("[PLIC IRQ  ] time=%0t pulse peripheral_interrupts[%0d]", $time, id);
        @(negedge clk);
        peripheral_interrupts[id] = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        peripheral_interrupts[id] = 1'b0;
    endtask

    task automatic wait_registered_irq();
        repeat (3) @(posedge clk);
        #1;
    endtask

    localparam logic [31:0] PRIO_0  = `PLIC_PRIORITY_BASE_ADDR + 32'd0;
    localparam logic [31:0] PRIO_1  = `PLIC_PRIORITY_BASE_ADDR + 32'd4;
    localparam logic [31:0] PRIO_2  = `PLIC_PRIORITY_BASE_ADDR + 32'd8;
    localparam logic [31:0] PRIO_16 = `PLIC_PRIORITY_BASE_ADDR + 32'd64;

    initial begin
        logic [31:0] rdata;

        clk = 1'b0;
        rst_n = 1'b0;
        peripheral_interrupts = '0;
        bus_idle();

        $display("");
        $display("============================================================");
        $display(" PLIC self-checking test");
        $display(" priority / enable / threshold / claim / complete");
        $display("============================================================");

        section("reset and default register state");
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        bus_read(`PLIC_PENDING_BASE_ADDR, rdata);
        check(rdata == 32'd0, "pending should reset to zero");
        bus_read(`PLIC_ENABLE_BASE_ADDR, rdata);
        check(rdata == 32'd0, "enable should reset to zero");
        bus_read(`PLIC_THRESHOLD_BASE_ADDR, rdata);
        check(rdata == 32'd0, "threshold should reset to zero");
        check(!plic_irq, "plic_irq should be low after reset");

        section("priority register and enable bitmap");
        bus_write(PRIO_0, 32'd7);
        bus_read(PRIO_0, rdata);
        check(rdata == 32'd0, "priority of interrupt 0 must stay zero");

        bus_write(PRIO_1, 32'd2);
        bus_write(PRIO_2, 32'd5);
        bus_write(PRIO_16, 32'd3);
        bus_write(`PLIC_ENABLE_BASE_ADDR, 32'h0001_0007);
        bus_read(`PLIC_ENABLE_BASE_ADDR, rdata);
        check(rdata == 32'h0001_0006, "enable bit 0 must be forced low");

        section("priority arbitration and claim path");
        pulse_irq(1);
        pulse_irq(2);
        wait_registered_irq();
        check(plic_irq, "highest priority pending interrupt should assert plic_irq");

        bus_read(`PLIC_CLAIM_BASE_ADDR, rdata);
        check(rdata == 32'd2, "claim should return highest priority interrupt id 2");
        repeat (2) @(posedge clk);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata[2], "claim should move id 2 into in_service");

        wait_registered_irq();
        bus_read(`PLIC_CLAIM_BASE_ADDR, rdata);
        check(rdata == 32'd1, "claim should return next pending interrupt id 1");
        repeat (2) @(posedge clk);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata[2] && rdata[1], "ids 1 and 2 should both be in_service before complete");

        bus_write(`PLIC_CLAIM_BASE_ADDR, 32'd2);
        repeat (2) @(posedge clk);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(!rdata[2] && rdata[1], "complete should release only the completed interrupt id");

        bus_write(`PLIC_CLAIM_BASE_ADDR, 32'd1);
        repeat (3) @(posedge clk);
        check(!plic_irq, "plic_irq should deassert when no eligible interrupt remains");

        section("threshold mask and delayed claim");
        bus_write(`PLIC_THRESHOLD_BASE_ADDR, 32'd4);
        pulse_irq(16);
        wait_registered_irq();
        check(!plic_irq, "priority 3 should be masked by threshold 4");

        bus_write(`PLIC_THRESHOLD_BASE_ADDR, 32'd0);
        wait_registered_irq();
        check(plic_irq, "lowering threshold should expose pending id 16");
        bus_read(`PLIC_CLAIM_BASE_ADDR, rdata);
        check(rdata == 32'd16, "claim should return id 16 after threshold is lowered");
        bus_write(`PLIC_CLAIM_BASE_ADDR, 32'd16);
        repeat (3) @(posedge clk);
        check(!plic_irq, "complete id 16 should clear final irq");

        section("invalid address readback");
        bus_read(32'h8030_6000, rdata);
        check(rdata == 32'hDEAD_BEEF, "invalid PLIC read should return DEAD_BEEF");

        $display("");
        $display("PLIC test summary: all observable register and interrupt checks passed.");
        $display("Test passed.");
        $finish;
    end
endmodule
