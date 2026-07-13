`include "defines.svh"

module dual_alu_pipeline (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           redirect,
    input  logic                           launch_valid,
    input  logic [`ISSUE_BUNDLE_WIDTH-1:0] launch_bundle,
    output logic                           launch_ready,
    output logic                           busy,
    output logic                           rf_read_en,
    output logic [4:0]                     rf_raddr0,
    output logic [4:0]                     rf_raddr1,
    output logic [4:0]                     rf_raddr2,
    output logic [4:0]                     rf_raddr3,
    input  logic [31:0]                    rf_rdata0,
    input  logic [31:0]                    rf_rdata1,
    input  logic [31:0]                    rf_rdata2,
    input  logic [31:0]                    rf_rdata3,
    output logic [1:0]                     commit_valid,
    output logic [1:0]                     commit_wen,
    output logic [4:0]                     commit_waddr0,
    output logic [4:0]                     commit_waddr1,
    output logic [31:0]                    commit_wdata0,
    output logic [31:0]                    commit_wdata1,
    output logic [1:0]                     retire_count,
    output logic                           dependency_event,
    output logic                           pending_stall_event,
    output logic [31:0]                    commit_pc0,
    output logic [31:0]                    commit_pc1,
    output logic [31:0]                    commit_inst0,
    output logic [31:0]                    commit_inst1,
    output logic [`FETCH_AGE_WIDTH-1:0]    commit_age0,
    output logic [`FETCH_AGE_WIDTH-1:0]    commit_age1,
    output logic [`FETCH_EPOCH_WIDTH-1:0]  commit_epoch0,
    output logic [`FETCH_EPOCH_WIDTH-1:0]  commit_epoch1
);

    logic launch_lane1_valid;
    logic launch_lane0_valid;
    logic [`FETCH_UOP_WIDTH-1:0] launch_uop1;
    logic [`FETCH_UOP_WIDTH-1:0] launch_uop0;
    logic [`FETCH_EPOCH_WIDTH-1:0] launch_epoch0;
    logic [`FETCH_AGE_WIDTH-1:0] launch_age0;
    logic [31:0] launch_inst0;
    logic [31:0] launch_pc0;
    logic launch_pred_taken0;
    logic [31:0] launch_pred_target0;
    logic [`BP_TYPE_WIDTH-1:0] launch_pred_type0;
    logic launch_btb_hit0;
    logic launch_ras_valid0;
    logic [31:0] launch_ras_target0;
    logic [`FETCH_EPOCH_WIDTH-1:0] launch_epoch1;
    logic [`FETCH_AGE_WIDTH-1:0] launch_age1;
    logic [31:0] launch_inst1;
    logic [31:0] launch_pc1;
    logic launch_pred_taken1;
    logic [31:0] launch_pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] launch_pred_type1;
    logic launch_btb_hit1;
    logic launch_ras_valid1;
    logic [31:0] launch_ras_target1;

    logic idex_valid;
    logic idex_lane0_valid;
    logic idex_lane1_valid;
    logic [`FETCH_EPOCH_WIDTH-1:0] idex_epoch0;
    logic [`FETCH_EPOCH_WIDTH-1:0] idex_epoch1;
    logic [`FETCH_AGE_WIDTH-1:0] idex_age0;
    logic [`FETCH_AGE_WIDTH-1:0] idex_age1;
    logic [31:0] idex_inst0;
    logic [31:0] idex_inst1;
    logic [31:0] idex_pc0;
    logic [31:0] idex_pc1;
    logic [4:0] idex_rd0;
    logic [4:0] idex_rd1;

    logic launch_uses_rs1_0;
    logic launch_uses_rs2_0;
    logic launch_uses_rs1_1;
    logic launch_uses_rs2_1;
    logic [19:0] consumer_rs_flat;
    logic [3:0] consumer_uses;
    logic [5:0] producer_valid;
    logic [5:0] producer_kill;
    logic [5:0] producer_pending;
    logic [5:0] producer_result_valid;
    logic [29:0] producer_dest_flat;
    logic scoreboard_dependency;
    logic scoreboard_stall;
    logic [11:0] scoreboard_forward_sel;
    logic launch_fire;

    assign {launch_lane1_valid, launch_lane0_valid,
            launch_uop1, launch_uop0} = launch_bundle;
    assign {launch_epoch0, launch_age0, launch_inst0, launch_pc0,
            launch_pred_taken0, launch_pred_target0, launch_pred_type0,
            launch_btb_hit0, launch_ras_valid0,
            launch_ras_target0} = launch_uop0;
    assign {launch_epoch1, launch_age1, launch_inst1, launch_pc1,
            launch_pred_taken1, launch_pred_target1, launch_pred_type1,
            launch_btb_hit1, launch_ras_valid1,
            launch_ras_target1} = launch_uop1;

    function automatic logic instruction_uses_rs1(input logic [31:0] inst);
        instruction_uses_rs1 = (inst[6:0] == 7'b0010011) ||
                               (inst[6:0] == 7'b0110011);
    endfunction

    function automatic logic instruction_uses_rs2(input logic [31:0] inst);
        instruction_uses_rs2 = (inst[6:0] == 7'b0110011);
    endfunction

    function automatic logic [31:0] alu_result(
        input logic [31:0] inst,
        input logic [31:0] pc,
        input logic [31:0] rs1,
        input logic [31:0] rs2
    );
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic [31:0] imm_i;
        begin
            opcode = inst[6:0];
            funct3 = inst[14:12];
            funct7 = inst[31:25];
            imm_i = {{20{inst[31]}}, inst[31:20]};
            case (opcode)
                7'b0110111: alu_result = {inst[31:12], 12'b0};
                7'b0010111: alu_result = pc + {inst[31:12], 12'b0};
                7'b0010011: begin
                    case (funct3)
                        3'b000: alu_result = rs1 + imm_i;
                        3'b010: alu_result = ($signed(rs1) < $signed(imm_i));
                        3'b011: alu_result = (rs1 < imm_i);
                        3'b100: alu_result = rs1 ^ imm_i;
                        3'b110: alu_result = rs1 | imm_i;
                        3'b111: alu_result = rs1 & imm_i;
                        3'b001: alu_result = rs1 << inst[24:20];
                        3'b101: begin
                            if (funct7 == 7'b0100000) begin
                                alu_result = $signed(rs1) >>> inst[24:20];
                            end else begin
                                alu_result = rs1 >> inst[24:20];
                            end
                        end
                        default: alu_result = 32'b0;
                    endcase
                end
                7'b0110011: begin
                    case (funct3)
                        3'b000: alu_result = funct7[5] ? rs1 - rs2 : rs1 + rs2;
                        3'b001: alu_result = rs1 << rs2[4:0];
                        3'b010: alu_result = ($signed(rs1) < $signed(rs2));
                        3'b011: alu_result = (rs1 < rs2);
                        3'b100: alu_result = rs1 ^ rs2;
                        3'b101: begin
                            if (funct7 == 7'b0100000) begin
                                alu_result = $signed(rs1) >>> rs2[4:0];
                            end else begin
                                alu_result = rs1 >> rs2[4:0];
                            end
                        end
                        3'b110: alu_result = rs1 | rs2;
                        3'b111: alu_result = rs1 & rs2;
                        default: alu_result = 32'b0;
                    endcase
                end
                default: alu_result = 32'b0;
            endcase
        end
    endfunction

    assign launch_uses_rs1_0 = instruction_uses_rs1(launch_inst0);
    assign launch_uses_rs2_0 = instruction_uses_rs2(launch_inst0);
    assign launch_uses_rs1_1 = instruction_uses_rs1(launch_inst1);
    assign launch_uses_rs2_1 = instruction_uses_rs2(launch_inst1);
    assign rf_raddr0 = launch_inst0[19:15];
    assign rf_raddr1 = launch_inst0[24:20];
    assign rf_raddr2 = launch_inst1[19:15];
    assign rf_raddr3 = launch_inst1[24:20];
    assign consumer_rs_flat = {rf_raddr3, rf_raddr2, rf_raddr1, rf_raddr0};
    assign consumer_uses = {launch_uses_rs2_1, launch_uses_rs1_1,
                            launch_uses_rs2_0, launch_uses_rs1_0};

    // Slot priority: EX lane1, EX lane0, then reserved MEM/WB lane slots.
    assign producer_valid = {4'b0,
                             idex_valid && idex_lane0_valid && (idex_rd0 != 0),
                             idex_valid && idex_lane1_valid && (idex_rd1 != 0)};
    assign producer_kill = 6'b0;
    assign producer_pending = 6'b0;
    assign producer_result_valid = producer_valid;
    assign producer_dest_flat = {20'b0, idex_rd0, idex_rd1};

    dual_scoreboard u_scoreboard (
        .consumer_valid(launch_valid),
        .consumer_uses(consumer_uses),
        .consumer_rs_flat(consumer_rs_flat),
        .producer_valid(producer_valid),
        .producer_kill(producer_kill),
        .producer_pending(producer_pending),
        .producer_result_valid(producer_result_valid),
        .producer_dest_flat(producer_dest_flat),
        .dependency(scoreboard_dependency),
        .stall(scoreboard_stall),
        .forward_sel_flat(scoreboard_forward_sel)
    );

    assign launch_ready = !redirect && !scoreboard_stall;
    assign launch_fire = launch_valid && launch_ready;
    assign rf_read_en = launch_fire;
    assign busy = idex_valid;
    assign dependency_event = launch_valid && scoreboard_dependency;
    assign pending_stall_event = launch_valid && scoreboard_stall;

    always_ff @(posedge clk) begin
        if (!rst_n || redirect) begin
            idex_valid <= 1'b0;
            idex_lane0_valid <= 1'b0;
            idex_lane1_valid <= 1'b0;
            idex_epoch0 <= '0;
            idex_epoch1 <= '0;
            idex_age0 <= '0;
            idex_age1 <= '0;
            idex_inst0 <= '0;
            idex_inst1 <= '0;
            idex_pc0 <= '0;
            idex_pc1 <= '0;
            idex_rd0 <= '0;
            idex_rd1 <= '0;
        end else begin
            idex_valid <= launch_fire;
            if (launch_fire) begin
                idex_lane0_valid <= launch_lane0_valid;
                idex_lane1_valid <= launch_lane1_valid;
                idex_epoch0 <= launch_epoch0;
                idex_epoch1 <= launch_epoch1;
                idex_age0 <= launch_age0;
                idex_age1 <= launch_age1;
                idex_inst0 <= launch_inst0;
                idex_inst1 <= launch_inst1;
                idex_pc0 <= launch_pc0;
                idex_pc1 <= launch_pc1;
                idex_rd0 <= launch_inst0[11:7];
                idex_rd1 <= launch_inst1[11:7];
            end
        end
    end

    assign commit_valid = {idex_valid && idex_lane1_valid && !redirect,
                           idex_valid && idex_lane0_valid && !redirect};
    assign commit_wen[0] = commit_valid[0] && (idex_rd0 != 0);
    assign commit_wen[1] = commit_valid[1] && (idex_rd1 != 0);
    assign commit_waddr0 = idex_rd0;
    assign commit_waddr1 = idex_rd1;
    assign commit_wdata0 = alu_result(idex_inst0, idex_pc0,
                                      rf_rdata0, rf_rdata1);
    assign commit_wdata1 = alu_result(idex_inst1, idex_pc1,
                                      rf_rdata2, rf_rdata3);
    assign retire_count = {1'b0, commit_valid[0]} +
                          {1'b0, commit_valid[1]};
    assign commit_pc0 = idex_pc0;
    assign commit_pc1 = idex_pc1;
    assign commit_inst0 = idex_inst0;
    assign commit_inst1 = idex_inst1;
    assign commit_age0 = idex_age0;
    assign commit_age1 = idex_age1;
    assign commit_epoch0 = idex_epoch0;
    assign commit_epoch1 = idex_epoch1;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && launch_fire && !launch_lane0_valid) begin
            $fatal(1, "dual ALU launch split an atomic bundle");
        end
        if (rst_n && idex_valid && idex_lane1_valid &&
            ((idex_age1 != (idex_age0 + 1'b1)) ||
             (idex_epoch1 != idex_epoch0))) begin
            $fatal(1, "dual ALU ID/EX age or epoch tag mismatch");
        end
    end
`endif

endmodule
