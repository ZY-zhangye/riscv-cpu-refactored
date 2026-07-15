module mul_pipeline #(
    parameter integer HIGH_PIPE_STAGES = 3
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        result_ready,
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

    logic active;
    logic stage1_valid;
    logic stage2_valid;

    logic [31:0] src1_r;
    logic [31:0] src2_r;
    logic        src1_negative_r;
    logic        src2_negative_r;
    logic        high_result_r;

    (* use_dsp = "yes" *) logic [31:0] partial_ll;
    (* use_dsp = "yes" *) logic [31:0] partial_lh;
    (* use_dsp = "yes" *) logic [31:0] partial_hl;
    (* use_dsp = "yes" *) logic [31:0] partial_hh;

    (* use_dsp = "no" *) logic [32:0] middle_sum;
    (* use_dsp = "no" *) logic [31:0] unsigned_high;
    (* use_dsp = "no" *) logic [31:0] corrected_high;
    logic [31:0] low_result;

    logic [16:0] middle_high_r;
    logic [31:0] partial_hh_r;
    (* use_dsp = "no" *) logic [31:0] three_stage_high;

    logic start_accept;
    logic low_complete;
    logic high_complete;

    assign busy = active;
    assign start_accept = start && !active;

    // A raw unsigned product can be converted to signed or mixed-signed form
    // by subtracting the opposite operand from the high word for each signed
    // negative input. The low word is identical for all RV32 MUL variants.
    assign middle_sum = {1'b0, partial_lh} +
                        {1'b0, partial_hl} +
                        {17'b0, partial_ll[31:16]};
    assign unsigned_high = partial_hh + {15'b0, middle_sum[32:16]};
    assign corrected_high = unsigned_high -
                            (src1_negative_r ? src2_r : 32'b0) -
                            (src2_negative_r ? src1_r : 32'b0);
    assign low_result = {middle_sum[15:0], partial_ll[15:0]};

    assign three_stage_high = partial_hh_r + {15'b0, middle_high_r} -
                              (src1_negative_r ? src2_r : 32'b0) -
                              (src2_negative_r ? src1_r : 32'b0);
    assign low_complete = !high_result_r && stage1_valid;
    assign high_complete = high_result_r &&
                           ((HIGH_PIPE_STAGES == 2) ? stage1_valid : stage2_valid);

    always_ff @(posedge clk) begin
        if (!rst_n || kill) begin
            active <= 1'b0;
            done <= 1'b0;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            result <= 32'b0;
        end else begin
            stage1_valid <= start_accept;
            stage2_valid <= stage1_valid;

            if (start_accept) begin
                src1_r <= src1;
                src2_r <= src2;
                src1_negative_r <= src1_signed && src1[31];
                src2_negative_r <= src2_signed && src2[31];
                high_result_r <= high_result;
                partial_ll <= src1[15:0] * src2[15:0];
                partial_lh <= src1[15:0] * src2[31:16];
                partial_hl <= src1[31:16] * src2[15:0];
                partial_hh <= src1[31:16] * src2[31:16];
                active <= 1'b1;
            end

            if (stage1_valid) begin
                middle_high_r <= middle_sum[32:16];
                partial_hh_r <= partial_hh;
            end

            if (low_complete) begin
                result <= low_result;
                done <= 1'b1;
            end else if (high_complete) begin
                result <= (HIGH_PIPE_STAGES == 2) ? corrected_high : three_stage_high;
                done <= 1'b1;
            end else if (done && result_ready) begin
                done <= 1'b0;
                active <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if ((HIGH_PIPE_STAGES != 2) && (HIGH_PIPE_STAGES != 3)) begin
            $fatal(1, "mul_pipeline HIGH_PIPE_STAGES must be 2 or 3");
        end
    end
`endif

endmodule
