`timescale 1ns/1ps

module tb_rv32_div_rcp;
    localparam integer ROM_ADDR_WIDTH = 16;
    localparam integer ROM_BUCKET_COUNT = (1 << ROM_ADDR_WIDTH);
    localparam integer ROM_BUCKET_SHIFT = 31 - ROM_ADDR_WIDTH;
    localparam integer NORMAL_LATENCY = 14;
    localparam integer SPECIAL_LATENCY = 2;

    logic clk;
    logic rst_n;
    logic req_valid;
    logic [31:0] dividend;
    logic [31:0] divisor;
    logic signed_div;
    logic want_remainder;
    logic req_ready;
    logic busy;
    logic done;
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic [31:0] result;

    integer failures;
    integer checks;
    integer cycle_count;
    integer random_count;
    integer bucket_count;

    rv32_div_rcp #(
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cancel(1'b0),
        .req_valid(req_valid),
        .dividend(dividend),
        .divisor(divisor),
        .signed_div(signed_div),
        .want_remainder(want_remainder),
        .req_ready(req_ready),
        .busy(busy),
        .done(done),
        .quotient(quotient),
        .remainder(remainder),
        .result(result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
    end

    task automatic reference(
        input  logic [31:0] a,
        input  logic [31:0] b,
        input  logic        is_signed,
        output logic [31:0] expected_q,
        output logic [31:0] expected_r
    );
        longint signed sa;
        longint signed sb;
        longint signed sq;
        longint signed sr;
        longint unsigned ua;
        longint unsigned ub;
        longint unsigned uq;
        longint unsigned ur;
        begin
            if (b == 32'b0) begin
                expected_q = 32'hffff_ffff;
                expected_r = a;
            end else if (is_signed && (a == 32'h8000_0000) &&
                         (b == 32'hffff_ffff)) begin
                expected_q = 32'h8000_0000;
                expected_r = 32'b0;
            end else if (is_signed) begin
                sa = $signed({{32{a[31]}}, a});
                sb = $signed({{32{b[31]}}, b});
                sq = sa / sb;
                sr = sa % sb;
                expected_q = sq[31:0];
                expected_r = sr[31:0];
            end else begin
                ua = {32'b0, a};
                ub = {32'b0, b};
                uq = ua / ub;
                ur = ua % ub;
                expected_q = uq[31:0];
                expected_r = ur[31:0];
            end
        end
    endtask

    task automatic run_case(
        input string       name,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic        is_signed,
        input logic        rem_select
    );
        logic [31:0] expected_q;
        logic [31:0] expected_r;
        logic [31:0] expected_result;
        integer start_cycle;
        integer latency;
        integer expected_latency;
        integer guard;
        begin
            reference(a, b, is_signed, expected_q, expected_r);
            expected_result = rem_select ? expected_r : expected_q;
            expected_latency = ((b == 32'b0) ||
                                (is_signed && (a == 32'h8000_0000) &&
                                 (b == 32'hffff_ffff))) ?
                               SPECIAL_LATENCY : NORMAL_LATENCY;

            @(negedge clk);
            while (!req_ready)
                @(negedge clk);
            dividend = a;
            divisor = b;
            signed_div = is_signed;
            want_remainder = rem_select;
            req_valid = 1'b1;
            @(posedge clk);
            #1;
            start_cycle = cycle_count;
            req_valid = 1'b0;

            // Inputs are deliberately changed while busy; the unit must use
            // only the request accepted at the start edge.
            dividend = 32'h1357_9bdf;
            divisor = 32'h2468_ace1;
            signed_div = 1'b0;
            want_remainder = 1'b0;

            guard = 0;
            while (!done && guard < 40) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            latency = cycle_count - start_cycle;
            checks = checks + 1;
            if (!done || (quotient !== expected_q) ||
                (remainder !== expected_r) || (result !== expected_result) ||
                (latency != expected_latency)) begin
                failures = failures + 1;
                $display("RCP_DIV_FAIL %s a=%08x b=%08x signed=%0b rem=%0b q=%08x/%08x r=%08x/%08x result=%08x/%08x done=%0b latency=%0d/%0d",
                         name, a, b, is_signed, rem_select,
                         quotient, expected_q, remainder, expected_r,
                         result, expected_result, done, latency,
                         expected_latency);
            end
            @(posedge clk);
            #1;
            if (done) begin
                failures = failures + 1;
                $display("RCP_DIV_DONE_NOT_PULSED %s", name);
            end
        end
    endtask

    function automatic [31:0] lfsr_next(input [31:0] value);
        lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    initial begin : stimulus
        logic [31:0] seed;
        logic [31:0] a;
        logic [31:0] b;
        logic [31:0] x;
        integer i;
        integer h;
        integer tail;

        failures = 0;
        checks = 0;
        cycle_count = 0;
        random_count = 20000;
        bucket_count = ROM_BUCKET_COUNT;
        void'($value$plusargs("N=%d", random_count));
        void'($value$plusargs("BUCKETS=%d", bucket_count));
        if ((bucket_count < 0) || (bucket_count > ROM_BUCKET_COUNT))
            $fatal(1, "BUCKETS must be between 0 and %0d", ROM_BUCKET_COUNT);

        rst_n = 1'b0;
        req_valid = 1'b0;
        dividend = 32'b0;
        divisor = 32'b0;
        signed_div = 1'b0;
        want_remainder = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        run_case("zero", 32'b0, 32'd7, 1'b0, 1'b0);
        run_case("equal", 32'hffff_ffff, 32'hffff_ffff, 1'b0, 1'b1);
        run_case("less", 32'd3, 32'd7, 1'b0, 1'b1);
        run_case("max_by_one", 32'hffff_ffff, 32'd1, 1'b0, 1'b0);
        run_case("min_by_two", 32'h8000_0000, 32'd2, 1'b0, 1'b0);
        run_case("div_zero_s", 32'hffff_fffb, 32'b0, 1'b1, 1'b0);
        run_case("rem_zero_s", 32'hffff_fffb, 32'b0, 1'b1, 1'b1);
        run_case("overflow", 32'h8000_0000, 32'hffff_ffff, 1'b1, 1'b0);
        run_case("overflow_rem", 32'h8000_0000, 32'hffff_ffff, 1'b1, 1'b1);
        run_case("negative_q", 32'hffff_fffb, 32'd3, 1'b1, 1'b0);
        run_case("negative_r", 32'hffff_fffb, 32'd3, 1'b1, 1'b1);
        run_case("both_negative", 32'hffff_fffb, 32'hffff_fffd, 1'b1, 1'b0);
        run_case("signed_min_q", 32'h8000_0000, 32'd3, 1'b1, 1'b0);
        run_case("signed_min_r", 32'h8000_0000, 32'd3, 1'b1, 1'b1);
        run_case("signed_allones_div1", 32'hffff_ffff, 32'd1, 1'b1, 1'b0);

        // Exercise every possible leading-zero count in both signed and
        // unsigned modes, including two's-complement divisor magnitudes.
        for (h = 0; h < 32; h = h + 1) begin
            b = 32'h0000_0001 << h;
            run_case("lzc_unsigned_q", 32'h7abc_def1, b, 1'b0, 1'b0);
            run_case("lzc_unsigned_r", 32'h7abc_def1, b, 1'b0, 1'b1);
            run_case("lzc_signed_pos_q", 32'h8123_4567, b, 1'b1, 1'b0);
            run_case("lzc_signed_pos_r", 32'h8123_4567, b, 1'b1, 1'b1);
            b = (~(32'h0000_0001 << h)) + 32'd1;
            run_case("lzc_signed_neg_q", 32'h8123_4567, b, 1'b1, 1'b0);
            run_case("lzc_signed_neg_r", 32'h8123_4567, b, 1'b1, 1'b1);
        end

        // Hit both endpoints of every selected normalized ROM bucket.  The
        // default sweep covers all 65536 entries used by the F40 design.
        tail = (1 << ROM_BUCKET_SHIFT) - 1;
        for (h = 0; h < bucket_count; h = h + 1) begin
            x = 32'h8000_0000 + (h * (1 << ROM_BUCKET_SHIFT));
            run_case("bucket_lo", 32'hffff_ffff, x, 1'b0, 1'b0);
            run_case("bucket_hi", 32'hffff_ffff, x | tail, 1'b0, 1'b1);
        end

        seed = 32'h1ace_b00c;
        for (i = 0; i < random_count; i = i + 1) begin
            seed = lfsr_next(seed);
            a = seed;
            seed = lfsr_next(seed);
            b = seed;
            if ((i % 17) == 0)
                b = 32'b0;
            else if ((i % 19) == 0)
                b = 32'd1;
            else if ((i % 23) == 0)
                b = 32'h8000_0000;
            run_case("random_div", a, b, (i & 1), 1'b0);
            run_case("random_rem", a, b, (i & 1), 1'b1);
        end

        if (failures == 0)
            $display("RCP_DIVIDER_TEST_PASSED checks=%0d", checks);
        else
            $fatal(1, "RCP_DIVIDER_TEST_FAILED failures=%0d checks=%0d", failures, checks);
        $finish;
    end
endmodule
