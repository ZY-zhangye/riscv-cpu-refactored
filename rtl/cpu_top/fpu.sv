`include "defines.svh"
module fpu (
    input logic clk,
    input logic rst_n,
    input logic is_fpu,
    input logic is_multicycle,
    input logic [31:0] fpu_src1,
    input logic [31:0] fpu_src2,
    input logic [31:0] fpu_src3,
    input logic [25:0] fpu_op,
    input logic [2:0] rm,
    output logic [31:0] fpu_result,
    output logic fpu_stall
);

    //暂时不实现FPU，直接输出0
    assign fpu_result = 32'b0;
    assign fpu_stall = 1'b0;



endmodule