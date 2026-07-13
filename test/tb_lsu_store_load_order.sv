`timescale 1ns/1ps

module tb_lsu_store_load_order;
    logic clk;
    logic rst_n;
    logic resident_valid;
    logic resident_kill;
    logic slot_replace;
    logic resident_start;
    logic resident_ready;
    logic [31:0] resident_result;
    logic resident_killed;
    logic resident_started;
    logic resident_completed;

    logic response_valid;
    logic [31:0] response_data;
    logic [31:0] base;
    logic [31:0] store_data;
    logic [31:0] immediate;
    logic [4:0] mem_op;
    logic is_store;
    logic lsu_busy;
    logic lsu_done;
    logic load_request_valid;
    logic [31:0] address;
    logic [31:0] write_data;
    logic [3:0] write_enable;
    logic [5:0] load_metadata;
    logic [31:0] load_response_data;
    logic misaligned;

    logic older_store_valid;
    logic older_store_ready;
    logic older_store_kill;
    logic older_store_exception;
    logic older_commit_valid;
    logic [31:0] older_commit_address;
    logic [31:0] older_commit_data;
    logic [3:0] older_commit_wen;
    integer older_commit_count;
    integer younger_start_count;
    integer younger_request_count;

    always #1 clk = ~clk;

    mem_store_commit u_older_store (
        .resident_valid(older_store_valid),
        .commit_ready(older_store_ready),
        .resident_kill(older_store_kill),
        .resident_exception(older_store_exception), .is_store(1'b1),
        .address(32'h3000), .write_data(32'h1122_3344),
        .write_enable(4'b1111), .commit_valid(older_commit_valid),
        .commit_address(older_commit_address),
        .commit_write_data(older_commit_data),
        .commit_write_enable(older_commit_wen)
    );

    lsu_exec_unit u_lsu (
        .clk(clk), .rst_n(rst_n), .start(resident_start),
        .kill(resident_killed), .response_valid(response_valid),
        .response_data(response_data), .base(base), .store_data(store_data),
        .immediate(immediate), .mem_op(mem_op), .is_store(is_store),
        .busy(lsu_busy), .done(lsu_done),
        .load_request_valid(load_request_valid), .address(address),
        .write_data(write_data), .write_enable(write_enable),
        .load_metadata(load_metadata),
        .load_response_data(load_response_data), .misaligned(misaligned)
    );

    ex_resident_control u_resident (
        .clk(clk), .rst_n(rst_n), .resident_valid(resident_valid),
        .resident_kill(resident_kill), .slot_replace(slot_replace),
        .unit_ready(!older_commit_valid), .unit_busy(lsu_busy),
        .unit_done(lsu_done), .unit_result(address),
        .unit_start(resident_start), .resident_ready(resident_ready),
        .resident_result(resident_result),
        .resident_killed(resident_killed),
        .resident_started(resident_started),
        .resident_completed(resident_completed)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            older_commit_count <= 0;
            younger_start_count <= 0;
            younger_request_count <= 0;
        end else begin
            if (older_commit_valid) older_commit_count <= older_commit_count + 1;
            if (resident_start) younger_start_count <= younger_start_count + 1;
            if (load_request_valid) younger_request_count <= younger_request_count + 1;
        end
    end

    task automatic clear_younger;
        begin
            resident_valid = 1'b0;
            resident_kill = 1'b0;
            slot_replace = 1'b1;
            @(posedge clk);
            #0.1;
            slot_replace = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        resident_valid = 1'b0;
        resident_kill = 1'b0;
        slot_replace = 1'b0;
        response_valid = 1'b0;
        response_data = 32'b0;
        base = 32'b0;
        store_data = 32'b0;
        immediate = 32'b0;
        mem_op = 5'b0;
        is_store = 1'b0;
        older_store_valid = 1'b0;
        older_store_ready = 1'b0;
        older_store_kill = 1'b0;
        older_store_exception = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;

        // An older Store commit owns the port; the younger Load is resident
        // but remains not-started and emits no request.
        older_store_valid = 1'b1;
        older_store_ready = 1'b1;
        base = 32'h4000;
        mem_op = 5'b00100;
        is_store = 1'b0;
        resident_valid = 1'b1;
        #0.1;
        if (!older_commit_valid || resident_start || load_request_valid ||
            resident_started || resident_ready) begin
            $fatal(1, "younger Load crossed an older Store commit");
        end
        @(posedge clk);
        #0.1;
        older_store_valid = 1'b0;
        #0.1;
        if (!resident_start || !load_request_valid ||
            (older_commit_count != 1)) begin
            $fatal(1, "younger Load request was lost after Store priority");
        end
        @(posedge clk);
        #0.1;
        if ((younger_start_count != 1) || (younger_request_count != 1) ||
            !lsu_busy) begin
            $fatal(1, "younger Load did not start exactly once");
        end
        response_data = 32'h5566_7788;
        response_valid = 1'b1;
        @(posedge clk);
        #0.1;
        response_valid = 1'b0;
        if (!resident_ready || (resident_result != 32'h4000) ||
            (load_response_data != 32'h5566_7788)) begin
            $fatal(1, "ordered younger Load did not complete");
        end

        clear_younger();

        // The same age rule applies when the younger operation is another Store.
        older_store_valid = 1'b1;
        older_store_ready = 1'b1;
        base = 32'h5000;
        immediate = 32'd1;
        store_data = 32'h0000_00cc;
        mem_op = 5'b10000;
        is_store = 1'b1;
        resident_valid = 1'b1;
        #0.1;
        if (resident_start || load_request_valid) begin
            $fatal(1, "younger Store crossed an older Store commit");
        end
        @(posedge clk);
        #0.1;
        older_store_valid = 1'b0;
        #0.1;
        if (!resident_start || load_request_valid) begin
            $fatal(1, "younger Store did not start after port release");
        end
        @(posedge clk);
        #0.1;
        if (!resident_ready || (write_enable != 4'b0010) ||
            (address != 32'h5001) || (younger_start_count != 2) ||
            (younger_request_count != 1) || (older_commit_count != 2)) begin
            $fatal(1, "ordered younger Store completion mismatch");
        end

        $display("LSU STORE LOAD ORDER TEST PASSED");
        $finish;
    end

endmodule
