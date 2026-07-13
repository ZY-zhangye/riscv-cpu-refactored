module divider #(
    parameter integer LATENCY = 12
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        kill,
    input  logic [31:0] dividend,
    input  logic [31:0] divisor,
    input  logic        signed_mode,
    input  logic        remainder,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);

    logic [7:0] cycles_left;
    logic [31:0] pending_result;

    function automatic logic [31:0] divide_result(
        input logic [31:0] dividend_value,
        input logic [31:0] divisor_value,
        input logic signed_operation,
        input logic want_remainder
    );
        logic [31:0] dividend_magnitude;
        logic [31:0] divisor_magnitude;
        logic [31:0] quotient_magnitude;
        logic [31:0] remainder_magnitude;
        logic [31:0] quotient_value;
        logic [31:0] remainder_value;
        begin
            if (divisor_value == 32'b0) begin
                quotient_value = 32'hffff_ffff;
                remainder_value = dividend_value;
            end else if (signed_operation &&
                         (dividend_value == 32'h8000_0000) &&
                         (divisor_value == 32'hffff_ffff)) begin
                quotient_value = 32'h8000_0000;
                remainder_value = 32'b0;
            end else begin
                dividend_magnitude = signed_operation && dividend_value[31] ?
                                     (~dividend_value + 1'b1) : dividend_value;
                divisor_magnitude = signed_operation && divisor_value[31] ?
                                    (~divisor_value + 1'b1) : divisor_value;
                quotient_magnitude = dividend_magnitude / divisor_magnitude;
                remainder_magnitude = dividend_magnitude % divisor_magnitude;
                quotient_value = signed_operation &&
                                 (dividend_value[31] ^ divisor_value[31]) ?
                                 (~quotient_magnitude + 1'b1) :
                                 quotient_magnitude;
                remainder_value = signed_operation && dividend_value[31] ?
                                  (~remainder_magnitude + 1'b1) :
                                  remainder_magnitude;
            end
            divide_result = want_remainder ? remainder_value : quotient_value;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles_left <= 8'b0;
            pending_result <= 32'b0;
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
        end else begin
            done <= 1'b0;
            if (kill) begin
                cycles_left <= 8'b0;
                busy <= 1'b0;
            end else if (start && !busy) begin
                if ((divisor == 32'b0) ||
                    (signed_mode && (dividend == 32'h8000_0000) &&
                     (divisor == 32'hffff_ffff))) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    result <= divide_result(dividend, divisor,
                                            signed_mode, remainder);
                end else begin
                    pending_result <= divide_result(dividend, divisor,
                                                    signed_mode, remainder);
                    cycles_left <= LATENCY;
                    busy <= 1'b1;
                end
            end else if (busy) begin
                if (cycles_left > 8'd1) begin
                    cycles_left <= cycles_left - 1'b1;
                end else begin
                    cycles_left <= 8'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    result <= pending_result;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && start && busy) begin
            $fatal(1, "divider received a duplicate start while busy");
        end
    end
`endif

endmodule
