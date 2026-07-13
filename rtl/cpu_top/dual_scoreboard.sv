module dual_scoreboard (
    input  logic        consumer_valid,
    input  logic [3:0]  consumer_uses,
    input  logic [19:0] consumer_rs_flat,
    // Producer slots are ordered youngest to oldest.  A3 maps them as
    // EX1, EX0, MEM1, MEM0, WB1, WB0.
    input  logic [5:0]  producer_valid,
    input  logic [5:0]  producer_kill,
    input  logic [5:0]  producer_pending,
    input  logic [5:0]  producer_result_valid,
    input  logic [29:0] producer_dest_flat,
    output logic        dependency,
    output logic        stall,
    output logic [11:0] forward_sel_flat
);

    integer source_index;
    integer producer_index;
    logic match_found;
    logic [4:0] source_addr;
    logic [4:0] producer_dest;

    always_comb begin
        dependency = 1'b0;
        stall = 1'b0;
        forward_sel_flat = '0;

        for (source_index = 0; source_index < 4; source_index = source_index + 1) begin
            match_found = 1'b0;
            source_addr = consumer_rs_flat[(source_index * 5) +: 5];
            for (producer_index = 0; producer_index < 6; producer_index = producer_index + 1) begin
                producer_dest = producer_dest_flat[(producer_index * 5) +: 5];
                if (consumer_valid && consumer_uses[source_index] &&
                    (source_addr != 0) && !match_found &&
                    producer_valid[producer_index] &&
                    !producer_kill[producer_index] &&
                    (producer_dest != 0) &&
                    (source_addr == producer_dest)) begin
                    match_found = 1'b1;
                    dependency = 1'b1;
                    if (producer_pending[producer_index] ||
                        !producer_result_valid[producer_index]) begin
                        stall = 1'b1;
                    end else begin
                        forward_sel_flat[(source_index * 3) +: 3] =
                            producer_index + 1;
                    end
                end
            end
        end
    end

endmodule
