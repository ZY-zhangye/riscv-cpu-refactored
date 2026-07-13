`include "defines.svh"

module fetch_fifo #(
    parameter integer DEPTH = 8
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        clear,
    input  logic [1:0]                  push_count,
    input  logic [`FETCH_UOP_WIDTH-1:0] push_uop0,
    input  logic [`FETCH_UOP_WIDTH-1:0] push_uop1,
    input  logic [1:0]                  pop_count,
    output logic [$clog2(DEPTH+1)-1:0]  count,
    output logic [$clog2(DEPTH+1)-1:0]  free_count,
    output logic                        peek_valid0,
    output logic                        peek_valid1,
    output logic [`FETCH_UOP_WIDTH-1:0] peek_uop0,
    output logic [`FETCH_UOP_WIDTH-1:0] peek_uop1
);

    localparam integer PTR_WIDTH = $clog2(DEPTH);
    logic [`FETCH_UOP_WIDTH-1:0] entries [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] read_ptr;
    logic [PTR_WIDTH-1:0] write_ptr;

    assign free_count = DEPTH - count;
    assign peek_valid0 = (count != 0);
    assign peek_valid1 = (count >= 2);
    assign peek_uop0 = entries[read_ptr];
    assign peek_uop1 = entries[read_ptr + 1'b1];

    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            read_ptr <= '0;
            write_ptr <= '0;
            count <= '0;
        end else begin
            if (push_count != 0) begin
                entries[write_ptr] <= push_uop0;
            end
            if (push_count == 2) begin
                entries[write_ptr + 1'b1] <= push_uop1;
            end

            read_ptr <= read_ptr + pop_count;
            write_ptr <= write_ptr + push_count;
            count <= count + push_count - pop_count;

`ifndef SYNTHESIS
            if (pop_count > count) begin
                $fatal(1, "Fetch FIFO underflow count=%0d pop=%0d",
                       count, pop_count);
            end
            if (push_count > (free_count + pop_count)) begin
                $fatal(1, "Fetch FIFO overflow free=%0d push=%0d pop=%0d",
                       free_count, push_count, pop_count);
            end
`endif
        end
    end

endmodule
