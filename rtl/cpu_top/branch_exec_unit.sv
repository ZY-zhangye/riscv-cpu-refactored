`include "defines.svh"

module branch_exec_unit (
    input  logic                       start,
    input  logic                       kill,
    input  logic [31:0]                pc,
    input  logic [31:0]                src1,
    input  logic [31:0]                src2,
    input  logic [31:0]                immediate,
    input  logic [31:0]                direct_target,
    input  logic [5:0]                 branch_opcode,
    input  logic                       is_jal,
    input  logic                       is_jalr,
    input  logic                       predicted_taken,
    input  logic [31:0]                predicted_target,
    output logic                       busy,
    output logic                       done,
    output logic                       taken,
    output logic [31:0]                target,
    output logic                       mispredict,
    output logic [31:0]                redirect_target
);

    logic is_beq;
    logic is_bne;
    logic is_blt;
    logic is_bge;
    logic is_bltu;
    logic is_bgeu;
    logic condition;

    assign is_beq  = branch_opcode[5];
    assign is_bne  = branch_opcode[4];
    assign is_blt  = branch_opcode[3];
    assign is_bge  = branch_opcode[2];
    assign is_bltu = branch_opcode[1];
    assign is_bgeu = branch_opcode[0];

    assign condition = (is_beq  && (src1 == src2)) ||
                       (is_bne  && (src1 != src2)) ||
                       (is_blt  && ($signed(src1) < $signed(src2))) ||
                       (is_bge  && ($signed(src1) >= $signed(src2))) ||
                       (is_bltu && (src1 < src2)) ||
                       (is_bgeu && (src1 >= src2));

    assign busy = 1'b0;
    assign done = start && !kill;
    assign taken = !kill && (is_jal || is_jalr || condition);
    assign target = is_jalr ? ((src1 + immediate) & 32'hffff_fffe) :
                              direct_target;
    assign mispredict = !kill && ((taken != predicted_taken) ||
                                  (taken && (target != predicted_target)));
    assign redirect_target = taken ? target : (pc + 32'd4);

endmodule
