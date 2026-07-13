`include "defines.svh"

module mul (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        kill,
    input  logic [31:0] src1,
    input  logic [31:0] src2,
    input  logic        src1_signed,
    input  logic        src2_signed,
    input  logic        high_result,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);

    logic signed [32:0] src1_r;
    logic signed [32:0] src2_r;
    logic signed [65:0] product;
    logic high_result_r;
    logic [7:0] cycles_left;

`ifdef DEBUG_EN
    assign product = src1_r * src2_r;
`else
    multiplier u_multiplier (
        .CLK(clk),
        .A(src1_r),
        .B(src2_r),
        .P(product),
        .CE(busy)
    );
`endif

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            src1_r <= '0;
            src2_r <= '0;
            high_result_r <= 1'b0;
            cycles_left <= 8'b0;
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
        end else begin
            done <= 1'b0;
            if (kill) begin
                cycles_left <= 8'b0;
                busy <= 1'b0;
            end else if (start && !busy) begin
                src1_r <= src1_signed ? {src1[31], src1} : {1'b0, src1};
                src2_r <= src2_signed ? {src2[31], src2} : {1'b0, src2};
                high_result_r <= high_result;
                // MUL_CYCLE includes the request/start edge.  The remaining
                // counter therefore covers only the post-start resident cycles.
                cycles_left <= `MUL_CYCLE - 1;
                busy <= 1'b1;
            end else if (busy) begin
                if (cycles_left > 8'd1) begin
                    cycles_left <= cycles_left - 1'b1;
                end else begin
                    cycles_left <= 8'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    result <= high_result_r ? product[63:32] : product[31:0];
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && start && busy) begin
            $fatal(1, "multiplier received a duplicate start while busy");
        end
    end
`endif

endmodule
