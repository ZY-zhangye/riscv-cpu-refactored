`timescale 1ns/1ps
`include "../rtl/my_cpu/my_cpu_defines.svh"

module tb_UART;
    localparam int MAX_WAIT_CYCLES = 400;

    logic clk;
    logic rst_n;
    logic clk_uart;
    logic [15:0] addr;
    logic [31:0] wdata;
    logic we;
    logic re;
    logic [31:0] rdata;
    logic tx;
    logic rx;
    logic tx_int;
    logic rx_int;
    logic loopback_en;

    UART dut (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .addr(addr),
        .wdata(wdata),
        .we(we),
        .re(re),
        .rdata(rdata),
        .tx(tx),
        .rx(rx),
        .tx_int(tx_int),
        .rx_int(rx_int)
    );

    always #5 clk = ~clk;

    assign rx = loopback_en ? tx : 1'b1;

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
        $display("[UART WRITE] time=%0t addr=0x%04h data=0x%08h", $time, wr_addr, wr_data);
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
        $display("[UART READ ] time=%0t addr=0x%04h data=0x%08h tx=%b rx_int=%b tx_int=%b",
                 $time, rd_addr, rd_data, tx, rx_int, tx_int);
        @(negedge clk);
        bus_idle();
    endtask

    task automatic wait_cycles(input int cycles);
        repeat (cycles) @(posedge clk);
        #1;
    endtask

    task automatic wait_for_rx_int();
        int i;
        bit seen;
        seen = 1'b0;
        for (i = 0; i < MAX_WAIT_CYCLES; i++) begin
            @(posedge clk);
            #1;
            if (rx_int) begin
                seen = 1'b1;
                $display("[UART EVENT] time=%0t rx_int asserted after %0d cycles", $time, i + 1);
                i = MAX_WAIT_CYCLES;
            end
        end
        check(seen, "loopback byte should raise rx_int");
    endtask

    initial begin
        logic [31:0] status;
        logic [31:0] data;

        clk = 1'b0;
        rst_n = 1'b0;
        clk_uart = 1'b0;
        loopback_en = 1'b0;
        bus_idle();

        $display("");
        $display("============================================================");
        $display(" UART self-checking test");
        $display(" reset / FIFO / overflow / soft reset / loopback interrupt");
        $display("============================================================");

        section("reset and disabled write behavior");
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        bus_read(`UART_RT_STATUS, status);
        check(status[0], "TX should be empty after reset");
        check(!status[5], "overflow should be clear after reset");
        check(tx == 1'b1, "TX line should idle high after reset");

        bus_write(`UART_RT_DATA, 32'h55);
        bus_read(`UART_RT_STATUS, status);
        check(!status[5], "writing DATA while UART is disabled must not set overflow");

        section("TX FIFO full and overflow flag");
        bus_write(`UART_RT_CTRL, 32'h4);
        repeat (2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            bus_write(`UART_RT_DATA, i[7:0]);
        end
        wait_cycles(2);
        bus_read(`UART_RT_STATUS, status);
        check(status[2], "TX FIFO should report full after 8 writes without tx ticks");

        bus_write(`UART_RT_DATA, 32'hff);
        bus_read(`UART_RT_STATUS, status);
        check(status[5], "ninth TX write should set overflow");

        bus_write(`UART_RT_STATUS, 32'h20);
        bus_read(`UART_RT_STATUS, status);
        check(!status[5], "writing STATUS bit 5 should clear overflow");

        section("soft reset");
        bus_write(`UART_RT_CTRL, 32'h8);
        wait_cycles(2);
        bus_read(`UART_RT_STATUS, status);
        check(status[0] && !status[2], "soft reset should empty TX FIFO");
        bus_read(`UART_RT_CTRL, data);
        check(!data[3], "UART reset bit should be self-clearing");

        section("baud mode loopback and RX interrupt");
        loopback_en = 1'b1;
        bus_write(`UART_RT_BAUD, 32'd4);
        bus_write(`UART_RT_CTRL, 32'h17);
        wait_cycles(2);
        check(tx_int, "TX interrupt should assert when enabled and idle");

        bus_write(`UART_RT_DATA, 32'ha5);
        wait_for_rx_int();
        bus_read(`UART_RT_STATUS, status);
        check(status[1] && status[7], "RX_READY and RX_INT should be visible after loopback byte");
        bus_read(`UART_RT_DATA, data);
        check(data[7:0] == 8'ha5, "loopback read data should match transmitted byte");
        wait_cycles(2);
        bus_read(`UART_RT_STATUS, status);
        check(!status[1], "reading DATA should pop RX FIFO");

        section("final soft reset state");
        bus_write(`UART_RT_CTRL, 32'h8);
        wait_cycles(2);
        bus_read(`UART_RT_STATUS, status);
        check(status[0] && !status[1] && !status[2] && !status[3], "soft reset should clear UART FIFOs");

        $display("");
        $display("UART test summary: all status flags, FIFO operations, and interrupt checks passed.");
        $display("Test passed.");
        $finish;
    end
endmodule
