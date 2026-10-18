`timescale 1ns / 1ps

module tb_board_divider;
    logic clk = 1'b0;
    always #5 clk = !clk;
    logic rst_n = 1'b0;

    logic divisor_valid = 1'b0;
    logic dividend_valid = 1'b0;
    logic [31:0] divisor_data = 32'd0;
    logic [31:0] dividend_data = 32'd0;
    wire divisor_ready, dividend_ready;
    wire output_valid;
    wire [63:0] output_data;
    divider u_divider (
        .aclk(clk), .aresetn(rst_n),
        .s_axis_divisor_tvalid(divisor_valid),
        .s_axis_divisor_tready(divisor_ready),
        .s_axis_divisor_tdata(divisor_data),
        .s_axis_dividend_tvalid(dividend_valid),
        .s_axis_dividend_tready(dividend_ready),
        .s_axis_dividend_tdata(dividend_data),
        .m_axis_dout_tvalid(output_valid),
        .m_axis_dout_tdata(output_data)
    );

    logic is_mul = 1'b0;
    logic [31:0] mul_a = 32'd0, mul_b = 32'd0;
    logic [3:0] mul_op = 4'd0;
    logic signed_a = 1'b0, signed_b = 1'b0;
    logic kill = 1'b0;
    wire [31:0] mul_result;
    wire mul_stall;
    mul u_mul (
        .clk(clk), .rst_n(rst_n), .is_mul(is_mul),
        .is_multicycle(1'b1), .mul_src1(mul_a), .mul_src2(mul_b),
        .mul_op(mul_op), .src1_signed(signed_a), .src2_signed(signed_b),
        .result_ready(1'b1), .kill(kill),
        .mul_result(mul_result), .mul_stall(mul_stall)
    );

    integer raw_checks = 0;
    integer mul_checks = 0;
    integer drained_responses = 0;
    logic [31:0] random_state = 32'h7020_cafe;

    function automatic [31:0] random_word(input logic [31:0] previous);
        logic [31:0] next;
        begin
            next = previous ^ (previous << 13);
            next = next ^ (next >> 17);
            random_word = next ^ (next << 5);
        end
    endfunction

    function automatic [31:0] expected_result(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic signed_op,
        input logic remainder_op
    );
        begin
            if (b == 0)
                expected_result = remainder_op ? a : 32'hffff_ffff;
            else if (signed_op && a == 32'h8000_0000 && b == 32'hffff_ffff)
                expected_result = remainder_op ? 32'd0 : 32'h8000_0000;
            else if (signed_op)
                expected_result = remainder_op ?
                    ($signed(a) % $signed(b)) : ($signed(a) / $signed(b));
            else
                expected_result = remainder_op ? (a % b) : (a / b);
        end
    endfunction

    task automatic check_raw(input logic [31:0] a, input logic [31:0] b);
        logic [63:0] expected;
        begin
            expected = {expected_result(a, b, 1'b0, 1'b1),
                        expected_result(a, b, 1'b0, 1'b0)};
            @(negedge clk);
            dividend_data = a;
            divisor_data = b;
            dividend_valid = 1'b1;
            divisor_valid = 1'b1;
            #1;
            if (!dividend_ready || !divisor_ready)
                $fatal(1, "raw divider not ready for a paired request");
            @(posedge clk); #1;
            if (output_valid || dividend_ready || divisor_ready)
                $fatal(1, "raw divider accepted request incorrectly");
            @(negedge clk);
            dividend_valid = 1'b0;
            divisor_valid = 1'b0;
            // Inputs may change after acceptance; the hardware must retain them.
            dividend_data = ~a;
            divisor_data = ~b;
            for (integer step = 1; step <= 32; step = step + 1) begin
                @(posedge clk); #1;
                if (output_valid != (step == 32))
                    $fatal(1, "raw latency a=%h b=%h step=%0d valid=%b", a, b, step, output_valid);
            end
            if (output_data !== expected)
                $fatal(1, "raw a=%h b=%h got=%h expected=%h", a, b, output_data, expected);
            @(posedge clk); #1;
            if (output_valid) $fatal(1, "raw response must last exactly one clock");
            raw_checks = raw_checks + 1;
        end
    endtask

    task automatic await_mul(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic signed_op,
        input logic remainder_op,
        input integer max_cycles
    );
        logic completed;
        logic [31:0] expected;
        begin
            completed = 1'b0;
            expected = expected_result(a, b, signed_op, remainder_op);
            for (integer cycles = 0; cycles < max_cycles && !completed; cycles = cycles + 1) begin
                @(posedge clk); #1;
                if (!mul_stall) begin
                    completed = 1'b1;
                    if (mul_result !== expected)
                        $fatal(1, "mul div/rem a=%h b=%h signed=%b rem=%b got=%h expected=%h",
                               a, b, signed_op, remainder_op, mul_result, expected);
                end
            end
            if (!completed) $fatal(1, "mul div/rem timeout a=%h b=%h", a, b);
            mul_checks = mul_checks + 1;
            @(negedge clk);
            is_mul = 1'b0;
            mul_op = 4'd0;
            @(posedge clk); #1;
        end
    endtask

    task automatic check_mul(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic signed_op,
        input logic remainder_op
    );
        begin
            @(negedge clk);
            mul_a = a;
            mul_b = b;
            signed_a = signed_op;
            signed_b = signed_op;
            mul_op = remainder_op ? 4'b0001 : 4'b0010;
            is_mul = 1'b1;
            await_mul(a, b, signed_op, remainder_op, 40);
        end
    endtask

    task automatic check_kill_drain(input integer elapsed_steps);
        integer responses_before;
        begin
            @(negedge clk);
            mul_a = 32'hffff_fffb;
            mul_b = 32'd17;
            signed_a = 1'b0;
            signed_b = 1'b0;
            mul_op = 4'b0010;
            is_mul = 1'b1;
            @(posedge clk); #1; // First paired request is accepted.
            repeat (elapsed_steps) begin @(posedge clk); #1; end
            responses_before = drained_responses;
            @(negedge clk);
            kill = 1'b1;
            is_mul = 1'b0;
            #1;
            if (mul_stall) $fatal(1, "kill must release execute stall immediately");
            @(posedge clk); #1;
            @(negedge clk);
            kill = 1'b0;
            // A new instruction arrives before the killed divider responds.
            // It must wait for the stale result to drain, then run normally.
            mul_a = 32'h8000_0013;
            mul_b = 32'd7;
            signed_a = 1'b1;
            signed_b = 1'b1;
            mul_op = 4'b0001;
            is_mul = 1'b1;
            await_mul(32'h8000_0013, 32'd7, 1'b1, 1'b1, 80);
            if (drained_responses != responses_before + 2)
                $fatal(1, "expected one stale and one new divider response after kill");
        end
    endtask

    always @(posedge clk)
        if (rst_n && u_mul.div_inst.m_axis_dout_tvalid)
            drained_responses = drained_responses + 1;

    initial begin
        logic [31:0] a, b;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Single-channel valid must neither accept nor produce a response.
        divisor_valid = 1'b1;
        divisor_data = 32'd3;
        repeat (3) begin
            @(posedge clk); #1;
            if (divisor_ready || output_valid) $fatal(1, "unpaired divisor accepted");
        end
        @(negedge clk);
        divisor_valid = 1'b0;
        dividend_valid = 1'b1;
        repeat (3) begin
            @(posedge clk); #1;
            if (dividend_ready || output_valid) $fatal(1, "unpaired dividend accepted");
        end
        @(negedge clk);
        dividend_valid = 1'b0;

        check_raw(0, 1);
        check_raw(1, 1);
        check_raw(32'hffff_ffff, 1);
        check_raw(32'hffff_ffff, 32'hffff_ffff);
        check_raw(32'hffff_fffe, 32'hffff_ffff);
        check_raw(32'hffff_ffff, 32'h8000_0000);
        check_raw(32'h8000_0000, 32'h7fff_ffff);
        check_raw(32'h8000_0000, 32'h8000_0001);
        check_raw(32'h1234_5678, 0);
        for (integer bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
            check_raw(32'hffff_ffff, 32'd1 << bit_index);
            check_raw(32'd1 << bit_index, 32'hffff_ffff);
        end
        for (integer sample = 0; sample < 1024; sample = sample + 1) begin
            random_state = random_word(random_state); a = random_state;
            random_state = random_word(random_state); b = random_state;
            check_raw(a, b);
        end

        // Reset in flight is asynchronous and must cancel the pending response.
        @(negedge clk);
        dividend_valid = 1'b1; divisor_valid = 1'b1;
        dividend_data = 32'hfeed_face; divisor_data = 32'd13;
        @(posedge clk); #1;
        @(negedge clk);
        dividend_valid = 1'b0; divisor_valid = 1'b0;
        repeat (5) @(posedge clk);
        #2 rst_n = 1'b0;
        #1;
        if (output_valid || output_data !== 64'd0)
            $fatal(1, "asynchronous reset failed to clear raw divider");
        @(negedge clk); rst_n = 1'b1;
        repeat (35) begin
            @(posedge clk); #1;
            if (output_valid) $fatal(1, "raw response survived reset");
        end
        check_raw(32'hdead_beef, 32'd31);

        for (integer signed_op = 0; signed_op < 2; signed_op = signed_op + 1) begin
            for (integer remainder_op = 0; remainder_op < 2; remainder_op = remainder_op + 1) begin
                check_mul(32'h8000_0000, 32'hffff_ffff, signed_op != 0, remainder_op != 0);
                check_mul(32'h8000_0000, 32'd0, signed_op != 0, remainder_op != 0);
                check_mul(32'd0, 32'd0, signed_op != 0, remainder_op != 0);
                check_mul(32'hffff_fff9, 32'd3, signed_op != 0, remainder_op != 0);
                check_mul(32'd7, 32'hffff_fffd, signed_op != 0, remainder_op != 0);
                check_mul(32'hffff_fff9, 32'hffff_fffd, signed_op != 0, remainder_op != 0);
                for (integer sample = 0; sample < 128; sample = sample + 1) begin
                    random_state = random_word(random_state); a = random_state;
                    random_state = random_word(random_state); b = random_state;
                    check_mul(a, b, signed_op != 0, remainder_op != 0);
                end
            end
        end

        check_kill_drain(0);
        check_kill_drain(7);
        check_kill_drain(30);

        // Reset also clears the existing mul controller and its in-flight unit.
        @(negedge clk);
        mul_a = 32'h1234_5678; mul_b = 32'd9;
        signed_a = 1'b0; signed_b = 1'b0;
        mul_op = 4'b0010; is_mul = 1'b1;
        repeat (5) @(posedge clk);
        #2 rst_n = 1'b0;
        is_mul = 1'b0; mul_op = 4'd0;
        #1;
        if (u_mul.div_inst.m_axis_dout_tvalid)
            $fatal(1, "integrated divider valid survived reset");
        @(negedge clk); rst_n = 1'b1;
        repeat (35) begin
            @(posedge clk); #1;
            if (u_mul.div_inst.m_axis_dout_tvalid)
                $fatal(1, "integrated divider emitted stale result after reset");
        end
        check_mul(32'h7654_3210, 32'd17, 1'b0, 1'b0);

        $display("BOARD_DIVIDER_PASS raw=%0d mul=%0d kill_drain=3 reset=2", raw_checks, mul_checks);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "board divider test watchdog expired");
    end
endmodule
