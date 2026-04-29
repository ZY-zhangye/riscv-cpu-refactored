`include "defines.svh"
`ifdef DEBUG_EN
module div (
    input clk,
    input rst_n,
    input [31:0] div_src1,
    input [31:0] div_src2,
    input div1_valid,
    input div2_valid,
    output logic [63:0] div_result,
    output logic div_valid
);

    logic [31:0] src1_reg, src2_reg;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            src1_reg <= 32'b0;
        end else
        if (div1_valid) begin
            src1_reg <= div_src1;
        end else begin
            src1_reg <= src1_reg;
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            src2_reg <= 32'b0;
        end else
        if (div2_valid) begin
            src2_reg <= div_src2;
        end else begin
            src2_reg <= src2_reg;
        end
    end
    logic [1:0] state;
    always_ff @(posedge clk)begin
        if (!rst_n) begin
            state <= 2'b00;
            div_valid <= 1'b0;
        end else begin
            case (state)
                2'b00: begin
                    if (div1_valid && div2_valid) begin
                        state <= 2'b01;
                    end else begin
                        state <= 2'b00;
                    end
                end
                2'b01: begin
                    repeat ($urandom_range(5, 35)) @(posedge clk); // 模拟除法运算的随机周期
                    state <= 2'b10;
                end
                2'b10: begin
                    div_valid <= 1'b1;
                    div_result <= {src1_reg % src2_reg, src1_reg / src2_reg}; 
                    state <= 2'b11;
                end
                2'b11: begin
                    div_valid <= 1'b0; // 输出结果后复位valid信号
                    state <= 2'b00; // 回到初始状态等待下一次输入
                end
            endcase
        end
    end


endmodule
`endif
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
    output logic [31:0] mul_result,
    output logic mul_stall
);
    // 这里只整理乘法模块的控制与结果选择；后续可直接替换为 IP 核实现。

    // --------------------
    // 乘法路径
    // --------------------
    logic signed [32:0] mul_src1_ext, mul_src2_ext;
    logic signed [65:0] mul_result_ext;
    logic [`MUL_CYCLE-1:0]         mul_valid_shift;
    logic               mul_start;
    logic               mul_done;
    logic               mul_busy;
    logic               mul_op_mul;

    // --------------------
    // 除法 / 取余路径
    // --------------------
    logic [31:0] div_src1, div_src2;
    logic [63:0] div_result;
    logic [63:0] div_result_reg;
    logic        div_0;
    logic        div_1;
    logic [1:0]  div_state;
    logic        div1_valid, div2_valid;
    logic        div_valid;
    logic        div_done;
    logic        div_start;
    logic        mul_op_div;

    assign mul_op_mul = mul_op[3] || mul_op[2];
    assign mul_op_div = mul_op[1] || mul_op[0];

    assign div_src1 = src1_signed && mul_src1[31] ? ~mul_src1 + 1'b1 : mul_src1;
    assign div_src2 = src2_signed && mul_src2[31] ? ~mul_src2 + 1'b1 : mul_src2;

    assign mul_src1_ext = src1_signed ? {mul_src1[31], mul_src1} : {1'b0, mul_src1};
    assign mul_src2_ext = src2_signed ? {mul_src2[31], mul_src2} : {1'b0, mul_src2};

    assign div_0 = (div_src2 == 32'b0);
    assign div_1 = src1_signed && src2_signed &&
                   (div_src1 == 32'h8000_0000) &&
                   (div_src2 == 32'hffff_ffff);

    assign mul_start = is_mul && mul_op_mul && !mul_busy;
    assign mul_done = mul_valid_shift[`MUL_CYCLE-1];

    assign div_start = is_multicycle && is_mul && mul_op_div &&
                       (div_state == 2'b00) && !div_0 && !div_1;
    assign div1_valid = div_start;
    assign div2_valid = div_start;
    assign div_done = div_valid || (div_state == 2'b10);

    assign mul_stall = is_mul && is_multicycle &&
                       ((mul_op_mul && !mul_done) ||
                        (mul_op_div && !div_done));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_valid_shift <= {`MUL_CYCLE{1'b0}};
            mul_busy <= 1'b0;
        end else if (mul_op_mul) begin
            mul_valid_shift <= {mul_valid_shift[`MUL_CYCLE-2:0], mul_start};

            if (mul_start) begin
                mul_busy <= 1'b1;
            end else if (mul_done) begin
                mul_busy <= 1'b0;
            end
        end else begin
            mul_valid_shift <= {`MUL_CYCLE{1'b0}};
            mul_busy <= 1'b0;
        end
    end

    always_comb begin
        unique case (1'b1)
            mul_op[3]: begin
                mul_result = mul_result_ext[31:0];
            end
            mul_op[2]: begin
                mul_result = mul_result_ext[63:32];
            end
            mul_op[1]: begin
                mul_result = (src1_signed && src2_signed && (mul_src1[31] ^ mul_src2[31]) && div_state[0]) ?
                             (~div_result[31:0] + 1'b1) :
                             div_result[31:0];
            end
            mul_op[0]: begin
                mul_result = (src1_signed && src2_signed && mul_src1[31] && div_state[0]) ?
                             (~div_result[63:32] + 1'b1) :
                             div_result[63:32];
            end
            default: begin
                mul_result = 32'b0;
            end
        endcase
    end

    // 当前为逻辑占位，后续直接替换成乘法 IP 核调用即可。
    assign mul_result_ext = mul_src1_ext * mul_src2_ext;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_state <= 2'b00;
        end else begin
            unique case (div_state)
                2'b00: begin
                    if (div_start) begin
                        div_state <= 2'b01;
                    end else if (is_multicycle && is_mul && mul_op_div && (div_0 || div_1)) begin
                        div_state <= 2'b10;
                    end else begin
                        div_state <= 2'b00;
                    end
                end
                2'b01: begin
                    if (div_valid) begin
                        div_state <= 2'b00;
                    end
                end
                2'b10: begin
                    div_state <= 2'b00;
                end
                default: begin
                    div_state <= 2'b00;
                end
            endcase
        end
    end

    div div_inst (
        .clk(clk),
        .rst_n(rst_n),
        .div_src1(div_src1),
        .div_src2(div_src2),
        .div1_valid(div1_valid),
        .div2_valid(div2_valid),
        .div_result(div_result_reg),
        .div_valid(div_valid)
    );

    assign div_result = div_0 ? {mul_src1, 32'hffff_ffff} :
                        div_1 ? {32'h0000_0000, 32'h8000_0000} :
                        div_result_reg;



endmodule