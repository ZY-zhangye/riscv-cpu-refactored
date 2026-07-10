`include "defines.svh"

module issue_stage (
    input  logic clk,
    input  logic rst_n,

    input  logic fs_to_is_valid0,
    input  logic fs_to_is_valid1,
    input  logic [`FS_DS_WIDTH-1:0] fs_to_is_bus0,
    input  logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1,
    output logic is_allowin,

    output logic is_to_ds_valid0,
    output logic is_to_ds_valid1,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus0,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1,
    input  logic ds_bundle_allowin,

    input  logic br_redirect,
    input  logic exception_flag,
    output logic issue_flush,

    output logic dual_issue_event,
    output logic single_issue_event,
    output logic issue_raw_reject_event,
    output logic issue_waw_reject_event,
    output logic issue_struct_reject_event,
    output logic issue_lsu_pair_event,
    output logic issue_lane1_control_event
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_issue_inst0,
    output logic [31:0] debug_issue_pc0,
    output logic debug_issue_valid0,
    output logic [31:0] debug_issue_inst1,
    output logic [31:0] debug_issue_pc1,
    output logic debug_issue_valid1
    `endif
);

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic need_rs1;
        logic need_rs2;
        logic write_gpr;
        logic simple_int;
        logic lsu;
        logic control;
    } issue_info_t;

    logic [`FS_DS_WIDTH-1:0] buf0;
    logic [`FS_DS_WIDTH-1:0] buf1;
    logic buf_valid0;
    logic buf_valid1;
    logic [`FS_DS_WIDTH-1:0] next_buf0;
    logic [`FS_DS_WIDTH-1:0] next_buf1;
    logic next_buf_valid0;
    logic next_buf_valid1;

    logic [31:0] buf_inst0;
    logic [31:0] buf_inst1;
    logic [31:0] buf_pc0;
    logic [31:0] buf_pc1;
    issue_info_t info0;
    issue_info_t info1;
    logic global_flush;
    logic pair_raw;
    logic pair_waw;
    logic pair_class_ok;
    logic can_pair;
    logic lane0_fire;
    logic lane1_fire;
    logic buffer_will_empty;
    logic packet_accept;

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
        logic legal_op_imm;
        logic legal_op_reg;
        logic is_load;
        logic is_store;
        logic is_branch;
        logic is_jal;
        logic is_jalr;
        logic legal_load;
        logic legal_store;
        logic legal_branch;
        begin
            opcode = inst[6:0];
            funct3 = inst[14:12];
            funct7 = inst[31:25];
            is_op_imm = (opcode == 7'b0010011);
            is_op_reg = (opcode == 7'b0110011);
            is_lui = (opcode == 7'b0110111);
            is_auipc = (opcode == 7'b0010111);
            is_load = (opcode == 7'b0000011);
            is_store = (opcode == 7'b0100011);
            is_branch = (opcode == 7'b1100011);
            is_jal = (opcode == 7'b1101111);
            is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);

            legal_op_imm = (funct3 == 3'b000) ||
                           (funct3 == 3'b010) ||
                           (funct3 == 3'b011) ||
                           (funct3 == 3'b100) ||
                           (funct3 == 3'b110) ||
                           (funct3 == 3'b111) ||
                           ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
                           ((funct3 == 3'b101) &&
                            ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)));
            legal_op_reg = (funct7 == 7'b0000000) ||
                           ((funct7 == 7'b0100000) &&
                            ((funct3 == 3'b000) || (funct3 == 3'b101)));
            legal_load = is_load && ((funct3 == 3'b000) ||
                                     (funct3 == 3'b001) ||
                                     (funct3 == 3'b010) ||
                                     (funct3 == 3'b100) ||
                                     (funct3 == 3'b101));
            legal_store = is_store && ((funct3 == 3'b000) ||
                                       (funct3 == 3'b001) ||
                                       (funct3 == 3'b010));
            legal_branch = is_branch && ((funct3 == 3'b000) ||
                                         (funct3 == 3'b001) ||
                                         (funct3 == 3'b100) ||
                                         (funct3 == 3'b101) ||
                                         (funct3 == 3'b110) ||
                                         (funct3 == 3'b111));

            info = '0;
            info.rs1 = inst[19:15];
            info.rs2 = inst[24:20];
            info.rd = inst[11:7];
            info.need_rs1 = is_op_imm || is_op_reg || legal_load ||
                            legal_store || legal_branch || is_jalr;
            info.need_rs2 = is_op_reg || legal_store || legal_branch;
            info.write_gpr = (is_op_imm && legal_op_imm) ||
                             (is_op_reg && legal_op_reg) ||
                             is_lui || is_auipc || legal_load ||
                             is_jal || is_jalr;
            info.simple_int = (is_op_imm && legal_op_imm) ||
                              (is_op_reg && legal_op_reg) ||
                              is_lui || is_auipc;
            info.lsu = legal_load || legal_store;
            info.control = legal_branch || is_jal || is_jalr;
            decode_issue_info = info;
        end
    endfunction

    assign info0 = decode_issue_info(buf_inst0);
    assign info1 = decode_issue_info(buf_inst1);
    assign pair_raw = info0.write_gpr && (info0.rd != 5'b0) &&
                      ((info1.need_rs1 && (info1.rs1 == info0.rd)) ||
                       (info1.need_rs2 && (info1.rs2 == info0.rd)));
    assign pair_waw = info0.write_gpr && info1.write_gpr &&
                      (info0.rd != 5'b0) && (info0.rd == info1.rd);
    assign pair_class_ok = (info0.simple_int && info1.simple_int) ||
                           (info0.lsu && info1.simple_int) ||
                           (info0.simple_int && info1.lsu) ||
                           (info0.simple_int && info1.control);
    assign can_pair = buf_valid0 && buf_valid1 && pair_class_ok &&
                      !pair_raw && !pair_waw;

    assign global_flush = br_redirect || exception_flag;
    assign issue_flush = global_flush;

    assign is_to_ds_valid0 = buf_valid0 && !global_flush;
    assign is_to_ds_valid1 = can_pair && !global_flush;
    assign is_to_ds_bus0 = buf0;
    assign is_to_ds_bus1 = buf1;

    assign lane0_fire = is_to_ds_valid0 && ds_bundle_allowin;
    assign lane1_fire = is_to_ds_valid1 && ds_bundle_allowin;
    assign buffer_will_empty = !buf_valid0 ||
                               (lane0_fire && (!buf_valid1 || lane1_fire));
    assign is_allowin = global_flush || buffer_will_empty;
    assign packet_accept = fs_to_is_valid0 && is_allowin && !global_flush;

    assign dual_issue_event = lane1_fire;
    assign single_issue_event = lane0_fire && !lane1_fire;
    assign issue_raw_reject_event = single_issue_event && buf_valid1 && pair_raw;
    assign issue_waw_reject_event = single_issue_event && buf_valid1 && pair_waw;
    assign issue_struct_reject_event = single_issue_event && buf_valid1 &&
                                       !pair_class_ok;
    assign issue_lsu_pair_event = lane1_fire && (info0.lsu || info1.lsu);
    assign issue_lane1_control_event = lane1_fire && info1.control;

    always_comb begin
        next_buf0 = buf0;
        next_buf1 = buf1;
        next_buf_valid0 = buf_valid0;
        next_buf_valid1 = buf_valid1;

        if (global_flush) begin
            next_buf0 = '0;
            next_buf1 = '0;
            next_buf_valid0 = 1'b0;
            next_buf_valid1 = 1'b0;
        end else begin
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
                next_buf0 = fs_to_is_bus0;
                next_buf1 = fs_to_is_bus1;
                next_buf_valid0 = 1'b1;
                next_buf_valid1 = fs_to_is_valid1;
            end
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
    assign debug_issue_valid0 = is_to_ds_valid0;
    assign debug_issue_inst1 = buf_inst1;
    assign debug_issue_pc1 = buf_pc1;
    assign debug_issue_valid1 = is_to_ds_valid1;
    `endif

endmodule
