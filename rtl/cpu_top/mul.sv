`include "defines.svh"

module mul (
    input logic clk,
    input logic rst_n,
    input logic is_mul,
    input logic is_multicycle,
    input logic [31:0] mul_src1,
    input logic [31:0] mul_src2,
    input logic [3:0] mul_op,
    input logic src1_signed,
    input logic src2_signed,
    input logic result_ready,
    input logic kill,
    output logic [31:0] mul_result,
    output logic mul_stall
);
    // 这里只整理乘法模块的控制与结果选择；后续可直接替换为 IP 核实现。

    // --------------------
    // 乘法路径
    // --------------------
    logic [31:0]        mul_product;
    logic               mul_start;
    logic               mul_done;
    logic               mul_busy;
    logic               mul_op_mul;

    // --------------------
    // 除法 / 取余路径
    // --------------------
    logic [31:0] div_src1, div_src2;
    logic [63:0] div_result;
    logic        div_0;
    logic        div_1;
    logic [1:0]  div_state;
    logic        div_start;
    logic        mul_op_div;
    logic        div_done;
    logic        div_discard_pending;
    logic        s1,s2;
    
    // AXI流接口信号 - 除数输入
    logic        s_axis_divisor_tvalid;
    logic        s_axis_divisor_tready;
    logic [31:0] s_axis_divisor_tdata;
    
    // AXI流接口信号 - 被除数输入
    logic        s_axis_dividend_tvalid;
    logic        s_axis_dividend_tready;
    logic [31:0] s_axis_dividend_tdata;
    
    // AXI流接口信号 - 输出结果
    logic        m_axis_dout_tvalid;
    logic [63:0] m_axis_dout_tdata;
    logic [63:0] m_axis_dout_tdata_reg;

    assign mul_op_mul = mul_op[3] || mul_op[2];
    assign mul_op_div = mul_op[1] || mul_op[0];

    assign div_src1 = src1_signed && mul_src1[31] ? ~mul_src1 + 1'b1 : mul_src1;
    assign div_src2 = src2_signed && mul_src2[31] ? ~mul_src2 + 1'b1 : mul_src2;

    assign div_0 = (div_src2 == 32'b0);
    assign div_1 = src1_signed && src2_signed &&
                   (mul_src1 == 32'h8000_0000) &&
                   (mul_src2 == 32'hffff_ffff);

    assign s1 = src1_signed && src2_signed && (mul_src1[31] ^ mul_src2[31]);
    assign s2 = src1_signed && mul_src1[31];

    assign mul_start = is_mul && mul_op_mul;

    assign div_start = is_multicycle && is_mul && mul_op_div &&
                       (div_state == 2'b00) && !div_discard_pending &&
                       !kill && !div_0 && !div_1;
    
    // AXI流握手信号 - 仅在两个输入都ready时才valid
    assign s_axis_divisor_tvalid  = div_start;
    assign s_axis_dividend_tvalid = div_start;
    assign s_axis_divisor_tdata   = div_src2;
    assign s_axis_dividend_tdata  = div_src1;
    
    assign div_done = (div_state == 2'b11) || (div_state == 2'b10);

    assign mul_stall = !kill && is_mul &&
                       ((mul_op_mul && !mul_done) ||
                        (mul_op_div && !div_done));

    mul_pipeline #(
        .HIGH_PIPE_STAGES(`MUL_HIGH_CYCLE)
    ) u_mul_pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .start(mul_start),
        .result_ready(result_ready),
        .kill(kill),
        .src1(mul_src1),
        .src2(mul_src2),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .high_result(mul_op[2]),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_product)
    );

    always_comb begin
        unique case (1'b1)
            mul_op[3]: begin
                mul_result = mul_product;
            end
            mul_op[2]: begin
                mul_result = mul_product;
            end
            mul_op[1]: begin
                // DIV: DEBUG仿真divider输出{remainder, quotient}，工程IP输出{quotient, remainder}
`ifdef DEBUG_EN
                mul_result = (s1 && div_state == 2'b11) ?
                             (~m_axis_dout_tdata_reg[31:0] + 1'b1) :
                             div_result[31:0];
`else
                mul_result = (s1 && div_state == 2'b11) ?
                             (~m_axis_dout_tdata_reg[63:32] + 1'b1) :
                             div_result[63:32];
`endif
            end
            mul_op[0]: begin
                // REM: DEBUG仿真divider输出{remainder, quotient}，工程IP输出{quotient, remainder}
`ifdef DEBUG_EN
                mul_result = (s2 && div_state == 2'b11) ?
                             (~m_axis_dout_tdata_reg[63:32] + 1'b1) :
                             div_result[63:32];
`else
                mul_result = (s2 && div_state == 2'b11) ?
                             (~m_axis_dout_tdata_reg[31:0] + 1'b1) :
                             div_result[31:0];
`endif
            end
            default: begin
                mul_result = 32'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_state <= 2'b00;
            div_discard_pending <= 1'b0;
            div_result <= 64'b0;
            m_axis_dout_tdata_reg <= 64'b0;
        end else if (kill) begin
            div_state <= 2'b00;
            // A pipeline flush does not reset the divider. If a request was
            // already accepted, wait for and discard its eventual response.
            div_discard_pending <=
                (div_discard_pending || (div_state == 2'b01)) &&
                !m_axis_dout_tvalid;
        end else if (div_discard_pending) begin
            div_state <= 2'b00;
            if (m_axis_dout_tvalid) begin
                div_discard_pending <= 1'b0;
            end
        end else begin
            div_discard_pending <= 1'b0;
            unique case (div_state)
                2'b00: begin
                    // 等待除法请求，检查特殊情况
                    if (div_start) begin
                        if (s_axis_divisor_tready && s_axis_dividend_tready && 
                        s_axis_divisor_tvalid && s_axis_dividend_tvalid) 
                        div_state <= 2'b01;
                    end else if (is_multicycle && is_mul && mul_op_div && (div_0 || div_1)) begin
                        div_state <= 2'b10;
`ifdef DEBUG_EN
                        div_result <= div_0 ? {mul_src1, 32'hffff_ffff} :
                                       {32'h0000_0000, 32'h8000_0000} ;
`else
                        div_result <= div_0 ? {32'hffff_ffff, mul_src1} :
                                       {32'h8000_0000, 32'h0000_0000} ;
`endif
                    end else begin
                        div_state <= 2'b00;
                    end
                end
                2'b01: begin
                    // 等待输出有效信号
                    if (m_axis_dout_tvalid) begin
                        div_state <= 2'b11;
                        m_axis_dout_tdata_reg <= m_axis_dout_tdata; // 捕获结果以供后续周期使用
                        div_result <= m_axis_dout_tdata; // 直接使用输出结果
                    end
                end
                2'b10: begin
                    // 输出特殊结果后回到初始状态
                    div_state <= 2'b00;
                end
                2'b11: begin
                    div_state <= 2'b00; // 结果已捕获，回到初始状态等待下一次除法请求
                end
                default: begin
                    div_state <= 2'b00;
                end
            endcase
        end
    end


    divider div_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_divisor_tvalid(s_axis_divisor_tvalid),    
        .s_axis_divisor_tready(s_axis_divisor_tready),    
        .s_axis_divisor_tdata(s_axis_divisor_tdata),      
        .s_axis_dividend_tvalid(s_axis_dividend_tvalid),  
        .s_axis_dividend_tready(s_axis_dividend_tready),  
        .s_axis_dividend_tdata(s_axis_dividend_tdata),    
        .m_axis_dout_tvalid(m_axis_dout_tvalid),                 
        .m_axis_dout_tdata(m_axis_dout_tdata)            
    );

    /*assign div_result = div_0 ? {mul_src1, 32'hffff_ffff} :
                        div_1 ? {32'h0000_0000, 32'h8000_0000} :
                        m_axis_dout_tdata;*/



endmodule
