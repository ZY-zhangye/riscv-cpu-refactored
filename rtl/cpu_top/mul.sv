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
    output logic [31:0] mul_result,
    output logic mul_stall
);
    //暂时不实现乘法器，直接输出0
    assign mul_result = 32'b0;
    assign mul_stall = 1'b0;



endmodule