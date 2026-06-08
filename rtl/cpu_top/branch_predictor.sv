`include "defines.svh"

module branch_predictor #(
    parameter int INDEX_WIDTH = 4,
    parameter int ENTRIES = 1 << INDEX_WIDTH,
    parameter int TAG_WIDTH = `ADDR_WIDTH - INDEX_WIDTH - 2
) (
    input logic clk,
    input logic rst_n,

    input logic [`ADDR_WIDTH-1:0] lookup_pc,
    output logic pred_taken,
    output logic [`ADDR_WIDTH-1:0] pred_target,

    input logic update_valid,
    input logic [`ADDR_WIDTH-1:0] update_pc,
    input logic update_taken,
    input logic [`ADDR_WIDTH-1:0] update_target,
    input logic update_is_jalr
);

    logic valid [ENTRIES-1:0];
    logic [1:0] counter [ENTRIES-1:0];
    logic [TAG_WIDTH-1:0] tag [ENTRIES-1:0];
    logic [`ADDR_WIDTH-1:0] target [ENTRIES-1:0];

    logic [INDEX_WIDTH-1:0] lookup_index;
    logic [TAG_WIDTH-1:0] lookup_tag;
    logic hit;

    assign lookup_index = lookup_pc[INDEX_WIDTH+1:2];
    assign lookup_tag = lookup_pc[`ADDR_WIDTH-1:INDEX_WIDTH+2];
    assign hit = valid[lookup_index] && (tag[lookup_index] == lookup_tag);

    assign pred_taken = hit && counter[lookup_index][1];
    assign pred_target = target[lookup_index];

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
