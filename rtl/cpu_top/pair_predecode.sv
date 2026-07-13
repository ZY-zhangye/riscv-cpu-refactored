module pair_predecode (
    input  logic [31:0] instruction,
    output logic        is_simple,
    output logic        is_control,
    output logic        is_lsu,
    output logic        is_muldiv,
    output logic        uses_rs1,
    output logic        uses_rs2,
    output logic        uses_rd
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic legal_load;
    logic legal_store;
    logic is_branch;
    logic is_jal;
    logic is_jalr;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    always_comb begin
        is_simple = 1'b0;
        unique case (opcode)
            7'b0110111,
            7'b0010111: is_simple = 1'b1; // LUI/AUIPC
            7'b0010011: begin
                unique case (funct3)
                    3'b001: is_simple = (funct7 == 7'b0000000);
                    3'b101: is_simple = (funct7 == 7'b0000000) ||
                                               (funct7 == 7'b0100000);
                    default: is_simple = 1'b1;
                endcase
            end
            7'b0110011: begin
                is_simple = (funct7 == 7'b0000000) ||
                            ((funct7 == 7'b0100000) &&
                             ((funct3 == 3'b000) || (funct3 == 3'b101)));
            end
            default: is_simple = 1'b0;
        endcase
    end

    assign is_branch = (opcode == 7'b1100011);
    assign is_jal = (opcode == 7'b1101111);
    assign is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);
    assign is_control = is_branch || is_jal || is_jalr;

    assign legal_load = (opcode == 7'b0000011) &&
                        ((funct3 == 3'b000) || (funct3 == 3'b001) ||
                         (funct3 == 3'b010) || (funct3 == 3'b100) ||
                         (funct3 == 3'b101));
    assign legal_store = (opcode == 7'b0100011) &&
                         ((funct3 == 3'b000) || (funct3 == 3'b001) ||
                          (funct3 == 3'b010));
    assign is_lsu = legal_load || legal_store;
    assign is_muldiv = (opcode == 7'b0110011) &&
                       (funct7 == 7'b0000001);

    assign uses_rs1 = (is_simple && ((opcode == 7'b0010011) ||
                                     (opcode == 7'b0110011))) ||
                      is_branch || is_jalr || is_lsu || is_muldiv;
    assign uses_rs2 = (is_simple && (opcode == 7'b0110011)) ||
                      is_branch || legal_store || is_muldiv;
    assign uses_rd = is_simple || is_jal || is_jalr || legal_load || is_muldiv;

endmodule
