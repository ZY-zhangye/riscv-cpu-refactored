`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_mul_special;
    logic clk;
    logic rst_n;
    logic op_valid;
    logic op_accept;
    logic op_kill;
    logic is_mul;
    logic is_multicycle;
    logic [31:0] mul_src1;
    logic [31:0] mul_src2;
    logic [3:0] mul_op;
    logic src1_signed;
    logic src2_signed;
    logic [31:0] mul_result;
    logic mul_stall;
    int failures;

    mul dut (
        .clk(clk),
        .rst_n(rst_n),
        .op_valid(op_valid),
        .op_accept(op_accept),
        .op_kill(op_kill),
        .is_mul(is_mul),
        .is_multicycle(is_multicycle),
        .mul_src1(mul_src1),
        .mul_src2(mul_src2),
        .mul_op(mul_op),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .mul_result(mul_result),
        .mul_stall(mul_stall)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_special(
        input string name,
        input logic [3:0] op,
        input logic signed_inputs,
        input logic [31:0] dividend,
        input logic [31:0] divisor,
        input logic [31:0] expected,
        input integer hold_cycles
    );
        integer guard;
        integer i;
        begin
            @(negedge clk);
            op_valid = 1'b1;
            op_accept = 1'b0;
            is_mul = 1'b1;
            is_multicycle = 1'b1;
            mul_op = op;
            src1_signed = signed_inputs;
            src2_signed = signed_inputs;
            mul_src1 = dividend;
            mul_src2 = divisor;
            guard = 0;
            do begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end while (mul_stall && (guard < 40));

            if (mul_stall || (mul_result !== expected)) begin
                failures++;
                $display("MUL_DIV_FAIL %s stall=%0b result=%08x expected=%08x cycles=%0d",
                         name, mul_stall, mul_result, expected, guard);
            end

            for (i = 0; i < hold_cycles; i = i + 1) begin
                @(posedge clk);
                #1;
                if (mul_stall || (mul_result !== expected)) begin
                    failures++;
                    $display("MUL_DIV_HOLD_FAIL %s hold=%0d stall=%0b result=%08x expected=%08x",
                             name, i, mul_stall, mul_result, expected);
                end
            end

            @(negedge clk);
            op_accept = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            op_accept = 1'b0;
            op_valid = 1'b0;
            is_mul = 1'b0;
            mul_op = 4'b0;
            @(posedge clk);
        end
    endtask

    task automatic cancel_inflight;
        begin
            @(negedge clk);
            op_valid = 1'b1;
            is_mul = 1'b1;
            is_multicycle = 1'b1;
            mul_op = 4'b0010;
            src1_signed = 1'b0;
            src2_signed = 1'b0;
            mul_src1 = 32'hffff_ffff;
            mul_src2 = 32'd7;
            repeat (4) @(posedge clk);
            @(negedge clk);
            op_kill = 1'b1;
            op_valid = 1'b0;
            is_mul = 1'b0;
            @(posedge clk);
            #1;
            if (mul_stall) begin
                failures++;
                $display("MUL_DIV_CANCEL_FAIL stall remained asserted");
            end
            @(negedge clk);
            op_kill = 1'b0;
            mul_op = 4'b0;
        end
    endtask

    initial begin
        failures = 0;
        rst_n = 1'b0;
        op_valid = 1'b0;
        op_accept = 1'b0;
        op_kill = 1'b0;
        is_mul = 1'b0;
        is_multicycle = 1'b1;
        mul_src1 = 32'b0;
        mul_src2 = 32'b0;
        mul_op = 4'b0;
        src1_signed = 1'b0;
        src2_signed = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        check_special("div by zero",  4'b0010, 1'b1,
                      32'hffff_fffb, 32'b0, 32'hffff_ffff, 2);
        check_special("divu by zero", 4'b0010, 1'b0,
                      32'h8000_0001, 32'b0, 32'hffff_ffff, 0);
        check_special("rem by zero",  4'b0001, 1'b1,
                      32'hffff_fffb, 32'b0, 32'hffff_fffb, 0);
        check_special("remu by zero", 4'b0001, 1'b0,
                      32'h8000_0001, 32'b0, 32'h8000_0001, 0);
        check_special("div overflow", 4'b0010, 1'b1,
                      32'h8000_0000, 32'hffff_ffff, 32'h8000_0000, 0);
        check_special("rem overflow", 4'b0001, 1'b1,
                      32'h8000_0000, 32'hffff_ffff, 32'b0, 0);
        check_special("signed normal div", 4'b0010, 1'b1,
                      32'hffff_fffb, 32'd3, 32'hffff_ffff, 2);
        check_special("signed normal rem", 4'b0001, 1'b1,
                      32'hffff_fffb, 32'd3, 32'hffff_fffe, 0);
        check_special("unsigned normal div", 4'b0010, 1'b0,
                      32'hffff_ffff, 32'd3, 32'h5555_5555, 0);
        cancel_inflight();
        check_special("post cancel div", 4'b0010, 1'b0,
                      32'd100, 32'd7, 32'd14, 0);

        if (failures == 0) begin
            $display("MUL_SPECIAL_TEST_PASSED");
        end else begin
            $fatal(1, "MUL_SPECIAL_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end
endmodule
