`include "defines.svh"

module skid_buffer #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  flush,

    // 上游握手接口 (Upstream)
    input  logic                  valid_in,
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic                  ready_out,

    // 下游握手接口 (Downstream)
    input  logic                  ready_in,
    output logic                  valid_out,
    output logic [DATA_WIDTH-1:0] data_out
);

    logic [DATA_WIDTH-1:0] data_reg;
    logic [DATA_WIDTH-1:0] skid_reg;

    // 状态定义:
    // 0: 空 (没有有效数据)
    // 1: 1个数据 (存储在 data_reg)
    // 2: 2个数据 (存储在 data_reg 和 skid_reg，其中 skid_reg 为旧数据)
    logic [1:0] state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 2'd0;
            data_reg <= '0;
            skid_reg <= '0;
        end else if (flush) begin
            state <= 2'd0;
            data_reg <= '0;
            skid_reg <= '0;
        end else begin
            case (state)
                2'd0: begin
                    if (valid_in) begin
                        state <= 2'd1;
                        data_reg <= data_in;
                    end
                end
                2'd1: begin
                    if (valid_in && ready_in) begin
                        // 下游能接收，上游也发新数据，保持状态1，更新data_reg
                        state <= 2'd1;
                        data_reg <= data_in;
                    end else if (valid_in && !ready_in) begin
                        // 下游不接收，上游发新数据，进入状态2，旧数据移入skid_reg，新数据放入data_reg
                        state <= 2'd2;
                        skid_reg <= data_reg;
                        data_reg <= data_in;
                    end else if (!valid_in && ready_in) begin
                        // 下游接收，上游没发新数据，进入空状态
                        state <= 2'd0;
                    end
                end
                2'd2: begin
                    if (ready_in) begin
                        // 在状态2，ready_out必为0，上游不能发新数据。
                        // 下游接收了最老的旧数据(skid_reg)，data_reg成为当前的唯一有效数据。
                        state <= 2'd1;
                    end
                end
                default: state <= 2'd0;
            endcase
        end
    end

    // ready_out 完全由状态寄存器决定，彻底截断了组合逻辑路径
    assign ready_out = (state != 2'd2);
    assign valid_out = (state != 2'd0);
    // 当状态为2时，skid_reg是最老的数据，应该先输出
    assign data_out  = (state == 2'd2) ? skid_reg : data_reg;

endmodule
