`timescale 1ns/1ps
`include "defines.svh"

module tb_lsu_exception_age;
    logic clk;
    logic rst_n;
    logic start;
    logic kill;
    logic response_valid;
    logic [31:0] response_data;
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
    integer request_count;

    logic es_flush;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus;
    logic es_to_ms_valid;
    logic ms_to_ws_valid;
    logic ms_allowin;
    logic ws_allowin;
    logic ms_valid;
    logic [4:0] mem_dst_addr;
    logic mem_regfile_wen;
    logic mem_reg_fpu_wen;
    logic [31:0] mem_result;
    logic csr_we;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic [1:0] retire_count;
    logic store_commit_valid;
    logic [31:0] store_commit_pc;
    logic [31:0] store_commit_addr;
    logic [3:0] store_commit_wen;
    logic [31:0] store_commit_wdata;

    always #1 clk = ~clk;

    lsu_exec_unit u_lsu (
        .clk(clk), .rst_n(rst_n), .start(start), .kill(kill),
        .response_valid(response_valid), .response_data(response_data),
        .base(base), .store_data(store_data), .immediate(immediate),
        .mem_op(mem_op), .is_store(is_store), .busy(busy), .done(done),
        .load_request_valid(load_request_valid), .address(address),
        .write_data(write_data), .write_enable(write_enable),
        .load_metadata(load_metadata),
        .load_response_data(load_response_data), .misaligned(misaligned)
    );

    mem_stage u_mem (
        .clk(clk), .rst_n(rst_n), .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus), .ms_to_ws_bus(ms_to_ws_bus),
        .es_to_ms_valid(es_to_ms_valid), .ms_to_ws_valid(ms_to_ws_valid),
        .ms_allowin(ms_allowin), .ws_allowin(ws_allowin),
        .ms_valid(ms_valid), .mem_dst_addr(mem_dst_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .mem_reg_fpu_wen(mem_reg_fpu_wen), .mem_result(mem_result),
        .exception_flag(1'b0), .exe_exc_bus('0), .plic_irq(1'b0),
        .external_irq_enable(1'b0), .csr_we(csr_we),
        .csr_waddr(csr_waddr), .csr_wdata(csr_wdata),
        .exception_code(exception_code), .exception_mtval(exception_mtval),
        .retire_count(retire_count), .store_commit_valid(store_commit_valid),
        .store_commit_pc(store_commit_pc),
        .store_commit_addr(store_commit_addr),
        .store_commit_wen(store_commit_wen),
        .store_commit_wdata(store_commit_wdata)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            request_count <= 0;
        end else if (load_request_valid) begin
            request_count <= request_count + 1;
        end
    end

    task automatic feed_mem_access(
        input logic flush_value,
        input logic [31:0] access_address,
        input logic [5:0] metadata,
        input logic [3:0] store_mask,
        input logic reg_write
    );
        begin
            es_to_ms_bus = {
                32'h6000, 32'h0000_0003, access_address, 32'hdead_beef,
                store_mask, 32'h1234_5678, metadata, 5'd9,
                reg_write, 1'b0, 2'b01, 1'b0, 12'b0, 32'b0
            };
            es_flush = flush_value;
            es_to_ms_valid = 1'b1;
            @(posedge clk);
            #0.1;
            es_to_ms_valid = 1'b0;
        end
    endtask

    task automatic drain_mem;
        begin
            es_flush = 1'b0;
            @(posedge clk);
            #0.1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        kill = 1'b0;
        response_valid = 1'b0;
        response_data = 32'b0;
        base = 32'b0;
        store_data = 32'b0;
        immediate = 32'b0;
        mem_op = 5'b0;
        is_store = 1'b0;
        es_flush = 1'b0;
        es_to_ms_bus = '0;
        es_to_ms_valid = 1'b0;
        ws_allowin = 1'b1;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;

        // E0 detects misaligned LW and must not issue a memory request.
        base = 32'h7000;
        immediate = 32'd2;
        mem_op = 5'b00100;
        is_store = 1'b0;
        start = 1'b1;
        #0.1;
        if (!misaligned || load_request_valid || done || busy) begin
            $fatal(1, "misaligned Load escaped E0 request suppression");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        if (!done || (request_count != 0)) begin
            $fatal(1, "misaligned Load did not complete locally");
        end

        // MEM reports LAM and suppresses forwarding, writeback and retire.
        feed_mem_access(1'b0, 32'h7002, `LW, 4'b0, 1'b1);
        if (exception_code != `EXC_LAM || ms_to_ws_valid ||
            mem_regfile_wen || (retire_count != 0) || store_commit_valid ||
            (exception_mtval != 32'h7002)) begin
            $fatal(1, "misaligned Load precise exception mismatch");
        end
        drain_mem();

        // Misaligned Store reaches MEM as metadata only and never writes/retires.
        feed_mem_access(1'b0, 32'h8002, `SW, 4'b1111, 1'b0);
        if (exception_code != `EXC_SAM || ms_to_ws_valid ||
            (retire_count != 0) || store_commit_valid ||
            (store_commit_wen != 4'b0) ||
            (exception_mtval != 32'h8002)) begin
            $fatal(1, "misaligned Store precise exception mismatch");
        end
        drain_mem();

        // A killed aligned Store has no exception, commit or retirement.
        feed_mem_access(1'b1, 32'h9000, `SW, 4'b1111, 1'b0);
        if (store_commit_valid || ms_to_ws_valid || (retire_count != 0) ||
            (store_commit_wen != 4'b0)) begin
            $fatal(1, "killed Store produced a MEM side effect");
        end
        drain_mem();

        // kill-before-start: no request, no busy wait, no completion.
        base = 32'ha000;
        immediate = 32'b0;
        mem_op = 5'b00100;
        is_store = 1'b0;
        kill = 1'b1;
        start = 1'b1;
        #0.1;
        if (load_request_valid || busy || done) begin
            $fatal(1, "kill-before-start LSU side effect");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        kill = 1'b0;

        // kill-during-wait cancels the resident.  A stale response may arrive
        // on the same edge that a replacement Load starts; start must win so
        // the stale payload cannot complete the younger resident.
        start = 1'b1;
        #0.1;
        if (!load_request_valid) begin
            $fatal(1, "aligned Load did not issue before kill-during-wait");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        if (!busy || (request_count != 1)) begin
            $fatal(1, "aligned Load was not waiting before kill");
        end
        kill = 1'b1;
        #0.1;
        if (done || load_request_valid) begin
            $fatal(1, "killed waiting Load completed or re-requested");
        end
        @(posedge clk);
        #0.1;
        kill = 1'b0;
        base = 32'ha004;
        start = 1'b1;
        response_data = 32'hcafe_babe;
        response_valid = 1'b1;
        #0.1;
        if (!load_request_valid) begin
            $fatal(1, "replacement Load did not start beside stale response");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        response_valid = 1'b0;
        if (!busy || done || (request_count != 2) ||
            (load_response_data == 32'hcafe_babe)) begin
            $fatal(1, "stale response matched the replacement Load");
        end

        response_data = 32'h1234_5678;
        response_valid = 1'b1;
        @(posedge clk);
        #0.1;
        response_valid = 1'b0;
        if (busy || !done || (request_count != 2) ||
            (load_response_data != 32'h1234_5678)) begin
            $fatal(1, "replacement Load did not wait for its own response");
        end

        $display("LSU EXCEPTION AGE TEST PASSED");
        $finish;
    end

endmodule
