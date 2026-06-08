`include "defines.svh"

module branch_predictor #(
    parameter int INDEX_WIDTH = 4
) (
    input logic clk,
    input logic rst_n,

    input logic [`ADDR_WIDTH-1:0] lookup_pc0,
    output logic pred_taken0,
    output logic [`ADDR_WIDTH-1:0] pred_target0,
    input logic [`ADDR_WIDTH-1:0] lookup_pc1,
    output logic pred_taken1,
    output logic [`ADDR_WIDTH-1:0] pred_target1,

    input logic update_valid,
    input logic [`ADDR_WIDTH-1:0] update_pc,
    input logic update_taken,
    input logic [`ADDR_WIDTH-1:0] update_target,
    input logic update_is_jalr
);

    localparam int ENTRIES = 1 << INDEX_WIDTH;
    localparam int TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - 2;

    logic valid [ENTRIES-1:0];
    logic [1:0] counter [ENTRIES-1:0];
    logic [TAG_WIDTH-1:0] tag [ENTRIES-1:0];
    logic [`ADDR_WIDTH-1:0] target [ENTRIES-1:0];

    logic [INDEX_WIDTH-1:0] lookup_index0;
    logic [TAG_WIDTH-1:0] lookup_tag0;
    logic hit0;
    logic [INDEX_WIDTH-1:0] lookup_index1;
    logic [TAG_WIDTH-1:0] lookup_tag1;
    logic hit1;

    assign lookup_index0 = lookup_pc0[INDEX_WIDTH+1:2];
    assign lookup_tag0 = lookup_pc0[`ADDR_WIDTH-1:INDEX_WIDTH+2];
    assign hit0 = valid[lookup_index0] && (tag[lookup_index0] == lookup_tag0);

    assign lookup_index1 = lookup_pc1[INDEX_WIDTH+1:2];
    assign lookup_tag1 = lookup_pc1[`ADDR_WIDTH-1:INDEX_WIDTH+2];
    assign hit1 = valid[lookup_index1] && (tag[lookup_index1] == lookup_tag1);

    assign pred_taken0 = hit0 && counter[lookup_index0][1];
    assign pred_target0 = target[lookup_index0];
    assign pred_taken1 = hit1 && counter[lookup_index1][1];
    assign pred_target1 = target[lookup_index1];

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid[i] <= 1'b0;
                counter[i] <= 2'b01;
                tag[i] <= '0;
                target[i] <= '0;
            end
        end else if (update_valid && !update_is_jalr) begin
            valid[update_pc[INDEX_WIDTH+1:2]] <= 1'b1;
            if (!valid[update_pc[INDEX_WIDTH+1:2]] ||
                (tag[update_pc[INDEX_WIDTH+1:2]] != update_pc[`ADDR_WIDTH-1:INDEX_WIDTH+2])) begin
                counter[update_pc[INDEX_WIDTH+1:2]] <= update_taken ? 2'b10 : 2'b01;
            end else if (update_taken && (counter[update_pc[INDEX_WIDTH+1:2]] != 2'b11)) begin
                counter[update_pc[INDEX_WIDTH+1:2]] <= counter[update_pc[INDEX_WIDTH+1:2]] + 2'b01;
            end else if (!update_taken && (counter[update_pc[INDEX_WIDTH+1:2]] != 2'b00)) begin
                counter[update_pc[INDEX_WIDTH+1:2]] <= counter[update_pc[INDEX_WIDTH+1:2]] - 2'b01;
            end
            tag[update_pc[INDEX_WIDTH+1:2]] <= update_pc[`ADDR_WIDTH-1:INDEX_WIDTH+2];
            target[update_pc[INDEX_WIDTH+1:2]] <= update_target;
        end
    end

endmodule
