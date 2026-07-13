`include "defines.svh"

module simple_alu_exec_unit (
    input  logic        start,
    input  logic        kill,
    input  logic [31:0] instruction,
    input  logic [31:0] pc,
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [31:0] immediate_i;
    logic [9:0] alu_op;
    logic [31:0] alu_src1;
    logic [31:0] alu_src2;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];
    assign immediate_i = {{20{instruction[31]}}, instruction[31:20]};

    always_comb begin
        alu_op = `ALU_OP_ADD;
        alu_src1 = rs1;
        alu_src2 = rs2;
        unique case (opcode)
            7'b0110111: begin
                alu_src1 = 32'b0;
                alu_src2 = {instruction[31:12], 12'b0};
            end
            7'b0010111: begin
                alu_src1 = pc;
                alu_src2 = {instruction[31:12], 12'b0};
            end
            7'b0010011: begin
                alu_src2 = immediate_i;
                unique case (funct3)
                    3'b000: alu_op = `ALU_OP_ADD;
                    3'b010: alu_op = `ALU_OP_SLT;
                    3'b011: alu_op = `ALU_OP_SLTU;
                    3'b100: alu_op = `ALU_OP_XOR;
                    3'b110: alu_op = `ALU_OP_OR;
                    3'b111: alu_op = `ALU_OP_AND;
                    3'b001: begin
                        alu_op = `ALU_OP_SLL;
                        alu_src2 = {27'b0, instruction[24:20]};
                    end
                    3'b101: begin
                        alu_op = (funct7 == 7'b0100000) ?
                                 `ALU_OP_SRA : `ALU_OP_SRL;
                        alu_src2 = {27'b0, instruction[24:20]};
                    end
                    default: alu_op = `ALU_OP_ADD;
                endcase
            end
            7'b0110011: begin
                unique case (funct3)
                    3'b000: alu_op = funct7[5] ? `ALU_OP_SUB : `ALU_OP_ADD;
                    3'b001: alu_op = `ALU_OP_SLL;
                    3'b010: alu_op = `ALU_OP_SLT;
                    3'b011: alu_op = `ALU_OP_SLTU;
                    3'b100: alu_op = `ALU_OP_XOR;
                    3'b101: alu_op = (funct7 == 7'b0100000) ?
                                         `ALU_OP_SRA : `ALU_OP_SRL;
                    3'b110: alu_op = `ALU_OP_OR;
                    3'b111: alu_op = `ALU_OP_AND;
                    default: alu_op = `ALU_OP_ADD;
                endcase
            end
            default: begin
                alu_op = `ALU_OP_ADD;
                alu_src1 = 32'b0;
                alu_src2 = 32'b0;
            end
        endcase
    end

    alu_exec_unit u_alu (
        .start(start),
        .kill(kill),
        .op(alu_op),
        .src1(alu_src1),
        .src2(alu_src2),
        .busy(busy),
        .done(done),
        .result(result)
    );

endmodule
