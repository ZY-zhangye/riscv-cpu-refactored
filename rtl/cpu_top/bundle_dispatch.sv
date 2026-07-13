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
    logic control0;
    logic control1;
    logic next_control0;
    logic next_control1;
    logic lsu0;
    logic lsu1;
    logic next_lsu0;
    logic next_lsu1;
    logic muldiv0;
    logic muldiv1;
    logic next_muldiv0;
    logic next_muldiv1;
    logic pair_candidate;
    logic next_pair_candidate;
    logic simple_singleton_candidate;
    logic next_simple_singleton_candidate;
    logic control_singleton_candidate;
    logic next_control_singleton_candidate;
    logic muldiv_singleton_candidate;
    logic next_muldiv_singleton_candidate;
    logic complex_candidate;
    logic lsu_candidate;
    logic muldiv_candidate;
    logic next_simple_pair;
    logic next_control_pair;
    logic next_fast_continuation;
    logic lsu_run_candidate;
    logic muldiv_run_candidate;
    logic effective_prefer_legacy;
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
        .is_control(control0), .is_lsu(lsu0), .is_muldiv(muldiv0),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_predecode1 (
        .instruction(inst1), .is_simple(simple1),
        .is_control(control1), .is_lsu(lsu1), .is_muldiv(muldiv1),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_next_predecode0 (
        .instruction(next_inst0), .is_simple(next_simple0),
        .is_control(next_control0), .is_lsu(next_lsu0),
        .is_muldiv(next_muldiv0),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );
    pair_predecode u_next_predecode1 (
        .instruction(next_inst1), .is_simple(next_simple1),
        .is_control(next_control1), .is_lsu(next_lsu1),
        .is_muldiv(next_muldiv1),
        .uses_rs1(), .uses_rs2(), .uses_rd()
    );

    assign pair_candidate = lane0_valid && lane1_valid &&
                            ((simple0 && (simple1 || control1 || lsu1 ||
                                          muldiv1)) ||
                             ((control0 || lsu0 || muldiv0) && simple1));
    assign simple_singleton_candidate = lane0_valid && !lane1_valid &&
                                        simple0;
    assign control_singleton_candidate = lane0_valid && !lane1_valid &&
                                         control0;
    assign muldiv_singleton_candidate = lane0_valid && !lane1_valid &&
                                        muldiv0;
    assign dual_candidate = pair_candidate || simple_singleton_candidate ||
                            control_singleton_candidate ||
                            muldiv_singleton_candidate;
    assign next_pair_candidate = next_bundle_valid && next_lane0_valid &&
                                 next_lane1_valid &&
                                 ((next_simple0 && (next_simple1 ||
                                                   next_control1 || next_lsu1 ||
                                                   next_muldiv1)) ||
                                  ((next_control0 || next_lsu0 ||
                                    next_muldiv0) &&
                                   next_simple1));
    assign next_simple_singleton_candidate = next_bundle_valid &&
                                             next_lane0_valid &&
                                             !next_lane1_valid &&
                                             next_simple0;
    assign next_control_singleton_candidate = next_bundle_valid &&
                                              next_lane0_valid &&
                                              !next_lane1_valid &&
                                              next_control0;
    assign next_muldiv_singleton_candidate = next_bundle_valid &&
                                             next_lane0_valid &&
                                             !next_lane1_valid &&
                                             next_muldiv0;
    assign next_dual_candidate = next_pair_candidate ||
                                 next_simple_singleton_candidate ||
                                 next_control_singleton_candidate ||
                                 next_muldiv_singleton_candidate;
    assign lsu_candidate = lsu0 || lsu1;
    assign muldiv_candidate = muldiv0 || muldiv1;
    assign next_simple_pair = next_bundle_valid && next_lane0_valid &&
                              next_lane1_valid && next_simple0 &&
                              next_simple1;
    assign next_control_pair = next_bundle_valid && next_lane0_valid &&
                               next_lane1_valid &&
                               ((next_simple0 && next_control1) ||
                                (next_control0 && next_simple1));
    assign next_fast_continuation = next_simple_pair ||
                                    next_simple_singleton_candidate ||
                                    next_control_singleton_candidate ||
                                    next_control_pair;
    // A long LSU resident is admitted only inside an already-established dual
    // run and only when a younger one-cycle simple/control bundle can consume
    // the same-edge MEM release.  This preserves the LSU's fixed four-beat
    // cadence and excludes another LSU or long MULDIV continuation.  Otherwise
    // the legacy pipeline is cheaper because it can fill younger stages behind
    // the memory operation.
    assign lsu_run_candidate = lsu_candidate && dual_mode &&
                               next_fast_continuation;
    // A valid shared MUL/DIV bundle can establish a dual run directly.  A pair
    // overlaps its independent simple lane; a singleton avoids draining into
    // the legacy long-op path and reuses the same resident.  legacy_idle
    // remains the hard exclusion boundary while older legacy state exists.
    assign muldiv_run_candidate = muldiv_candidate;
    // Control bundles, including lane0-only control singletons, resolve
    // frontend state and may enter an idle dual domain directly.  Plain simple
    // bundles enter only inside an established run or when a compatible
    // younger bundle can amortize the domain switch.  An LSU pair keeps its
    // stricter run rule.
    assign complex_candidate = control0 || control1;
    assign dual_schedule = complex_candidate ||
                           (!lsu_candidate && !muldiv_candidate &&
                            (dual_mode || next_dual_candidate)) ||
                           lsu_run_candidate || muldiv_run_candidate;
    // legacy_idle is the hard cross-domain safety condition.  Once it is true,
    // a historical long-op cooldown must not indefinitely route every new
    // MUL/DIV pair back to legacy and make the A6.4 class unreachable.
    assign effective_prefer_legacy = prefer_legacy && !muldiv_candidate;
    assign dual_bundle_valid = !redirect && bundle_valid && dual_candidate &&
                               legacy_idle && !effective_prefer_legacy &&
                               dual_schedule;
    // The current dual ID/EX resident commits on this edge, so a younger
    // legacy uop may enter Decode on the same edge without overlapping commit.
    assign legacy_bundle_valid = !redirect && bundle_valid &&
                                 !dual_block_legacy &&
                                 (!dual_candidate || effective_prefer_legacy ||
                                  (lsu_candidate && !lsu_run_candidate) ||
                                  (muldiv_candidate &&
                                   !muldiv_run_candidate) ||
                                  (!complex_candidate && !lsu_candidate &&
                                   !muldiv_candidate &&
                                   !dual_mode &&
                                   next_bundle_valid &&
                                   !next_dual_candidate));

endmodule
