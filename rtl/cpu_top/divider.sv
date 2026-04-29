// 除法器模块 - 逻辑验证版本
// 实现 AXI Stream 接口的除法功能
// 输出格式: [63:32] = 余数, [31:0] = 商

module divider (
    input logic aclk,
    input logic aresetn,
    
    // AXI Stream 除数输入
    input logic s_axis_divisor_tvalid,
    output logic s_axis_divisor_tready,
    input logic [31:0] s_axis_divisor_tdata,
    
    // AXI Stream 被除数输入
    input logic s_axis_dividend_tvalid,
    output logic s_axis_dividend_tready,
    input logic [31:0] s_axis_dividend_tdata,
    
    // AXI Stream 输出结果
    output logic m_axis_dout_tvalid,
    output logic [63:0] m_axis_dout_tdata
);

    // 内部信号
    logic [31:0] divisor_reg, dividend_reg;
    logic [1:0] state;
    logic [4:0] delay_counter;
    logic input_handshake_done;

    // 状态定义
    localparam IDLE = 2'b00;
    localparam WAIT_RESULT = 2'b01;
    localparam OUTPUT_VALID = 2'b10;

    // AXI Stream 握手逻辑 - 两个输入都有效时才ready
    assign s_axis_divisor_tready = (state == IDLE) && s_axis_dividend_tvalid;
    assign s_axis_dividend_tready = (state == IDLE) && s_axis_divisor_tvalid;
    assign input_handshake_done = s_axis_divisor_tvalid && s_axis_divisor_tready &&
                                  s_axis_dividend_tvalid && s_axis_dividend_tready;

    // 输出握手逻辑
    assign m_axis_dout_tvalid = (state == OUTPUT_VALID);
    assign m_axis_dout_tdata = {dividend_reg % divisor_reg, dividend_reg / divisor_reg};

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            divisor_reg <= 32'b0;
            dividend_reg <= 32'b0;
            delay_counter <= 5'b0;
        end else begin
            unique case (state)
                IDLE: begin
                    if (input_handshake_done) begin
                        divisor_reg <= s_axis_divisor_tdata;
                        dividend_reg <= s_axis_dividend_tdata;
                        delay_counter <= 5'd10; // 模拟除法延迟 10 个周期
                        state <= WAIT_RESULT;
                    end
                end
                
                WAIT_RESULT: begin
                    if (delay_counter > 5'b0) begin
                        delay_counter <= delay_counter - 1'b1;
                    end else begin
                        state <= OUTPUT_VALID;
                    end
                end
                
                OUTPUT_VALID: begin
                    // 输出一个周期后回到空闲状态
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
