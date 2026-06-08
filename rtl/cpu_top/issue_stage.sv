`include "defines.svh"
module issue_stage (
    input logic clk,
    input logic rst_n,
    //来自IF阶段的数据0
    input logic fs_to_is_valid,
    output logic is_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1,
    //送往ID阶段的数据0
    output logic is_to_ds_valid,
    input logic ds_allowin,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus,
    //送往ID阶段的数据1
    output logic is_to_ds_valid1,
    input logic ds_allowin1,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1,
    //分支跳转与异常冲刷信号
    input logic br_taken,
    input logic exception_flag,
    output logic is_flush,
    output logic is_flush1
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_issue_inst0,
    output logic [31:0] debug_issue_pc0,
    output logic        debug_issue_valid0,
    output logic [31:0] debug_issue_inst1,
    output logic [31:0] debug_issue_pc1,
    output logic        debug_issue_valid1
    `endif
);

    typedef enum logic {
        ISSUE_IDLE,
        ISSUE_LANE0
    } issue_state_t;

    issue_state_t state;
    issue_state_t next_state;

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic       need_rs1;
        logic       need_rs2;
        logic       write_gpr;
        logic       is_simple_int;
        logic       is_load;
        logic       is_store;
        logic       is_branch_jmp;
    } issue_info_t;

    logic [`FS_DS_WIDTH-1:0] buf0;
    logic [`FS_DS_WIDTH-1:0] buf1;
    logic buf_valid0;
    logic buf_valid1;
    logic global_flush;
    logic lane0_fire;
    logic lane1_fire;
    logic can_pair;
    logic lane1_issue_class_ok;
    logic packet_accept;
    logic buffer_empty;
    logic buffer_single;
    logic dual_issue_ready;
    logic next_buf_valid0;
    logic next_buf_valid1;
    logic [`FS_DS_WIDTH-1:0] next_buf0;
    logic [`FS_DS_WIDTH-1:0] next_buf1;
    logic [31:0] buf_inst0;
    logic [31:0] buf_inst1;
    logic [31:0] buf_pc0;
    logic [31:0] buf_pc1;
    issue_info_t info0;
    issue_info_t info1;

    assign buf_inst0 = buf0[`FS_DS_WIDTH-1 -: 32];
    assign buf_inst1 = buf1[`FS_DS_WIDTH-1 -: 32];
    assign buf_pc0 = buf0[`FS_DS_WIDTH-33 -: 32];
    assign buf_pc1 = buf1[`FS_DS_WIDTH-33 -: 32];

    function automatic issue_info_t decode_issue_info(input logic [31:0] inst);
        issue_info_t info;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic is_op_imm;
        logic is_op_reg;
        logic is_lui;
        logic is_auipc;
        logic is_load;
        logic is_store;
        logic is_branch;
        logic is_jal;
        logic is_jalr;
        logic is_legal_op_imm;
        logic is_legal_op_reg;
        logic is_legal_load;
        logic is_legal_store;
        logic is_legal_branch;
        logic is_legal_jalr;

        begin
            opcode = inst[6:0];
            funct3 = inst[14:12];
            funct7 = inst[31:25];

            is_op_imm = (opcode == 7'b0010011);
            is_op_reg = (opcode == 7'b0110011);
            is_lui    = (opcode == 7'b0110111);
            is_auipc  = (opcode == 7'b0010111);
            is_load   = (opcode == 7'b0000011);
            is_store  = (opcode == 7'b0100011);
            is_branch = (opcode == 7'b1100011);
            is_jal    = (opcode == 7'b1101111);
            is_jalr   = (opcode == 7'b1100111);

            is_legal_op_imm = ((funct3 == 3'b000) || (funct3 == 3'b010) ||
                               (funct3 == 3'b011) || (funct3 == 3'b100) ||
                               (funct3 == 3'b110) || (funct3 == 3'b111) ||
                               ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
                               ((funct3 == 3'b101) &&
                                ((funct7 == 7'b0000000) || (funct7 == 7'b0100000))));
            is_legal_op_reg = (funct7 == 7'b0000000) ||
                              ((funct7 == 7'b0100000) &&
                               ((funct3 == 3'b000) || (funct3 == 3'b101)));
            is_legal_load = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                            (funct3 == 3'b010) || (funct3 == 3'b100) ||
                            (funct3 == 3'b101);
            is_legal_store = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                             (funct3 == 3'b010);
            is_legal_branch = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                              (funct3 == 3'b100) || (funct3 == 3'b101) ||
                              (funct3 == 3'b110) || (funct3 == 3'b111);
            is_legal_jalr = (funct3 == 3'b000);

            info = '0;
            info.rs1 = inst[19:15];
            info.rs2 = inst[24:20];
            info.rd  = inst[11:7];
            info.need_rs1 = is_op_imm || is_op_reg || is_load || is_store ||
                             is_branch || is_jalr;
            info.need_rs2 = is_op_reg || is_store || is_branch;
            info.write_gpr = is_op_imm || is_op_reg || is_lui || is_auipc ||
                             (is_load && is_legal_load) || is_jal ||
                             (is_jalr && is_legal_jalr);
            info.is_simple_int = (is_op_imm && is_legal_op_imm) ||
                                 (is_op_reg && is_legal_op_reg) ||
                                 is_lui || is_auipc;
            info.is_load = is_load && is_legal_load;
            info.is_store = is_store && is_legal_store;
            info.is_branch_jmp = (is_branch && is_legal_branch) || is_jal ||
                                 (is_jalr && is_legal_jalr);
            decode_issue_info = info;
        end
    endfunction

    assign global_flush = br_taken || exception_flag;
    assign is_flush  = global_flush;
    assign is_flush1 = global_flush;

    assign info0 = decode_issue_info(buf_inst0);
    assign info1 = decode_issue_info(buf_inst1);

    assign lane1_issue_class_ok = info1.is_simple_int || info1.is_load ||
                                  info1.is_store || info1.is_branch_jmp;
    assign can_pair = buf_valid0 && buf_valid1 &&
                      info0.is_simple_int &&
                      lane1_issue_class_ok &&
                      !(info0.write_gpr && (info0.rd != 5'b0) &&
                        ((info1.need_rs1 && (info1.rs1 == info0.rd)) ||
                         (info1.need_rs2 && (info1.rs2 == info0.rd)))) &&
                      !(info0.write_gpr && info1.write_gpr &&
                        (info0.rd != 5'b0) && (info0.rd == info1.rd));

    // IDLE may dual-issue safe pairs. Lane0 control-flow instructions remain
    // lane0-only because issue does not know the final branch direction.
    assign buffer_empty = !buf_valid0 && !buf_valid1;
    assign buffer_single = buf_valid0 && !buf_valid1;
    assign dual_issue_ready = (state == ISSUE_IDLE) && can_pair && ds_allowin && ds_allowin1;
    assign lane0_fire = buf_valid0 && ds_allowin;
    assign lane1_fire = global_flush ? (buf_valid1 && ds_allowin && ds_allowin1) :
                        dual_issue_ready;
    assign packet_accept = fs_to_is_valid && is_allowin && !global_flush;
    assign is_allowin = buffer_empty || (buffer_single && lane0_fire) || lane1_fire;

    assign is_to_ds_valid = lane0_fire;
    assign is_to_ds_valid1 = lane1_fire;
    assign is_to_ds_bus = buf0;
    assign is_to_ds_bus1 = buf1;

    always_comb begin
        next_buf0 = buf0;
        next_buf1 = buf1;
        next_buf_valid0 = buf_valid0;
        next_buf_valid1 = buf_valid1;

        if (lane1_fire) begin
            next_buf0 = '0;
            next_buf1 = '0;
            next_buf_valid0 = 1'b0;
            next_buf_valid1 = 1'b0;
        end else if (lane0_fire) begin
            next_buf0 = buf1;
            next_buf1 = '0;
            next_buf_valid0 = buf_valid1;
            next_buf_valid1 = 1'b0;
        end

        if (packet_accept) begin
            next_buf0 = fs_to_is_bus;
            next_buf1 = fs_to_is_bus1;
            next_buf_valid0 = 1'b1;
            next_buf_valid1 = 1'b1;
        end

        if (next_buf_valid0 && next_buf_valid1) begin
            next_state = ISSUE_IDLE;
        end else if (next_buf_valid0) begin
            next_state = ISSUE_LANE0;
        end else begin
            next_state = ISSUE_IDLE;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ISSUE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf0 <= '0;
            buf1 <= '0;
            buf_valid0 <= 1'b0;
            buf_valid1 <= 1'b0;
        end else begin
            buf0 <= next_buf0;
            buf1 <= next_buf1;
            buf_valid0 <= next_buf_valid0;
            buf_valid1 <= next_buf_valid1;
        end
    end

    `ifdef DEBUG_EN
    assign debug_issue_inst0 = buf_inst0;
    assign debug_issue_pc0 = buf_pc0;
    assign debug_issue_valid0 = buf_valid0;
    assign debug_issue_inst1 = buf_inst1;
    assign debug_issue_pc1 = buf_pc1;
    assign debug_issue_valid1 = buf_valid1;
    `endif

endmodule
