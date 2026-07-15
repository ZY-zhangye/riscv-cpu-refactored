`timescale 1ns/1ps

module tb_mul_pipeline #(
    parameter integer HIGH_PIPE_STAGES = 3
);

    logic clk;
    logic rst_n;
    logic start;
    logic result_ready;
    logic kill;
    logic [31:0] src1;
    logic [31:0] src2;
    logic src1_signed;
    logic src2_signed;
    logic high_result;
    logic busy;
    logic done;
    logic [31:0] result;

    mul_pipeline #(
        .HIGH_PIPE_STAGES(HIGH_PIPE_STAGES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .result_ready(result_ready),
        .kill(kill),
        .src1(src1),
        .src2(src2),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .high_result(high_result),
        .busy(busy),
        .done(done),
        .result(result)
    );

    always #5 clk = ~clk;

    function automatic logic [63:0] expected_product(
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input logic lhs_signed,
        input logic rhs_signed
    );
        logic signed [63:0] lhs_ext;
        logic signed [63:0] rhs_ext;
        begin
            lhs_ext = lhs_signed ? {{32{lhs[31]}}, lhs} : {32'b0, lhs};
            rhs_ext = rhs_signed ? {{32{rhs[31]}}, rhs} : {32'b0, rhs};
            expected_product = lhs_ext * rhs_ext;
        end
    endfunction

    task automatic run_case(
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input logic lhs_signed,
        input logic rhs_signed,
        input logic want_high
    );
        logic [63:0] expected;
        integer timeout;
        integer expected_latency;
        begin
            expected = expected_product(lhs, rhs, lhs_signed, rhs_signed);
            while (busy) @(posedge clk);

            src1 <= lhs;
            src2 <= rhs;
            src1_signed <= lhs_signed;
            src2_signed <= rhs_signed;
            high_result <= want_high;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            timeout = 0;
            while (!done && timeout < 12) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!done) begin
                $fatal(1, "multiplier timeout lhs=%h rhs=%h", lhs, rhs);
            end
            expected_latency = want_high ? HIGH_PIPE_STAGES : 2;
            if (timeout != expected_latency) begin
                $fatal(1, "unexpected multiplier latency high=%0d expected=%0d actual=%0d",
                       want_high, expected_latency, timeout);
            end
            if ((!want_high && (result !== expected[31:0])) ||
                (want_high && (result !== expected[63:32]))) begin
                $fatal(1, "product mismatch lhs=%h rhs=%h signed=%0d/%0d expected=%h actual=%h",
                       lhs, rhs, lhs_signed, rhs_signed, expected, result);
            end
            @(posedge clk);
            @(negedge clk);
            if (busy || done) begin
                $fatal(1, "completed result was not consumed when ready");
            end
        end
    endtask

    task automatic run_kill_case;
        integer check_cycles;
        begin
            while (busy) @(posedge clk);

            src1 <= 32'h8123_4567;
            src2 <= 32'h7654_3210;
            src1_signed <= 1'b1;
            src2_signed <= 1'b0;
            high_result <= 1'b1;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            @(negedge clk);
            kill <= 1'b1;
            @(posedge clk);
            kill <= 1'b0;
            @(negedge clk);

            if (busy || done) begin
                $fatal(1, "kill did not cancel the active multiply");
            end
            for (check_cycles = 0; check_cycles < HIGH_PIPE_STAGES + 2;
                 check_cycles = check_cycles + 1) begin
                @(negedge clk);
                if (busy || done) begin
                    $fatal(1, "cancelled multiply produced a late completion");
                end
            end
        end
    endtask

    integer i;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        result_ready = 1'b1;
        kill = 1'b0;
        src1 = 32'b0;
        src2 = 32'b0;
        src1_signed = 1'b0;
        src2_signed = 1'b0;
        high_result = 1'b0;

        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        run_case(32'h0000_0000, 32'hffff_ffff, 1'b0, 1'b0, 1'b0);
        run_case(32'hffff_ffff, 32'hffff_ffff, 1'b0, 1'b0, 1'b1);
        run_case(32'hffff_ffff, 32'hffff_ffff, 1'b1, 1'b1, 1'b1);
        run_case(32'h8000_0000, 32'h0000_0002, 1'b1, 1'b1, 1'b1);
        run_case(32'h8000_0000, 32'hffff_ffff, 1'b1, 1'b0, 1'b1);
        run_case(32'hffff_fffe, 32'h8000_0001, 1'b1, 1'b0, 1'b1);
        run_kill_case();

        for (i = 0; i < 200; i = i + 1) begin
            run_case($urandom, $urandom, i[0], i[1], i[2]);
        end

        result_ready <= 1'b0;
        src1 <= 32'hffff_fffd;
        src2 <= 32'h0000_0007;
        src1_signed <= 1'b1;
        src2_signed <= 1'b1;
        high_result <= 1'b0;
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        wait (done);
        repeat (3) begin
            @(posedge clk);
            if (!done || result !== 32'hffff_ffeb) begin
                $fatal(1, "result was not held under backpressure");
            end
        end
        result_ready <= 1'b1;
        @(posedge clk);
        @(negedge clk);
        if (busy || done) begin
            $fatal(1, "backpressured result was not consumed after ready");
        end

        $display("[MUL_PIPELINE] PASS high_stages=%0d", HIGH_PIPE_STAGES);
        $finish;
    end

endmodule
