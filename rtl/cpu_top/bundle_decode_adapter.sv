`include "defines.svh"

module bundle_decode_adapter (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          redirect,
    input  logic                          bundle_valid,
    input  logic [`ISSUE_BUNDLE_WIDTH-1:0] bundle,
    output logic                          bundle_pop,
    output logic                          busy,
    input  logic                          ds_allowin,
    output logic                          fs_to_ds_valid,
    output logic [`FS_DS_WIDTH-1:0]       fs_to_ds_bus
);

    logic bundle_lane1_valid;
    logic bundle_lane0_valid;
    logic [`FETCH_UOP_WIDTH-1:0] bundle_uop1;
    logic [`FETCH_UOP_WIDTH-1:0] bundle_uop0;
    logic held_valid;
    logic [`FETCH_UOP_WIDTH-1:0] held_uop;
    logic [`FETCH_UOP_WIDTH-1:0] selected_uop;
    logic output_fire;

    logic [`FETCH_EPOCH_WIDTH-1:0] selected_epoch;
    logic [`FETCH_AGE_WIDTH-1:0] selected_age;
    logic [31:0] selected_inst;
    logic [31:0] selected_pc;
    logic selected_pred_taken;
    logic [31:0] selected_pred_target;
    logic [`BP_TYPE_WIDTH-1:0] selected_pred_type;
    logic selected_btb_hit;
    logic selected_ras_valid;
    logic [31:0] selected_ras_target;

    assign {bundle_lane1_valid, bundle_lane0_valid,
            bundle_uop1, bundle_uop0} = bundle;
    assign selected_uop = held_valid ? held_uop : bundle_uop0;
    assign {selected_epoch, selected_age, selected_inst, selected_pc,
            selected_pred_taken, selected_pred_target, selected_pred_type,
            selected_btb_hit, selected_ras_valid,
            selected_ras_target} = selected_uop;

    assign fs_to_ds_valid = !redirect &&
                            (held_valid || (bundle_valid && bundle_lane0_valid));
    assign fs_to_ds_bus = {selected_inst, selected_pc,
                           selected_pred_taken, selected_pred_target};
    assign output_fire = fs_to_ds_valid && ds_allowin;
    assign bundle_pop = output_fire && !held_valid;
    assign busy = held_valid;

    always_ff @(posedge clk) begin
        if (!rst_n || redirect) begin
            held_valid <= 1'b0;
            held_uop <= '0;
        end else if (output_fire) begin
            if (held_valid) begin
                held_valid <= 1'b0;
            end else if (bundle_lane1_valid) begin
                held_valid <= 1'b1;
                held_uop <= bundle_uop1;
            end
        end
    end

endmodule
