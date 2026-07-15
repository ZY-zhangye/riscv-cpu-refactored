`ifdef TB_DIV_KILL_DRAIN
`timescale 1ns/1ps

// A pipelined Divider Generator stand-in. It intentionally keeps accepted
// operations alive across the wrapper's kill signal, matching the synthesis
// IP, which has no reset port.
module divider #(
    parameter integer LATENCY = 6
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        s_axis_divisor_tvalid,
    output logic        s_axis_divisor_tready,
    input  logic [31:0] s_axis_divisor_tdata,
    input  logic        s_axis_dividend_tvalid,
    output logic        s_axis_dividend_tready,
    input  logic [31:0] s_axis_dividend_tdata,
    output logic        m_axis_dout_tvalid,
    output logic [63:0] m_axis_dout_tdata
);

    logic [LATENCY-1:0] valid_pipe;
    logic [63:0] data_pipe [0:LATENCY-1];
    logic input_accept;
    integer accept_count;
    integer output_count;
    integer i;

    assign s_axis_divisor_tready = 1'b1;
    assign s_axis_dividend_tready = 1'b1;
    assign input_accept = s_axis_divisor_tvalid &&
                          s_axis_dividend_tvalid;
    assign m_axis_dout_tvalid = valid_pipe[LATENCY-1];
    assign m_axis_dout_tdata = data_pipe[LATENCY-1];

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            valid_pipe <= '0;
            accept_count <= 0;
            output_count <= 0;
            for (i = 0; i < LATENCY; i = i + 1) begin
                data_pipe[i] <= '0;
            end
        end else begin
            for (i = LATENCY - 1; i > 0; i = i - 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                data_pipe[i] <= data_pipe[i-1];
            end
            valid_pipe[0] <= input_accept;

            if (input_accept) begin
                data_pipe[0] <= {
                    s_axis_dividend_tdata % s_axis_divisor_tdata,
                    s_axis_dividend_tdata / s_axis_divisor_tdata
                };
                accept_count <= accept_count + 1;
            end
            if (m_axis_dout_tvalid) begin
                output_count <= output_count + 1;
            end
        end
    end

endmodule

module tb_div_kill_drain;

    logic clk;
    logic rst_n;
    logic is_mul;
    logic is_multicycle;
    logic [31:0] mul_src1;
    logic [31:0] mul_src2;
    logic [3:0] mul_op;
    logic src1_signed;
    logic src2_signed;
    logic result_ready;
    logic kill;
    logic [31:0] mul_result;
    logic mul_stall;

    mul dut (
        .clk(clk),
        .rst_n(rst_n),
        .is_mul(is_mul),
        .is_multicycle(is_multicycle),
        .mul_src1(mul_src1),
        .mul_src2(mul_src2),
        .mul_op(mul_op),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .result_ready(result_ready),
        .kill(kill),
        .mul_result(mul_result),
        .mul_stall(mul_stall)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        is_mul = 1'b0;
        is_multicycle = 1'b1;
        mul_src1 = 32'b0;
        mul_src2 = 32'b0;
        mul_op = 4'b0010;
        src1_signed = 1'b0;
        src2_signed = 1'b0;
        result_ready = 1'b1;
        kill = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Launch an operation whose result must be discarded.
        mul_src1 = 32'd100;
        mul_src2 = 32'd7;
        is_mul = 1'b1;
        wait (dut.div_inst.accept_count == 1);

        // Kill it while the unresettable divider pipeline still owns it.
        @(negedge clk);
        kill = 1'b1;
        @(posedge clk);
        @(negedge clk);
        kill = 1'b0;
        mul_src1 = 32'd81;
        mul_src2 = 32'd9;

        // The replacement DIV must remain blocked until the stale response
        // has appeared and been discarded.
        repeat (2) begin
            @(posedge clk);
            #1;
            if (dut.div_inst.accept_count != 1) begin
                $fatal(1, "replacement DIV was accepted before drain completed");
            end
        end

        wait (dut.div_inst.output_count == 1);
        wait (dut.div_inst.accept_count == 2);
        wait (!mul_stall);
        #1;
        if (mul_result !== 32'd9) begin
            $fatal(1, "stale DIV result leaked: expected 9, got %0d", mul_result);
        end

        $display("PASS tb_div_kill_drain result=%0d", mul_result);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "tb_div_kill_drain timeout");
    end

endmodule
`endif
