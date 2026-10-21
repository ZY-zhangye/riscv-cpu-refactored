// Board implementation of the CPU-local divider interface.
// Include this file instead of rtl/cpu_top/divider.sv for FPGA builds.
// The existing mul controller expects {remainder, quotient} with DEBUG_EN.
module divider (
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
    logic busy;
    logic [4:0] iteration;
    logic [31:0] divisor;
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic [32:0] shifted_remainder;
    logic [32:0] subtracted_remainder;
    logic [31:0] next_remainder;
    logic [31:0] next_quotient;
    logic accept;

    // This is the CPU's paired-input convention: both channels are accepted
    // on the same edge. No independent AXI input-channel buffering is needed.
    assign s_axis_divisor_tready = aresetn && !busy &&
                                  !m_axis_dout_tvalid && s_axis_dividend_tvalid;
    assign s_axis_dividend_tready = aresetn && !busy &&
                                   !m_axis_dout_tvalid && s_axis_divisor_tvalid;
    assign accept = s_axis_divisor_tvalid && s_axis_divisor_tready &&
                    s_axis_dividend_tvalid && s_axis_dividend_tready;

    // One restoring-division step per clock, processing the dividend MSB first.
    // The extra remainder bit preserves the carry before the subtraction.
    assign shifted_remainder = {remainder, quotient[31]};
    assign subtracted_remainder = shifted_remainder - {1'b0, divisor};
    assign next_remainder = subtracted_remainder[32] ?
                            shifted_remainder[31:0] : subtracted_remainder[31:0];
    assign next_quotient = {quotient[30:0], !subtracted_remainder[32]};

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            busy <= 1'b0;
            iteration <= 5'd0;
            divisor <= 32'd0;
            quotient <= 32'd0;
            remainder <= 32'd0;
            m_axis_dout_tvalid <= 1'b0;
            m_axis_dout_tdata <= 64'd0;
        end else begin
            // No output backpressure port: each completed response lasts one
            // clock. The mul controller captures or drains it on that edge.
            m_axis_dout_tvalid <= 1'b0;
            if (accept) begin
                divisor <= s_axis_divisor_tdata;
                quotient <= s_axis_dividend_tdata;
                remainder <= 32'd0;
                iteration <= 5'd0;
                busy <= 1'b1;
            end else if (busy) begin
                quotient <= next_quotient;
                remainder <= next_remainder;
                if (iteration == 5'd31) begin
                    busy <= 1'b0;
                    m_axis_dout_tvalid <= 1'b1;
                    m_axis_dout_tdata <= {next_remainder, next_quotient};
                end else begin
                    iteration <= iteration + 5'd1;
                end
            end
        end
    end
endmodule
