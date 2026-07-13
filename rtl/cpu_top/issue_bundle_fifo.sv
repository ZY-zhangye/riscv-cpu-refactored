`include "defines.svh"

module issue_bundle_fifo #(
    parameter integer DEPTH = 4
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    input  logic                          push_valid,
    input  logic [`ISSUE_BUNDLE_WIDTH-1:0] push_bundle,
    input  logic                          pop_valid,
    output logic                          head_valid,
    output logic [`ISSUE_BUNDLE_WIDTH-1:0] head_bundle,
    output logic                          next_valid,
    output logic [`ISSUE_BUNDLE_WIDTH-1:0] next_bundle,
    output logic [$clog2(DEPTH+1)-1:0]    count,
    output logic                          push_ready
);

    localparam integer PTR_WIDTH = $clog2(DEPTH);
    logic [`ISSUE_BUNDLE_WIDTH-1:0] entries [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] read_ptr;
    logic [PTR_WIDTH-1:0] write_ptr;

    assign head_valid = (count != 0);
    assign head_bundle = entries[read_ptr];
    assign next_valid = (count >= 2);
    assign next_bundle = entries[read_ptr + 1'b1];
    assign push_ready = (count != DEPTH);

    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            read_ptr <= '0;
            write_ptr <= '0;
            count <= '0;
        end else begin
            if (push_valid) begin
                entries[write_ptr] <= push_bundle;
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop_valid) begin
                read_ptr <= read_ptr + 1'b1;
            end
            case ({push_valid, pop_valid})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase

`ifndef SYNTHESIS
            if (push_valid && !push_ready && !pop_valid) begin
                $fatal(1, "Issue bundle FIFO overflow");
            end
            if (pop_valid && !head_valid) begin
                $fatal(1, "Issue bundle FIFO underflow");
            end
`endif
        end
    end

endmodule
