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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic fail(input string msg);
        begin
            $display("[FAILED] %s", msg);
            $fatal(1);
        end
    endtask

    task automatic check(input bit cond, input string msg);
        begin
            if (!cond) begin
                fail(msg);
            end
        end
    endtask

    task automatic bus_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            plic_sel = 1'b1;
            plic_we = 1'b1;
            plic_re = 1'b0;
            plic_addr = addr;
            plic_wdata = data;
            @(negedge clk);
            plic_sel = 1'b0;
            plic_we = 1'b0;
            plic_addr = 32'b0;
            plic_wdata = 32'b0;
        end
    endtask

    task automatic bus_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            plic_sel = 1'b1;
            plic_we = 1'b0;
            plic_re = 1'b1;
            plic_addr = addr;
            @(negedge clk);
            data = plic_rdata;
            plic_sel = 1'b0;
            plic_re = 1'b0;
            plic_addr = 32'b0;
        end
    endtask

    task automatic claim_expect(input logic [`ID_WIDTH-1:0] exp_id);
        logic [31:0] data;
        begin
            bus_read(`PLIC_CLAIM_BASE_ADDR, data);
            check(data[`ID_WIDTH-1:0] == exp_id,
                  $sformatf("claim id mismatch, expect %0d got %0d", exp_id, data[`ID_WIDTH-1:0]));
        end
    endtask

    task automatic complete_id(input logic [`ID_WIDTH-1:0] id);
        begin
            bus_write(`PLIC_CLAIM_BASE_ADDR, {{(32-`ID_WIDTH){1'b0}}, id});
        end
    endtask

    localparam logic [31:0] PRIO_1  = `PLIC_PRIORITY_BASE_ADDR + 32'd4;
    localparam logic [31:0] PRIO_2  = `PLIC_PRIORITY_BASE_ADDR + 32'd8;
    localparam logic [31:0] PRIO_16 = `PLIC_PRIORITY_BASE_ADDR + 32'd64;

    logic [31:0] rdata;

    initial begin
        rst_n = 1'b0;
        peripheral_interrupts = '0;
        plic_sel = 1'b0;
        plic_we = 1'b0;
        plic_re = 1'b0;
        plic_addr = 32'b0;
        plic_wdata = 32'b0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        bus_read(`PLIC_PENDING_BASE_ADDR, rdata);
        check(rdata == 32'b0, "pending should be zero after reset");
        bus_read(`PLIC_ENABLE_BASE_ADDR, rdata);
        check(rdata == 32'b0, "enable should be zero after reset");
        check(!plic_irq, "irq should be low after reset");

        bus_write(PRIO_1, 32'd2);
        bus_write(PRIO_2, 32'd5);
        bus_write(PRIO_16, 32'd9);
        bus_read(PRIO_16, rdata);
        check(rdata == 32'd1, "priority should be masked to PRIORITY_WIDTH bits");

        bus_write(`PLIC_ENABLE_BASE_ADDR, 32'h0001_0007);
        bus_read(`PLIC_ENABLE_BASE_ADDR, rdata);
        check(rdata[0] == 1'b0, "interrupt 0 enable must stay zero");
        check(rdata[1] && rdata[2] && rdata[16], "interrupt 1,2,16 should be enabled");

        peripheral_interrupts[1] = 1'b1;
        peripheral_interrupts[2] = 1'b1;
        peripheral_interrupts[16] = 1'b1;
        repeat (2) @(negedge clk);
        check(plic_irq, "irq should assert when enabled pending interrupt exists");

        claim_expect(5'd2);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata[2], "interrupt 2 should enter in_service after claim");

        claim_expect(5'd1);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata[1], "interrupt 1 should enter in_service after claim");

        claim_expect(5'd16);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata[16], "interrupt 16 should enter in_service after claim");

        peripheral_interrupts[1] = 1'b0;
        peripheral_interrupts[2] = 1'b0;
        peripheral_interrupts[16] = 1'b0;
        complete_id(5'd16);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(!rdata[16], "interrupt 16 should be released by full-width complete id");

        complete_id(5'd1);
        complete_id(5'd2);
        bus_read(`PLIC_IN_SERVICE_BASE_ADDR, rdata);
        check(rdata == 32'b0, "all in_service bits should be clear after complete");
        check(!plic_irq, "irq should deassert after pending and in_service are clear");

        bus_write(`PLIC_THRESHOLD_BASE_ADDR, 32'd4);
        peripheral_interrupts[1] = 1'b1;
        repeat (2) @(negedge clk);
        check(!plic_irq, "priority 2 interrupt should be masked by threshold 4");
        peripheral_interrupts[2] = 1'b1;
        repeat (2) @(negedge clk);
        check(plic_irq, "priority 5 interrupt should pass threshold 4");
        claim_expect(5'd2);
        peripheral_interrupts[1] = 1'b0;
        peripheral_interrupts[2] = 1'b0;
        complete_id(5'd2);

        bus_read(`PLIC_CLAIM_BASE_ADDR, rdata);
        check(rdata == 32'd0, "claim should return zero when no interrupt is claimable");

        $display("Test passed.");
        $finish;
    end

endmodule
