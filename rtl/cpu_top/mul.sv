`include "defines.svh"

module mul (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        op_valid,
    input  logic        op_accept,
    input  logic        op_kill,
    input  logic        is_mul,
    input  logic        is_multicycle,
    input  logic [31:0] mul_src1,
    input  logic [31:0] mul_src2,
    input  logic [3:0]  mul_op,
    input  logic        src1_signed,
    input  logic        src2_signed,
    output logic [31:0] mul_result,
    output logic        mul_stall
);

    logic signed [32:0] mul_src1_ext;
    logic signed [32:0] mul_src2_ext;
    logic signed [65:0] mul_result_ext;
    logic signed [65:0] mul_result_hold;
    logic [`MUL_CYCLE-1:0] mul_valid_shift;
    logic mul_start;
    logic mul_done_pulse;
    logic mul_inflight;
    logic mul_result_valid;
    logic mul_available;
    logic mul_op_mul;

    logic div_req_valid;
    logic div_req_ready;
    logic div_busy;
    logic div_raw_done;
    logic div_cancel;
    logic div_inflight;
    logic div_result_valid;
    logic div_available;
    logic [31:0] div_quotient;
    logic [31:0] div_remainder;
    logic [31:0] div_raw_result;
    logic [31:0] div_result_hold;
    logic mul_op_div;

    assign mul_op_mul = mul_op[3] || mul_op[2];
    assign mul_op_div = mul_op[1] || mul_op[0];

    assign mul_src1_ext = src1_signed ? {mul_src1[31], mul_src1} :
                                        {1'b0, mul_src1};
    assign mul_src2_ext = src2_signed ? {mul_src2[31], mul_src2} :
                                        {1'b0, mul_src2};

    assign mul_start = op_valid && is_mul && mul_op_mul &&
                       !mul_inflight && !mul_result_valid;
    assign mul_done_pulse = mul_valid_shift[`MUL_CYCLE-1];
    assign mul_available = mul_result_valid ||
                           (mul_done_pulse && mul_inflight);

    assign div_cancel = op_kill ||
                        (div_inflight &&
                         (!op_valid || !is_mul || !mul_op_div));
    assign div_req_valid = op_valid && is_mul && is_multicycle &&
                           mul_op_div && !div_inflight &&
                           !div_result_valid && div_req_ready &&
                           !div_cancel;
    assign div_available = div_result_valid ||
                           (div_raw_done && div_inflight);

    assign mul_stall = op_valid && is_mul && is_multicycle &&
                       ((mul_op_mul && !mul_available) ||
                        (mul_op_div && !div_available));

    // Hold multiplier completion until the resident EX operation is actually
    // accepted.  This prevents a one-cycle done pulse from being lost under
    // MEM or bundle backpressure.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_valid_shift <= '0;
            mul_inflight <= 1'b0;
            mul_result_valid <= 1'b0;
            mul_result_hold <= '0;
        end else if (op_kill || !op_valid || !is_mul || !mul_op_mul) begin
            mul_valid_shift <= '0;
            mul_inflight <= 1'b0;
            mul_result_valid <= 1'b0;
        end else if (mul_result_valid) begin
            mul_valid_shift <= '0;
            if (op_accept)
                mul_result_valid <= 1'b0;
        end else if (mul_done_pulse && mul_inflight) begin
            mul_valid_shift <= '0;
            mul_inflight <= 1'b0;
            mul_result_hold <= mul_result_ext;
            mul_result_valid <= !op_accept;
        end else begin
            mul_valid_shift <= {mul_valid_shift[`MUL_CYCLE-2:0], mul_start};
            if (mul_start)
                mul_inflight <= 1'b1;
        end
    end

    // The reciprocal divider returns a pulse, while EX may remain blocked by
    // the other lane or MEM.  Capture the result unless it is consumed in the
    // completion cycle, and cancel any flushed resident operation.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_inflight <= 1'b0;
            div_result_valid <= 1'b0;
            div_result_hold <= '0;
        end else if (div_cancel || !op_valid || !is_mul || !mul_op_div) begin
            div_inflight <= 1'b0;
            div_result_valid <= 1'b0;
        end else begin
            if (div_req_valid && div_req_ready)
                div_inflight <= 1'b1;

            if (div_raw_done && div_inflight) begin
                div_inflight <= 1'b0;
                div_result_hold <= div_raw_result;
                div_result_valid <= !op_accept;
            end else if (div_result_valid && op_accept) begin
                div_result_valid <= 1'b0;
            end
        end
    end

    always_comb begin
        unique case (1'b1)
            mul_op[3]: mul_result = mul_result_valid ?
                                        mul_result_hold[31:0] :
                                        mul_result_ext[31:0];
            mul_op[2]: mul_result = mul_result_valid ?
                                        mul_result_hold[63:32] :
                                        mul_result_ext[63:32];
            mul_op[1], mul_op[0]:
                mul_result = div_result_valid ? div_result_hold :
                                                div_raw_result;
            default: mul_result = 32'b0;
        endcase
    end

`ifdef DEBUG_EN
    assign mul_result_ext = mul_src1_ext * mul_src2_ext;
`else
    multiplier mul_inst (
        .CLK(clk),
        .A(mul_src1_ext),
        .B(mul_src2_ext),
        .P(mul_result_ext),
        .CE(op_valid && is_mul && mul_op_mul)
    );
`endif

    rv32_div_rcp u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .cancel(div_cancel),
        .req_valid(div_req_valid),
        .dividend(mul_src1),
        .divisor(mul_src2),
        .signed_div(src1_signed && src2_signed),
        .want_remainder(mul_op[0]),
        .req_ready(div_req_ready),
        .busy(div_busy),
        .done(div_raw_done),
        .quotient(div_quotient),
        .remainder(div_remainder),
        .result(div_raw_result)
    );

endmodule
