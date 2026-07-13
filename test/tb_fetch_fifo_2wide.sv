`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_fetch_fifo_2wide;
    logic clk;
    logic rst_n;
    logic clear;
    logic [1:0] push_count;
    logic [`FETCH_UOP_WIDTH-1:0] push_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] push_uop1;
    logic [1:0] pop_count;
    logic [3:0] count;
    logic [3:0] free_count;
    logic peek_valid0;
    logic peek_valid1;
    logic [`FETCH_UOP_WIDTH-1:0] peek_uop0;
    logic [`FETCH_UOP_WIDTH-1:0] peek_uop1;

    fetch_fifo dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .push_count(push_count),
        .push_uop0(push_uop0),
        .push_uop1(push_uop1),
        .pop_count(pop_count),
        .count(count),
        .free_count(free_count),
        .peek_valid0(peek_valid0),
        .peek_valid1(peek_valid1),
        .peek_uop0(peek_uop0),
        .peek_uop1(peek_uop1)
    );

    function automatic logic [`FETCH_UOP_WIDTH-1:0] uop_id(input integer id);
        logic [`FETCH_UOP_WIDTH-1:0] value;
        begin
            value = '0;
            value[31:0] = id;
            uop_id = value;
        end
    endfunction

    always #5 clk = ~clk;

    task automatic drive_cycle(
        input logic [1:0] pushes,
        input integer id0,
        input integer id1,
        input logic [1:0] pops
    );
        begin
            @(negedge clk);
            push_count = pushes;
            push_uop0 = uop_id(id0);
            push_uop1 = uop_id(id1);
            pop_count = pops;
            @(posedge clk);
            @(negedge clk);
            push_count = 0;
            pop_count = 0;
        end
    endtask

    task automatic expect_head(
        input integer expected_count,
        input integer id0,
        input integer id1
    );
        begin
            if (count !== expected_count) begin
                $fatal(1, "count mismatch expected=%0d actual=%0d",
                       expected_count, count);
            end
            if (free_count !== (8 - expected_count)) begin
                $fatal(1, "free count mismatch count=%0d free=%0d", count, free_count);
            end
            if (expected_count > 0) begin
                if (!peek_valid0 || (peek_uop0 !== uop_id(id0))) begin
                    $fatal(1, "lane0 peek mismatch expected id=%0d", id0);
                end
            end
            if (expected_count > 1) begin
                if (!peek_valid1 || (peek_uop1 !== uop_id(id1))) begin
                    $fatal(1, "lane1 peek mismatch expected id=%0d", id1);
                end
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        clear = 0;
        push_count = 0;
        pop_count = 0;
        push_uop0 = '0;
        push_uop1 = '0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        drive_cycle(2, 1, 2, 0);
        expect_head(2, 1, 2);
        drive_cycle(0, 0, 0, 1);
        expect_head(1, 2, 0);
        drive_cycle(2, 3, 4, 1);
        expect_head(2, 3, 4);
        drive_cycle(0, 0, 0, 2);
        expect_head(0, 0, 0);

        // Fill, then simultaneously pop/push across the circular boundary.
        drive_cycle(2, 1, 2, 0);
        drive_cycle(2, 3, 4, 0);
        drive_cycle(2, 5, 6, 0);
        drive_cycle(2, 7, 8, 0);
        expect_head(8, 1, 2);
        drive_cycle(2, 9, 10, 2);
        expect_head(8, 3, 4);
        drive_cycle(0, 0, 0, 2);
        expect_head(6, 5, 6);
        drive_cycle(0, 0, 0, 2);
        expect_head(4, 7, 8);
        drive_cycle(0, 0, 0, 2);
        expect_head(2, 9, 10);

        @(negedge clk);
        clear = 1;
        @(posedge clk);
        @(negedge clk);
        clear = 0;
        expect_head(0, 0, 0);

        $display("FETCH FIFO 2WIDE TEST PASSED");
        $finish;
    end

endmodule
