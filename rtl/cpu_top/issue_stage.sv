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
    output logic issue_lane1_control_event,
    output logic issue_bitman_pair_event,
    output logic issue_cross_packet_pair_event,
    output logic issue_queue_full_event
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
        logic bitman;
    } issue_info_t;

    logic [`FS_DS_WIDTH-1:0] queue0;
    logic [`FS_DS_WIDTH-1:0] queue1;
    logic [`FS_DS_WIDTH-1:0] queue2;
    logic [`FS_DS_WIDTH-1:0] queue3;
    logic [`FS_DS_WIDTH-1:0] next_queue0;
    logic [`FS_DS_WIDTH-1:0] next_queue1;
    logic [`FS_DS_WIDTH-1:0] next_queue2;
    logic [`FS_DS_WIDTH-1:0] next_queue3;
    logic [2:0] queue_count;
    logic [2:0] next_queue_count;
    logic queue_tag0;
    logic queue_tag1;
    logic queue_tag2;
    logic queue_tag3;
    logic next_queue_tag0;
    logic next_queue_tag1;
    logic next_queue_tag2;
    logic next_queue_tag3;
    logic next_packet_tag;
    logic next_next_packet_tag;
    issue_info_t queue_info0;
    issue_info_t queue_info1;
    issue_info_t queue_info2;
    issue_info_t queue_info3;
    issue_info_t next_queue_info0;
    issue_info_t next_queue_info1;
    issue_info_t next_queue_info2;
    issue_info_t next_queue_info3;
    logic [`FS_DS_WIDTH-1:0] buf0;
    logic [`FS_DS_WIDTH-1:0] buf1;
    logic buf_valid0;
    logic buf_valid1;

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
    logic packet_accept;
    logic [2:0] consume_count;
    logic [2:0] incoming_count;
    logic [2:0] remaining_count;
    logic can_accept_one;
    logic can_accept_two;
    logic queue_full_event_now;

    assign buf0 = queue0;
    assign buf1 = queue1;
    assign buf_valid0 = (queue_count != 3'd0);
    assign buf_valid1 = (queue_count >= 3'd2);

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
        logic bitman_any;
        logic bitman_rs2;
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
            bitman_rs2 =
                (is_op_reg && (funct7 == 7'b0010000) &&
                 ((funct3 == 3'b010) || (funct3 == 3'b100) || (funct3 == 3'b110))) ||
                (is_op_reg && (funct7 == 7'b0100000) &&
                 ((funct3 == 3'b111) || (funct3 == 3'b110) || (funct3 == 3'b100))) ||
                (is_op_reg && (funct7 == 7'b0000101) &&
                 ((funct3 == 3'b100) || (funct3 == 3'b101) ||
                  (funct3 == 3'b110) || (funct3 == 3'b111))) ||
                (is_op_reg && (funct7 == 7'b0000100) &&
                 (((funct3 == 3'b100) && (inst[24:20] != 5'b00000)) ||
                  (funct3 == 3'b111))) ||
                (is_op_reg &&
                 (((funct7 == 7'b0100100) &&
                   ((funct3 == 3'b001) || (funct3 == 3'b101))) ||
                  ((funct7 == 7'b0110100) && (funct3 == 3'b001)) ||
                  ((funct7 == 7'b0010100) && (funct3 == 3'b001))));
            bitman_any = bitman_rs2 ||
                (is_op_imm && (inst[31:20] == 12'h604) && (funct3 == 3'b001)) ||
                (is_op_imm && (inst[31:20] == 12'h605) && (funct3 == 3'b001)) ||
                (is_op_reg && (funct7 == 7'b0000100) &&
                 (inst[24:20] == 5'b00000) && (funct3 == 3'b100)) ||
                (is_op_imm && (inst[31:20] == 12'h287) && (funct3 == 3'b101)) ||
                (is_op_imm && (inst[31:20] == 12'h698) && (funct3 == 3'b101)) ||
                (is_op_imm && (inst[31:20] == 12'h687) && (funct3 == 3'b101)) ||
                (is_op_imm && (funct7 == 7'b0000100) &&
                 (inst[24:20] == 5'b01111) &&
                 ((funct3 == 3'b001) || (funct3 == 3'b101))) ||
                (is_op_imm &&
                 (((funct7 == 7'b0100100) &&
                   ((funct3 == 3'b001) || (funct3 == 3'b101))) ||
                  ((funct7 == 7'b0110100) && (funct3 == 3'b001)) ||
                  ((funct7 == 7'b0010100) && (funct3 == 3'b001))));

            info = '0;
            info.rs1 = inst[19:15];
            info.rs2 = inst[24:20];
            info.rd = inst[11:7];
            info.need_rs1 = is_op_imm || is_op_reg || legal_load ||
                            legal_store || legal_branch || is_jalr || bitman_any;
            info.need_rs2 = is_op_reg || legal_store || legal_branch || bitman_rs2;
            info.write_gpr = (is_op_imm && legal_op_imm) ||
                             (is_op_reg && legal_op_reg) ||
                             is_lui || is_auipc || legal_load ||
                             is_jal || is_jalr || bitman_any;
            info.simple_int = (is_op_imm && legal_op_imm) ||
                              (is_op_reg && legal_op_reg) ||
                              is_lui || is_auipc || bitman_any;
            info.lsu = legal_load || legal_store;
            info.control = legal_branch || is_jal || is_jalr;
            info.bitman = bitman_any;
            decode_issue_info = info;
        end
    endfunction

    // 最终issue选择只读取入队时锁存的轻量预译码，避免重复穿过完整指令识别逻辑。
    assign info0 = queue_info0;
    assign info1 = queue_info1;
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
    assign consume_count = lane1_fire ? 3'd2 : lane0_fire ? 3'd1 : 3'd0;
    assign incoming_count = fs_to_is_valid0 ?
                            (fs_to_is_valid1 ? 3'd2 : 3'd1) : 3'd0;
    assign remaining_count = queue_count - consume_count;
    // 深度固定为4，显式容量判断避免在EX反压到IF路径上推导减法/比较进位链。
    always_comb begin
        can_accept_one = 1'b0;
        can_accept_two = 1'b0;
        unique case (queue_count)
            3'd0, 3'd1, 3'd2: begin
                can_accept_one = 1'b1;
                can_accept_two = 1'b1;
            end
            3'd3: begin
                can_accept_one = 1'b1;
                can_accept_two = (consume_count != 3'd0);
            end
            3'd4: begin
                can_accept_one = (consume_count != 3'd0);
                can_accept_two = (consume_count == 3'd2);
            end
            default: ;
        endcase
    end
    // IF当前尚无有效packet时为下一次双字返回预留两个槽位。
    assign is_allowin = global_flush ||
                        ((!fs_to_is_valid0 || fs_to_is_valid1) ?
                         can_accept_two : can_accept_one);
    assign packet_accept = fs_to_is_valid0 && is_allowin && !global_flush;

    assign dual_issue_event = lane1_fire;
    assign single_issue_event = lane0_fire && !lane1_fire;
    assign issue_raw_reject_event = single_issue_event && buf_valid1 && pair_raw;
    assign issue_waw_reject_event = single_issue_event && buf_valid1 && pair_waw;
    assign issue_struct_reject_event = single_issue_event && buf_valid1 &&
                                       !pair_class_ok;
    assign issue_lsu_pair_event = lane1_fire && (info0.lsu || info1.lsu);
    assign issue_lane1_control_event = lane1_fire && info1.control;
    assign issue_bitman_pair_event = lane1_fire && (info0.bitman || info1.bitman);
    assign issue_cross_packet_pair_event = lane1_fire && (queue_tag0 != queue_tag1);
    assign queue_full_event_now = fs_to_is_valid0 && !is_allowin && !global_flush;

    always_comb begin
        next_queue0 = queue0;
        next_queue1 = queue1;
        next_queue2 = queue2;
        next_queue3 = queue3;
        next_queue_tag0 = queue_tag0;
        next_queue_tag1 = queue_tag1;
        next_queue_tag2 = queue_tag2;
        next_queue_tag3 = queue_tag3;
        next_queue_info0 = queue_info0;
        next_queue_info1 = queue_info1;
        next_queue_info2 = queue_info2;
        next_queue_info3 = queue_info3;
        next_queue_count = queue_count;
        next_next_packet_tag = next_packet_tag;

        if (global_flush) begin
            // payload、预译码和tag在count=0后均为无效数据，不必由EX redirect
            // 高扇出清零；后续有效入队会按槽位自然覆盖。
            next_queue_count = 3'd0;
            next_next_packet_tag = 1'b0;
        end else begin
            unique case (consume_count)
                3'd1: begin
                    next_queue0 = queue1;
                    next_queue1 = queue2;
                    next_queue2 = queue3;
                    next_queue3 = '0;
                    next_queue_tag0 = queue_tag1;
                    next_queue_tag1 = queue_tag2;
                    next_queue_tag2 = queue_tag3;
                    next_queue_tag3 = 1'b0;
                    next_queue_info0 = queue_info1;
                    next_queue_info1 = queue_info2;
                    next_queue_info2 = queue_info3;
                    next_queue_info3 = '0;
                end
                3'd2: begin
                    next_queue0 = queue2;
                    next_queue1 = queue3;
                    next_queue2 = '0;
                    next_queue3 = '0;
                    next_queue_tag0 = queue_tag2;
                    next_queue_tag1 = queue_tag3;
                    next_queue_tag2 = 1'b0;
                    next_queue_tag3 = 1'b0;
                    next_queue_info0 = queue_info2;
                    next_queue_info1 = queue_info3;
                    next_queue_info2 = '0;
                    next_queue_info3 = '0;
                end
                default: ;
            endcase
            next_queue_count = remaining_count;

            if (packet_accept) begin
                unique case (remaining_count)
                    3'd0: begin
                        next_queue0 = fs_to_is_bus0;
                        next_queue_tag0 = next_packet_tag;
                        next_queue_info0 = decode_issue_info(
                            fs_to_is_bus0[`FS_DS_WIDTH-1 -: 32]);
                        if (fs_to_is_valid1) begin
                            next_queue1 = fs_to_is_bus1;
                            next_queue_tag1 = next_packet_tag;
                            next_queue_info1 = decode_issue_info(
                                fs_to_is_bus1[`FS_DS_WIDTH-1 -: 32]);
                        end
                    end
                    3'd1: begin
                        next_queue1 = fs_to_is_bus0;
                        next_queue_tag1 = next_packet_tag;
                        next_queue_info1 = decode_issue_info(
                            fs_to_is_bus0[`FS_DS_WIDTH-1 -: 32]);
                        if (fs_to_is_valid1) begin
                            next_queue2 = fs_to_is_bus1;
                            next_queue_tag2 = next_packet_tag;
                            next_queue_info2 = decode_issue_info(
                                fs_to_is_bus1[`FS_DS_WIDTH-1 -: 32]);
                        end
                    end
                    3'd2: begin
                        next_queue2 = fs_to_is_bus0;
                        next_queue_tag2 = next_packet_tag;
                        next_queue_info2 = decode_issue_info(
                            fs_to_is_bus0[`FS_DS_WIDTH-1 -: 32]);
                        if (fs_to_is_valid1) begin
                            next_queue3 = fs_to_is_bus1;
                            next_queue_tag3 = next_packet_tag;
                            next_queue_info3 = decode_issue_info(
                                fs_to_is_bus1[`FS_DS_WIDTH-1 -: 32]);
                        end
                    end
                    default: begin
                        next_queue3 = fs_to_is_bus0;
                        next_queue_tag3 = next_packet_tag;
                        next_queue_info3 = decode_issue_info(
                            fs_to_is_bus0[`FS_DS_WIDTH-1 -: 32]);
                    end
                endcase
                next_queue_count = remaining_count + incoming_count;
                next_next_packet_tag = ~next_packet_tag;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            queue0 <= '0;
            queue1 <= '0;
            queue2 <= '0;
            queue3 <= '0;
            queue_tag0 <= 1'b0;
            queue_tag1 <= 1'b0;
            queue_tag2 <= 1'b0;
            queue_tag3 <= 1'b0;
            queue_info0 <= '0;
            queue_info1 <= '0;
            queue_info2 <= '0;
            queue_info3 <= '0;
            queue_count <= 3'd0;
            next_packet_tag <= 1'b0;
            issue_queue_full_event <= 1'b0;
        end else begin
            queue0 <= next_queue0;
            queue1 <= next_queue1;
            queue2 <= next_queue2;
            queue3 <= next_queue3;
            queue_tag0 <= next_queue_tag0;
            queue_tag1 <= next_queue_tag1;
            queue_tag2 <= next_queue_tag2;
            queue_tag3 <= next_queue_tag3;
            queue_info0 <= next_queue_info0;
            queue_info1 <= next_queue_info1;
            queue_info2 <= next_queue_info2;
            queue_info3 <= next_queue_info3;
            queue_count <= next_queue_count;
            next_packet_tag <= next_next_packet_tag;
            // 性能观测事件延迟一拍，切断issue/EX反压到CSR计数器的长布线路径。
            issue_queue_full_event <= queue_full_event_now;
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
