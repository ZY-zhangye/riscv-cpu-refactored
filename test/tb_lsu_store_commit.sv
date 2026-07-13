`timescale 1ns/1ps
`include "defines.svh"

module tb_lsu_store_commit;
    logic clk;
    logic rst_n;
    logic start;
    logic kill;
    logic [31:0] base;
    logic [31:0] store_data;
    logic [31:0] immediate;
    logic [4:0] mem_op;
    logic is_store;
    logic busy;
    logic done;
    logic load_request_valid;
    logic [31:0] address;
    logic [31:0] write_data;
    logic [3:0] write_enable;
    logic [5:0] load_metadata;
    logic [31:0] load_response_data;
    logic misaligned;

    logic mem_valid;
    logic commit_ready;
    logic mem_kill;
    logic mem_exception;
    logic commit_valid;
    logic [31:0] commit_address;
    logic [31:0] commit_write_data;
    logic [3:0] commit_write_enable;
    integer commit_count;

    always #1 clk = ~clk;

    lsu_exec_unit u_lsu (
        .clk(clk), .rst_n(rst_n), .start(start), .kill(kill),
        .response_valid(1'b0), .response_data(32'b0), .base(base),
        .store_data(store_data), .immediate(immediate), .mem_op(mem_op),
        .is_store(is_store), .busy(busy), .done(done),
        .load_request_valid(load_request_valid), .address(address),
        .write_data(write_data), .write_enable(write_enable),
        .load_metadata(load_metadata),
        .load_response_data(load_response_data), .misaligned(misaligned)
    );

    mem_store_commit u_commit (
        .resident_valid(mem_valid), .commit_ready(commit_ready),
        .resident_kill(mem_kill), .resident_exception(mem_exception),
        .is_store(load_metadata[0]), .address(address),
        .write_data(write_data), .write_enable(write_enable),
        .commit_valid(commit_valid), .commit_address(commit_address),
        .commit_write_data(commit_write_data),
        .commit_write_enable(commit_write_enable)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            commit_count <= 0;
        end else if (commit_valid) begin
            commit_count <= commit_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        kill = 1'b0;
        base = 32'b0;
        store_data = 32'b0;
        immediate = 32'b0;
        mem_op = 5'b0;
        is_store = 1'b0;
        mem_valid = 1'b0;
        commit_ready = 1'b0;
        mem_kill = 1'b0;
        mem_exception = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;

        // E0 forms a byte Store command but must not touch physical memory.
        base = 32'h2000;
        immediate = 32'd2;
        store_data = 32'h0000_00a5;
        mem_op = 5'b10000;
        is_store = 1'b1;
        start = 1'b1;
        #0.1;
        if (done || busy || load_request_valid || commit_valid ||
            (address != 32'h2002) || (write_data != 32'ha5a5_a5a5) ||
            (write_enable != 4'b0100) || (load_metadata != `SB)) begin
            $fatal(1, "Store E0 command formation mismatch");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;

        // E1 completes into EX/MEM, still without a physical write.
        if (!done || busy || commit_valid || (commit_count != 0)) begin
            $fatal(1, "Store E1 completion produced an early write");
        end
        mem_valid = 1'b1;
        repeat (2) begin
            @(posedge clk);
            #0.1;
            if (commit_valid || (commit_count != 0)) begin
                $fatal(1, "MEM backpressure repeated or advanced Store write");
            end
        end

        // The only physical write coincides with MEM acceptance.
        commit_ready = 1'b1;
        #0.1;
        if (!commit_valid || (commit_address != 32'h2002) ||
            (commit_write_data != 32'ha5a5_a5a5) ||
            (commit_write_enable != 4'b0100)) begin
            $fatal(1, "Store commit pulse/address/data/mask mismatch");
        end
        @(posedge clk);
        #0.1;
        mem_valid = 1'b0;
        commit_ready = 1'b0;
        #0.1;
        if (commit_valid || (commit_count != 1)) begin
            $fatal(1, "Store committed more than once");
        end

        // MEM kill and exception independently suppress the write.
        mem_valid = 1'b1;
        commit_ready = 1'b1;
        mem_kill = 1'b1;
        #0.1;
        if (commit_valid || (commit_write_enable != 4'b0)) begin
            $fatal(1, "killed Store escaped MEM commit gate");
        end
        mem_kill = 1'b0;
        mem_exception = 1'b1;
        #0.1;
        if (commit_valid || (commit_write_enable != 4'b0)) begin
            $fatal(1, "exceptional Store escaped MEM commit gate");
        end

        $display("LSU STORE COMMIT TEST PASSED");
        $finish;
    end

endmodule
