`include "defines.svh"
module issue_stage (
    input logic clk,
    input logic rst_n,
    //来自IF阶段的数据0
    input logic fs_to_is_valid,
    output logic is_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus,
    //送往ID阶段的数据0
    output logic is_to_ds_valid,
    input logic ds_allowin,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus,
    //来自IF阶段的数据1
    input logic fs_to_is_valid1,
    output logic is_allowin1,
    input logic [`FS_DS_WIDTH-1:0] fs_to_is_bus1,
    //送往ID阶段的数据1
    output logic is_to_ds_valid1,
    input logic ds_allowin1,
    output logic [`FS_DS_WIDTH-1:0] is_to_ds_bus1,
    //分支跳转与异常冲刷信号
    input logic br_taken,
    input logic exception_flag,
    output logic is_flush,
    output logic is_flush1
);

    typedef struct packed {
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic       need_rs1;
        logic       need_rs2;
        logic       write_gpr;
        logic       is_load;
        logic       is_store;
        logic       is_branch;
        logic       is_jump;
        logic       is_system;
        logic       is_fpu;
        logic       is_muldiv;
        logic       is_fence;
        logic       is_serial;
    } issue_info_t;

    logic hold_valid;
    logic [`FS_DS_WIDTH-1:0] hold_bus;

    logic [`FS_DS_WIDTH-1:0] issue_bus0;
    logic [`FS_DS_WIDTH-1:0] issue_bus1;
    logic issue_valid0;
    logic issue_valid1;
    logic global_flush;
    logic flush_pending;
    logic flush_effective;
    logic issue_accept;

    assign global_flush = br_taken || exception_flag;
    assign flush_effective = global_flush || flush_pending;

    assign issue_bus0 = hold_valid ? hold_bus : fs_to_is_bus;
    assign issue_bus1 = hold_valid ? fs_to_is_bus : fs_to_is_bus1;
    assign issue_valid0 = hold_valid || fs_to_is_valid;
    assign issue_valid1 = hold_valid ? fs_to_is_valid : fs_to_is_valid1;

    logic [31:0] issue_inst0;
    logic [31:0] issue_inst1;
    logic [31:0] issue_pc0;
    logic [31:0] issue_pc1;
    logic issue_bp_taken0;
    logic issue_bp_taken1;
    logic [31:0] issue_bp_target0;
    logic [31:0] issue_bp_target1;

    assign {issue_inst0, issue_pc0, issue_bp_taken0, issue_bp_target0} = issue_bus0;
    assign {issue_inst1, issue_pc1, issue_bp_taken1, issue_bp_target1} = issue_bus1;

    function automatic issue_info_t decode_issue_info(input logic [31:0] inst);
        issue_info_t info;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic is_load;
        logic is_store;
        logic is_branch;
        logic is_jal;
        logic is_jalr;
        logic is_op_imm;
        logic is_op_reg;
        logic is_lui;
        logic is_auipc;
        logic is_system;
        logic is_fence;
        logic is_fload;
        logic is_fstore;
        logic is_fpu_op;
        logic is_fmadd;
        logic is_fmsub;
        logic is_fnmsub;
        logic is_fnmadd;
        logic is_muldiv;

        begin
            opcode = inst[6:0];
            funct3 = inst[14:12];
            funct7 = inst[31:25];

            is_load   = (opcode == 7'b0000011);
            is_store  = (opcode == 7'b0100011);
            is_branch = (opcode == 7'b1100011);
            is_jal    = (opcode == 7'b1101111);
            is_jalr   = (opcode == 7'b1100111);
            is_op_imm = (opcode == 7'b0010011);
            is_op_reg = (opcode == 7'b0110011);
            is_lui    = (opcode == 7'b0110111);
            is_auipc  = (opcode == 7'b0010111);
            is_system = (opcode == 7'b1110011);
            is_fence  = (opcode == 7'b0001111);
            is_fload  = (opcode == 7'b0000111);
            is_fstore = (opcode == 7'b0100111);
            is_fpu_op = (opcode == 7'b1010011);
            is_fmadd  = (opcode == 7'b1000011);
            is_fmsub  = (opcode == 7'b1000111);
            is_fnmsub = (opcode == 7'b1001011);
            is_fnmadd = (opcode == 7'b1001111);
            is_muldiv = is_op_reg && (funct7 == 7'b0000001);

            info = '0;
            info.rs1 = inst[19:15];
            info.rs2 = inst[24:20];
            info.rd  = inst[11:7];
            info.is_load = is_load || is_fload;
            info.is_store = is_store || is_fstore;
            info.is_branch = is_branch;
            info.is_jump = is_jal || is_jalr;
            info.is_system = is_system;
            info.is_fpu = is_fload || is_fstore || is_fpu_op ||
                          is_fmadd || is_fmsub || is_fnmsub || is_fnmadd;
            info.is_muldiv = is_muldiv;
            info.is_fence = is_fence;

            info.need_rs1 = is_op_reg || is_op_imm || is_load || is_store ||
                            is_branch || is_jalr || is_fload || is_fstore ||
                            is_fpu_op || is_fmadd || is_fmsub || is_fnmsub ||
                            is_fnmadd ||
                            (is_system &&
                             ((funct3 == 3'b001) ||
                              (funct3 == 3'b010) ||
                              (funct3 == 3'b011)));
            info.need_rs2 = is_op_reg || is_store || is_branch || is_fstore ||
                            is_fpu_op || is_fmadd || is_fmsub || is_fnmsub ||
                            is_fnmadd;
            info.write_gpr = is_op_imm || is_op_reg || is_lui || is_auipc ||
                             is_load || is_jal || is_jalr ||
                             (is_system && (funct3 != 3'b000));

            info.is_serial = info.is_load || info.is_store ||
                             info.is_branch || info.is_jump ||
                             info.is_system || info.is_fpu ||
                             info.is_muldiv || info.is_fence;
            decode_issue_info = info;
        end
    endfunction

    issue_info_t info0;
    issue_info_t info1;
    logic raw01;
    logic waw01;
    logic structural_conflict;
    logic can_issue_lane1;
    logic lane1_fire;

    assign info0 = decode_issue_info(issue_inst0);
    assign info1 = decode_issue_info(issue_inst1);

    assign raw01 = info0.write_gpr && (info0.rd != 5'b0) &&
                   ((info1.need_rs1 && (info1.rs1 == info0.rd)) ||
                    (info1.need_rs2 && (info1.rs2 == info0.rd)));
    assign waw01 = info0.write_gpr && info1.write_gpr &&
                   (info0.rd != 5'b0) && (info0.rd == info1.rd);

    // 最小策略：两条执行线保持完整，但遇到会破坏顺序或共享资源的组合时，
    // issue 只发 lane0，并把 lane1 候选保存在 hold 槽中下一拍继续发。
    assign structural_conflict = info0.is_serial || info1.is_serial;
    assign can_issue_lane1 = issue_valid0 && issue_valid1 &&
                             !raw01 && !waw01 && !structural_conflict;
    assign lane1_fire = is_to_ds_valid1 && ds_allowin1;

    assign issue_accept = (fs_to_is_valid && is_allowin) ||
                          (fs_to_is_valid1 && is_allowin1);

    assign is_to_ds_valid = issue_valid0 && !flush_effective;
    assign is_to_ds_bus = issue_bus0;

    assign is_to_ds_valid1 = issue_valid1 && can_issue_lane1 && !flush_effective;
    assign is_to_ds_bus1 = issue_bus1;

    // flush 是“该指令应被丢弃”的标签，后级流水会自行屏蔽副作用。
    assign is_flush = flush_effective;
    assign is_flush1 = flush_effective;

    // hold_valid=1 时，本拍已经有一条老指令等待 lane0，只额外接收 IF lane0。
    // hold_valid=0 时，可以接收 IF lane0/lane1；若 lane1 不能同拍发射，则存入 hold。
    assign is_allowin = ds_allowin;
    assign is_allowin1 = ds_allowin && !hold_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_pending <= 1'b0;
        end else if (global_flush) begin
            flush_pending <= 1'b1;
        end else if (issue_accept) begin
            flush_pending <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_valid <= 1'b0;
            hold_bus <= '0;
        end else if (flush_effective) begin
            hold_valid <= 1'b0;
            hold_bus <= '0;
        end else if (ds_allowin) begin
            if (hold_valid) begin
                if (lane1_fire) begin
                    hold_valid <= 1'b0;
                    hold_bus <= '0;
                end else if (fs_to_is_valid) begin
                    hold_valid <= 1'b1;
                    hold_bus <= fs_to_is_bus;
                end else begin
                    hold_valid <= 1'b0;
                    hold_bus <= '0;
                end
            end else begin
                if (fs_to_is_valid && fs_to_is_valid1 && !lane1_fire) begin
                    hold_valid <= 1'b1;
                    hold_bus <= fs_to_is_bus1;
                end else begin
                    hold_valid <= 1'b0;
                    hold_bus <= '0;
                end
            end
        end
    end

endmodule
