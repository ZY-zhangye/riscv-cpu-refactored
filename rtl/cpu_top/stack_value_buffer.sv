module stack_value_buffer #(
    parameter int ENTRIES = 16
) (
    input  logic        clk,
    input  logic        rst_n,

    // EX-stage aligned LW lookup. The hit indication is combinational so ID
    // can decide whether the immediately following integer ALU instruction
    // may advance; the data itself is captured before it is forwarded.
    input  logic        query_valid,
    input  logic [31:0] query_addr,
    output logic        query_hit,
    output logic [31:0] query_data,

    input  logic        capture_en,
    input  logic [31:0] capture_addr,
    input  logic        capture_flush,
    output logic        captured_valid,
    output logic [31:0] captured_data,

    // Every architectural store snoops the selected entry. Only qualified,
    // aligned full-word stack stores allocate; any full-word alias updates an
    // existing entry, while a partial write invalidates an existing entry.
    input  logic        store_valid,
    input  logic        store_allocate,
    input  logic [31:0] store_addr,
    input  logic [3:0]  store_wstrb,
    input  logic [31:0] store_wdata
);
    localparam int INDEX_WIDTH = $clog2(ENTRIES);
    // The CPU wrapper admits only addresses from one 256 KiB DRAM window.
    // Its high 14 bits are therefore implicit in valid_array; retain the full
    // word address within that window as the tag.
    localparam int TAG_WIDTH = 18 - INDEX_WIDTH - 2;

    logic [ENTRIES-1:0] valid_array;
    logic [TAG_WIDTH-1:0] tag_array [0:ENTRIES-1];
    logic [31:0] data_array [0:ENTRIES-1];

    logic [INDEX_WIDTH-1:0] query_index;
    logic [TAG_WIDTH-1:0] query_tag;
    logic [INDEX_WIDTH-1:0] store_index;
    logic [INDEX_WIDTH-1:0] capture_index;
    logic [TAG_WIDTH-1:0] store_tag;
    logic store_tag_hit;
    logic array_query_hit;

    assign query_index = query_addr[INDEX_WIDTH+1:2];
    assign query_tag = query_addr[17:INDEX_WIDTH+2];
    assign store_index = store_addr[INDEX_WIDTH+1:2];
    assign capture_index = capture_addr[INDEX_WIDTH+1:2];
    assign store_tag = store_addr[17:INDEX_WIDTH+2];

    assign array_query_hit = query_valid && (query_addr[1:0] == 2'b00) &&
                             valid_array[query_index] &&
                             (tag_array[query_index] == query_tag);
    assign store_tag_hit = valid_array[store_index] &&
                           (tag_array[store_index] == store_tag);
    assign query_hit = array_query_hit;
    assign query_data = data_array[query_index];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_array <= '0;
            captured_valid <= 1'b0;
            captured_data <= 32'b0;
        end else begin
            if (capture_flush) begin
                captured_valid <= 1'b0;
            end else if (capture_en) begin
                captured_valid <= 1'b1;
                captured_data <= data_array[capture_index];
            end else begin
                captured_valid <= 1'b0;
            end

            if (store_valid) begin
                if (store_wstrb == 4'b1111) begin
                    if (store_allocate || store_tag_hit) begin
                        valid_array[store_index] <= 1'b1;
                        tag_array[store_index] <= store_tag;
                        data_array[store_index] <= store_wdata;
                    end
                end else if (store_tag_hit) begin
                    valid_array[store_index] <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (ENTRIES >= 2 && (ENTRIES & (ENTRIES - 1)) == 0)
            else $fatal(1, "stack_value_buffer ENTRIES must be a power of two");
    end
`endif
endmodule
