`timescale 1ns / 1ps

module tb_stack_value_buffer;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic query_valid = 1'b0;
    logic [31:0] query_addr = 32'b0;
    logic query_hit;
    logic [31:0] query_data;
    logic capture_en = 1'b0;
    logic [31:0] capture_addr = 32'b0;
    logic capture_flush = 1'b0;
    logic captured_valid;
    logic [31:0] captured_data;
    logic store_valid = 1'b0;
    logic store_allocate = 1'b0;
    logic [31:0] store_addr = 32'b0;
    logic [3:0] store_wstrb = 4'b0;
    logic [31:0] store_wdata = 32'b0;

    always #5 clk = ~clk;

    stack_value_buffer dut (.*);

    task automatic store(
        input logic allocate,
        input logic [31:0] addr,
        input logic [3:0] wstrb,
        input logic [31:0] data
    );
        @(negedge clk);
        store_valid = 1'b1;
        store_allocate = allocate;
        store_addr = addr;
        store_wstrb = wstrb;
        store_wdata = data;
        @(posedge clk);
        #1;
        store_valid = 1'b0;
        store_allocate = 1'b0;
        store_wstrb = 4'b0;
    endtask

    task automatic check_query(
        input logic [31:0] addr,
        input logic expected_hit,
        input logic [31:0] expected_data
    );
        query_valid = 1'b1;
        query_addr = addr;
        #1;
        assert (query_hit == expected_hit)
            else $fatal(1, "query %08x hit=%0b expected=%0b",
                        addr, query_hit, expected_hit);
        if (expected_hit) begin
            assert (query_data == expected_data)
                else $fatal(1, "query %08x data=%08x expected=%08x",
                            addr, query_data, expected_data);
        end
        query_valid = 1'b0;
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        check_query(32'h8000_1040, 1'b0, 32'b0);

        // Qualified aligned SW allocates.
        store(1'b1, 32'h8000_1040, 4'b1111, 32'h1122_3344);
        check_query(32'h8000_1040, 1'b1, 32'h1122_3344);

        // Hit data is captured at the edge and only then becomes forwardable.
        query_valid = 1'b1;
        query_addr = 32'h8000_1040;
        capture_addr = 32'h8000_1040;
        capture_en = 1'b1;
        @(posedge clk);
        #1;
        assert (captured_valid && captured_data == 32'h1122_3344)
            else $fatal(1, "registered capture failed");
        query_valid = 1'b0;
        capture_en = 1'b0;

        // A full-word store through another base register updates on tag hit.
        store(1'b0, 32'h8000_1040, 4'b1111, 32'haabb_ccdd);
        check_query(32'h8000_1040, 1'b1, 32'haabb_ccdd);

        // A partial write to the same word invalidates the cached scalar.
        store(1'b0, 32'h8000_1041, 4'b0010, 32'h0000_ee00);
        check_query(32'h8000_1040, 1'b0, 32'b0);

        // A non-qualified full-word miss must not allocate.
        store(1'b0, 32'h8000_1080, 4'b1111, 32'h5566_7788);
        check_query(32'h8000_1080, 1'b0, 32'b0);

        // Same-index allocation replaces the previous tag.
        store(1'b1, 32'h8000_1040, 4'b1111, 32'h0102_0304);
        store(1'b1, 32'h8000_1080, 4'b1111, 32'h0506_0708);
        check_query(32'h8000_1040, 1'b0, 32'b0);
        check_query(32'h8000_1080, 1'b1, 32'h0506_0708);

        // Unaligned LW queries are never considered hits.
        check_query(32'h8000_1082, 1'b0, 32'b0);

        // Flush kills only the pending forward, not the cache contents.
        capture_flush = 1'b1;
        @(posedge clk);
        #1;
        capture_flush = 1'b0;
        assert (!captured_valid) else $fatal(1, "flush did not clear capture");
        check_query(32'h8000_1080, 1'b1, 32'h0506_0708);

        rst_n = 1'b0;
        @(posedge clk);
        #1;
        rst_n = 1'b1;
        check_query(32'h8000_1080, 1'b0, 32'b0);

        $display("PASS: stack value buffer directed tests");
        $finish;
    end
endmodule
