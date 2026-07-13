`include "defines.svh"

module issue_stage (
    input  logic                         redirect,
    input  logic [3:0]                   fetch_count,
    input  logic [`FETCH_UOP_WIDTH-1:0]  fetch_uop0,
    input  logic [`FETCH_UOP_WIDTH-1:0]  fetch_uop1,
    input  logic                         bundle_ready,
    output logic [1:0]                   fetch_pop_count,
    output logic                         bundle_valid,
    output logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle,
    output logic                         pair_accepted,
    output logic [`PAIR_CLASS_WIDTH-1:0] pair_class,
    output logic                         reject_raw,
    output logic                         reject_waw,
    output logic                         reject_struct,
    output logic                         reject_lsu_conflict
);

    logic [`FETCH_EPOCH_WIDTH-1:0] epoch0;
    logic [`FETCH_AGE_WIDTH-1:0] age0;
    logic [31:0] inst0;
    logic [31:0] pc0;
    logic pred_taken0;
    logic [31:0] pred_target0;
    logic [`BP_TYPE_WIDTH-1:0] pred_type0;
    logic btb_hit0;
    logic ras_valid0;
    logic [31:0] ras_target0;

    logic [`FETCH_EPOCH_WIDTH-1:0] epoch1;
    logic [`FETCH_AGE_WIDTH-1:0] age1;
    logic [31:0] inst1;
    logic [31:0] pc1;
    logic pred_taken1;
    logic [31:0] pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] pred_type1;
    logic btb_hit1;
    logic ras_valid1;
    logic [31:0] ras_target1;

    logic simple0;
    logic simple1;
    logic control0;
    logic control1;
    logic lsu0;
    logic lsu1;
    logic muldiv0;
    logic muldiv1;
    logic uses_rs1_0;
    logic uses_rs2_0;
    logic uses_rd_0;
    logic uses_rs1_1;
    logic uses_rs2_1;
    logic uses_rd_1;
    logic [4:0] rs1_0;
    logic [4:0] rs2_0;
    logic [4:0] rd_0;
    logic [4:0] rs1_1;
    logic [4:0] rs2_1;
    logic [4:0] rd_1;
    logic raw_hazard;
    logic waw_hazard;
    logic structural_hazard;
    logic can_pair;
    logic [`PAIR_CLASS_WIDTH-1:0] candidate_class;
    logic lsu_conflict;

    assign {epoch0, age0, inst0, pc0, pred_taken0, pred_target0,
            pred_type0, btb_hit0, ras_valid0, ras_target0} = fetch_uop0;
    assign {epoch1, age1, inst1, pc1, pred_taken1, pred_target1,
            pred_type1, btb_hit1, ras_valid1, ras_target1} = fetch_uop1;

    pair_predecode u_predecode0 (
        .instruction(inst0),
        .is_simple(simple0),
        .is_control(control0),
        .is_lsu(lsu0),
        .is_muldiv(muldiv0),
        .uses_rs1(uses_rs1_0),
        .uses_rs2(uses_rs2_0),
        .uses_rd(uses_rd_0)
    );

    pair_predecode u_predecode1 (
        .instruction(inst1),
        .is_simple(simple1),
        .is_control(control1),
        .is_lsu(lsu1),
        .is_muldiv(muldiv1),
        .uses_rs1(uses_rs1_1),
        .uses_rs2(uses_rs2_1),
        .uses_rd(uses_rd_1)
    );
    assign rs1_0 = inst0[19:15];
    assign rs2_0 = inst0[24:20];
    assign rd_0 = inst0[11:7];
    assign rs1_1 = inst1[19:15];
    assign rs2_1 = inst1[24:20];
    assign rd_1 = inst1[11:7];

    assign raw_hazard = uses_rd_0 && (rd_0 != 0) &&
                        ((uses_rs1_1 && (rs1_1 == rd_0)) ||
                         (uses_rs2_1 && (rs2_1 == rd_0)));
    assign waw_hazard = uses_rd_0 && uses_rd_1 &&
                        (rd_0 != 0) && (rd_1 != 0) && (rd_0 == rd_1);
    always_comb begin
        candidate_class = `PAIR_NONE;
        if (simple0 && simple1) begin
            candidate_class = `PAIR_SIMPLE_SIMPLE;
        end else if (simple0 && control1) begin
            candidate_class = `PAIR_SIMPLE_CONTROL;
        end else if (control0 && simple1) begin
            candidate_class = `PAIR_CONTROL_SIMPLE;
        end else if (simple0 && lsu1) begin
            candidate_class = `PAIR_SIMPLE_LSU;
        end else if (lsu0 && simple1) begin
            candidate_class = `PAIR_LSU_SIMPLE;
        end else if (simple0 && muldiv1) begin
            candidate_class = `PAIR_SIMPLE_MULDIV;
        end else if (muldiv0 && simple1) begin
            candidate_class = `PAIR_MULDIV_SIMPLE;
        end
    end

    assign lsu_conflict = lsu0 && lsu1;
    assign structural_hazard = (candidate_class == `PAIR_NONE);
    assign can_pair = (fetch_count >= 2) && !structural_hazard &&
                      !raw_hazard && !waw_hazard;

    always_comb begin
        fetch_pop_count = 2'd0;
        bundle_valid = 1'b0;
        bundle = '0;
        pair_accepted = 1'b0;
        pair_class = `PAIR_NONE;
        reject_raw = 1'b0;
        reject_waw = 1'b0;
        reject_struct = 1'b0;
        reject_lsu_conflict = 1'b0;

        if (!redirect && bundle_ready && (fetch_count != 0)) begin
            bundle_valid = 1'b1;
            if (can_pair) begin
                fetch_pop_count = 2'd2;
                bundle = {1'b1, 1'b1, fetch_uop1, fetch_uop0};
                pair_accepted = 1'b1;
                pair_class = candidate_class;
            end else begin
                fetch_pop_count = 2'd1;
                bundle = {1'b0, 1'b1, {`FETCH_UOP_WIDTH{1'b0}}, fetch_uop0};
                if (fetch_count >= 2) begin
                    reject_raw = raw_hazard;
                    reject_waw = waw_hazard;
                    reject_struct = structural_hazard;
                    reject_lsu_conflict = lsu_conflict;
                end
            end
        end
    end

endmodule
