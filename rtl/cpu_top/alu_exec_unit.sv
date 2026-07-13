`include "defines.svh"

module alu_exec_unit (
    input  logic        start,
    input  logic        kill,
    input  logic [9:0]  op,
    input  logic [31:0] src1,
    input  logic [31:0] src2,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);

    assign busy = 1'b0;
    assign done = start && !kill;

    always_comb begin
        unique case (op)
            `ALU_OP_ADD:  result = src1 + src2;
            `ALU_OP_SUB:  result = src1 - src2;
            `ALU_OP_AND:  result = src1 & src2;
            `ALU_OP_OR:   result = src1 | src2;
            `ALU_OP_XOR:  result = src1 ^ src2;
            `ALU_OP_SLL:  result = src1 << src2[4:0];
            `ALU_OP_SRL:  result = src1 >> src2[4:0];
            `ALU_OP_SRA:  result = $signed(src1) >>> src2[4:0];
            `ALU_OP_SLT:  result = ($signed(src1) < $signed(src2)) ? 32'b1 : 32'b0;
            `ALU_OP_SLTU: result = (src1 < src2) ? 32'b1 : 32'b0;
            default:      result = 32'b0;
        endcase
    end

endmodule
