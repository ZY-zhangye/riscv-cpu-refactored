`include "defines.svh"

module bundle_dispatch (
    input  logic                           redirect,
    input  logic                           bundle_valid,
    input  logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle,
    input  logic                           next_bundle_valid,
    input  logic [`ISSUE_BUNDLE_WIDTH-1:0] next_bundle,
    input  logic                           legacy_idle,
    input  logic                           prefer_legacy,
    input  logic                           dual_mode,
    input  logic                           dual_block_legacy,
    output logic                           dual_candidate,
    output logic                           next_dual_candidate,
    output logic                           dual_bundle_valid,
    output logic                           legacy_bundle_valid
);

    logic lane1_valid;
    logic lane0_valid;
    logic [`FETCH_UOP_WIDTH-1:0] uop1;
    logic [`FETCH_UOP_WIDTH-1:0] uop0;
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
    logic next_lane1_valid;
    logic next_lane0_valid;
    logic [`FETCH_UOP_WIDTH-1:0] next_uop1;
    logic [`FETCH_UOP_WIDTH-1:0] next_uop0;
    logic [`FETCH_EPOCH_WIDTH-1:0] next_epoch0;
    logic [`FETCH_AGE_WIDTH-1:0] next_age0;
    logic [31:0] next_inst0;
    logic [31:0] next_pc0;
    logic next_pred_taken0;
    logic [31:0] next_pred_target0;
    logic [`BP_TYPE_WIDTH-1:0] next_pred_type0;
    logic next_btb_hit0;
    logic next_ras_valid0;
    logic [31:0] next_ras_target0;
    logic [`FETCH_EPOCH_WIDTH-1:0] next_epoch1;
    logic [`FETCH_AGE_WIDTH-1:0] next_age1;
    logic [31:0] next_inst1;
    logic [31:0] next_pc1;
    logic next_pred_taken1;
    logic [31:0] next_pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] next_pred_type1;
    logic next_btb_hit1;
    logic next_ras_valid1;
    logic [31:0] next_ras_target1;
    logic simple0;
    logic simple1;
    logic next_simple0;
    logic next_simple1;
    logic control1;
    logic next_control1;
    logic lsu0;
    logic lsu1;
    logic next_lsu0;
    logic next_lsu1;
    logic complex_candidate;
    logic lsu_candidate;
    logic next_simple_pair;
    logic lsu_run_candidate;
    logic dual_schedule;

    assign {lane1_valid, lane0_valid, uop1, uop0} = bundle;
    assign {epoch0, age0, inst0, pc0, pred_taken0, pred_target0,
            pred_type0, btb_hit0, ras_valid0, ras_target0} = uop0;
    assign {epoch1, age1, inst1, pc1, pred_taken1, pred_target1,
            pred_type1, btb_hit1, ras_valid1, ras_target1} = uop1;
    assign {next_lane1_valid, next_lane0_valid,
            next_uop1, next_uop0} = next_bundle;
    assign {next_epoch0, next_age0, next_inst0, next_pc0,
            next_pred_taken0, next_pred_target0, next_pred_type0,
            next_btb_hit0, next_ras_valid0,
            next_ras_target0} = next_uop0;
    assign {next_epoch1, next_age1, next_inst1, next_pc1,
            next_pred_taken1, next_pred_target1, next_pred_type1,
            next_btb_hit1, next_ras_valid1,
            next_ras_target1} = next_uop1;

    pair_predecode u_predecode0 (
        .instruction(inst0), .is_simple(simple0),
        .is_control(), .is_lsu(lsu0), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_predecode1 (
        .instruction(inst1), .is_simple(simple1),
        .is_control(control1), .is_lsu(lsu1), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_next_predecode0 (
        .instruction(next_inst0), .is_simple(next_simple0),
        .is_control(), .is_lsu(next_lsu0), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_next_predecode1 (
        .instruction(next_inst1), .is_simple(next_simple1),
        .is_control(next_control1), .is_lsu(next_lsu1), .is_muldiv(),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );

    assign dual_candidate = lane0_valid && lane1_valid &&
                            ((simple0 && (simple1 || control1 || lsu1)) ||
                             (lsu0 && simple1));
    assign next_dual_candidate = next_bundle_valid && next_lane0_valid &&
                                 next_lane1_valid &&
                                 ((next_simple0 && (next_simple1 ||
                                                   next_control1 || next_lsu1)) ||
                                  (next_lsu0 && next_simple1));
    assign lsu_candidate = lsu0 || lsu1;
    assign next_simple_pair = next_bundle_valid && next_lane0_valid &&
                              next_lane1_valid && next_simple0 &&
                              next_simple1;
    // A long LSU resident is admitted only inside an already-established dual
    // run and only when a younger simple pair can consume the same-edge MEM
    // release.  Otherwise the legacy pipeline is cheaper because it can fill
    // its younger stages behind the memory operation.
    assign lsu_run_candidate = lsu_candidate && dual_mode && next_simple_pair;
    // Control pairs resolve frontend state and may enter an idle dual domain
    // directly.  An LSU pair uses the same run-establishment lookahead as a
    // simple pair so an isolated memory operation does not pay a domain switch.
    assign complex_candidate = control1;
    assign dual_schedule = complex_candidate ||
                           (!lsu_candidate &&
                            (dual_mode || next_dual_candidate)) ||
                           lsu_run_candidate;
    assign dual_bundle_valid = !redirect && bundle_valid && dual_candidate &&
                               legacy_idle && !prefer_legacy && dual_schedule;
    // The current dual ID/EX resident commits on this edge, so a younger
    // legacy uop may enter Decode on the same edge without overlapping commit.
    assign legacy_bundle_valid = !redirect && bundle_valid &&
                                 !dual_block_legacy &&
                                 (!dual_candidate || prefer_legacy ||
                                  (lsu_candidate && !lsu_run_candidate) ||
                                  (!complex_candidate && !lsu_candidate &&
                                   !dual_mode &&
                                   next_bundle_valid &&
                                   !next_dual_candidate));

endmodule
