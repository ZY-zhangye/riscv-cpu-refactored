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
    output logic [`FETCH_EPOCH_WIDTH-1:0]  commit_epoch1,
    output logic                           branch_event,
    output logic                           branch_mispredict_event,
    output logic                           branch_redirect,
    output logic [31:0]                    branch_redirect_target,
    output logic                           bp_update_valid,
    output logic [31:0]                    bp_update_pc,
    output logic                           bp_update_taken,
    output logic [31:0]                    bp_update_target,
    output logic [`BP_TYPE_WIDTH-1:0]      bp_update_type,
    output logic                           lane1_control_event,
    output logic                           exception_valid,
    output logic [6:0]                     exception_code,
    output logic [31:0]                    exception_pc,
    output logic [31:0]                    exception_mtval
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
    logic idex_pred_taken1;
    logic [31:0] idex_pred_target1;

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
    logic alu_busy0;
    logic alu_busy1;
    logic alu_done0;
    logic alu_done1;
    logic [31:0] alu_result0;
    logic [31:0] alu_result1;
    logic launch_simple0;
    logic launch_simple1;
    logic launch_control0;
    logic launch_control1;
    logic idex_simple0;
    logic idex_simple1;
    logic idex_control0;
    logic idex_control1;
    logic idex_uses_rd0;
    logic idex_uses_rd1;
    logic pipeline_clear;
    logic branch_busy;
    logic branch_done;
    logic branch_taken;
    logic [31:0] branch_target;
    logic branch_mispredict;
    logic [31:0] branch_unit_redirect_target;
    logic [31:0] branch_immediate;
    logic [31:0] branch_direct_target;
    logic [5:0] branch_opcode;
    logic idex_is_jal;
    logic idex_is_jalr;
    logic branch_iam;
    logic bp_update_is_call;
    logic bp_update_is_return;
    logic lane1_done;

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

    pair_predecode u_launch_predecode0 (
        .instruction(launch_inst0), .is_simple(launch_simple0),
        .is_control(launch_control0), .is_lsu(), .is_muldiv(),
        .uses_rs1(launch_uses_rs1_0), .uses_rs2(launch_uses_rs2_0),
        .uses_rd()
    );
    pair_predecode u_launch_predecode1 (
        .instruction(launch_inst1), .is_simple(launch_simple1),
        .is_control(launch_control1), .is_lsu(), .is_muldiv(),
        .uses_rs1(launch_uses_rs1_1), .uses_rs2(launch_uses_rs2_1),
        .uses_rd()
    );
    pair_predecode u_idex_predecode0 (
        .instruction(idex_inst0), .is_simple(idex_simple0),
        .is_control(idex_control0), .is_lsu(), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd(idex_uses_rd0)
    );
    pair_predecode u_idex_predecode1 (
        .instruction(idex_inst1), .is_simple(idex_simple1),
        .is_control(idex_control1), .is_lsu(), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd(idex_uses_rd1)
    );
    assign rf_raddr0 = launch_inst0[19:15];
    assign rf_raddr1 = launch_inst0[24:20];
    assign rf_raddr2 = launch_inst1[19:15];
    assign rf_raddr3 = launch_inst1[24:20];
    assign consumer_rs_flat = {rf_raddr3, rf_raddr2, rf_raddr1, rf_raddr0};
    assign consumer_uses = {launch_uses_rs2_1, launch_uses_rs1_1,
                            launch_uses_rs2_0, launch_uses_rs1_0};

    // Slot priority: EX lane1, EX lane0, then reserved MEM/WB lane slots.
    assign producer_valid = {4'b0,
                             idex_valid && idex_lane0_valid && idex_uses_rd0 &&
                                 (idex_rd0 != 0),
                             idex_valid && idex_lane1_valid && idex_uses_rd1 &&
                                 (idex_rd1 != 0)};
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

    assign pipeline_clear = redirect || branch_redirect || exception_valid;
    assign launch_ready = !pipeline_clear && !scoreboard_stall;
    assign launch_fire = launch_valid && launch_ready;
    assign rf_read_en = launch_fire;
    assign busy = idex_valid;
    assign dependency_event = launch_valid && scoreboard_dependency;
    assign pending_stall_event = launch_valid && scoreboard_stall;

    always_ff @(posedge clk) begin
        if (!rst_n || pipeline_clear) begin
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
            idex_pred_taken1 <= 1'b0;
            idex_pred_target1 <= 32'b0;
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
                idex_pred_taken1 <= launch_pred_taken1;
                idex_pred_target1 <= launch_pred_target1;
            end
        end
    end

    simple_alu_exec_unit u_alu0 (
        .start(idex_valid && idex_lane0_valid && idex_simple0),
        .kill(redirect),
        .instruction(idex_inst0),
        .pc(idex_pc0),
        .rs1(rf_rdata0),
        .rs2(rf_rdata1),
        .busy(alu_busy0),
        .done(alu_done0),
        .result(alu_result0)
    );

    simple_alu_exec_unit u_alu1 (
        .start(idex_valid && idex_lane1_valid && idex_simple1),
        .kill(redirect),
        .instruction(idex_inst1),
        .pc(idex_pc1),
        .rs1(rf_rdata2),
        .rs2(rf_rdata3),
        .busy(alu_busy1),
        .done(alu_done1),
        .result(alu_result1)
    );

    assign idex_is_jal = idex_control1 && (idex_inst1[6:0] == 7'b1101111);
    assign idex_is_jalr = idex_control1 &&
                          (idex_inst1[6:0] == 7'b1100111);
    assign branch_immediate = idex_is_jal ?
        {{11{idex_inst1[31]}}, idex_inst1[31], idex_inst1[19:12],
         idex_inst1[20], idex_inst1[30:21], 1'b0} :
        idex_is_jalr ? {{20{idex_inst1[31]}}, idex_inst1[31:20]} :
        {{19{idex_inst1[31]}}, idex_inst1[31], idex_inst1[7],
         idex_inst1[30:25], idex_inst1[11:8], 1'b0};
    assign branch_direct_target = idex_pc1 + branch_immediate;

    always_comb begin
        branch_opcode = 6'b0;
        if (idex_control1 && (idex_inst1[6:0] == 7'b1100011)) begin
            unique case (idex_inst1[14:12])
                3'b000: branch_opcode[5] = 1'b1;
                3'b001: branch_opcode[4] = 1'b1;
                3'b100: branch_opcode[3] = 1'b1;
                3'b101: branch_opcode[2] = 1'b1;
                3'b110: branch_opcode[1] = 1'b1;
                3'b111: branch_opcode[0] = 1'b1;
                default: branch_opcode = 6'b0;
            endcase
        end
    end

    branch_exec_unit u_lane1_branch (
        .start(idex_valid && idex_lane1_valid && idex_control1),
        .kill(redirect),
        .pc(idex_pc1),
        .src1(rf_rdata2),
        .src2(rf_rdata3),
        .immediate(branch_immediate),
        .direct_target(branch_direct_target),
        .branch_opcode(branch_opcode),
        .is_jal(idex_is_jal),
        .is_jalr(idex_is_jalr),
        .predicted_taken(idex_pred_taken1),
        .predicted_target(idex_pred_target1),
        .busy(branch_busy),
        .done(branch_done),
        .taken(branch_taken),
        .target(branch_target),
        .mispredict(branch_mispredict),
        .redirect_target(branch_unit_redirect_target)
    );

    assign branch_event = branch_done;
    assign branch_iam = branch_event && branch_taken &&
                        (branch_target[1:0] != 2'b00);
    assign branch_redirect = branch_event && branch_mispredict && !branch_iam;
    assign branch_redirect_target = branch_unit_redirect_target;
    assign branch_mispredict_event = branch_event && branch_mispredict;
    assign bp_update_valid = branch_event;
    assign bp_update_pc = idex_pc1;
    assign bp_update_taken = branch_taken;
    assign bp_update_target = branch_target;
    assign bp_update_is_call = (idex_is_jal || idex_is_jalr) &&
                               ((idex_inst1[11:7] == 5'd1) ||
                                (idex_inst1[11:7] == 5'd5));
    assign bp_update_is_return = idex_is_jalr &&
                                 (idex_inst1[11:7] == 5'd0) &&
                                 ((idex_inst1[19:15] == 5'd1) ||
                                  (idex_inst1[19:15] == 5'd5)) &&
                                 (idex_inst1[31:20] == 12'd0);
    always_comb begin
        if (bp_update_is_return) begin
            bp_update_type = `BP_TYPE_RETURN;
        end else if (bp_update_is_call) begin
            bp_update_type = `BP_TYPE_CALL;
        end else if (idex_is_jalr) begin
            bp_update_type = `BP_TYPE_JALR;
        end else if (idex_is_jal) begin
            bp_update_type = `BP_TYPE_JAL;
        end else begin
            bp_update_type = `BP_TYPE_BRANCH;
        end
    end

    assign lane1_control_event = launch_fire && launch_control1;
    assign exception_valid = branch_iam;
    assign exception_code = exception_valid ? `EXC_IAM : `EXC_NONE;
    assign exception_pc = idex_pc1;
    assign exception_mtval = branch_target;

    assign lane1_done = (idex_simple1 && alu_done1) ||
                        (idex_control1 && branch_done);
    assign commit_valid[0] = alu_done0;
    assign commit_valid[1] = lane1_done && !exception_valid;
    assign commit_wen[0] = commit_valid[0] && idex_uses_rd0 &&
                           (idex_rd0 != 0);
    assign commit_wen[1] = commit_valid[1] && idex_uses_rd1 &&
                           (idex_rd1 != 0);
    assign commit_waddr0 = idex_rd0;
    assign commit_waddr1 = idex_rd1;
    assign commit_wdata0 = alu_result0;
    assign commit_wdata1 = idex_control1 ? (idex_pc1 + 32'd4) : alu_result1;
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
        if (rst_n && launch_fire &&
            (!launch_simple0 || !(launch_simple1 || launch_control1) ||
             launch_control0)) begin
            $fatal(1, "unsupported pairing class entered the A6.2 dual resident");
        end
        if (rst_n && branch_event &&
            (!idex_valid || !idex_lane1_valid || !idex_control1)) begin
            $fatal(1, "lane1 branch resolved without a control resident");
        end
        if (rst_n && exception_valid &&
            ((commit_valid != 2'b01) || branch_redirect || commit_wen[1])) begin
            $fatal(1, "lane1 control exception violated precise age commit");
        end
        if (rst_n && branch_redirect && exception_valid) begin
            $fatal(1, "misaligned lane1 control emitted both redirect and exception");
        end
    end
`endif

endmodule
