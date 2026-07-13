`timescale 1ns/1ps
`include "defines.svh"

module tb_lsu_four_beat_load;
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

    task automatic check_mem_extension(
        input logic [5:0] metadata,
        input logic [31:0] load_address,
        input logic [31:0] raw_data,
        input logic [31:0] expected
    );
        begin
            es_to_ms_bus = {
                32'h2000, 32'h0000_0003, load_address, raw_data,
                4'b0, 32'b0, metadata, 5'd5, 1'b1, 1'b0,
                2'b01, 1'b0, 12'b0, 32'b0
            };
            es_to_ms_valid = 1'b1;
            @(posedge clk);
            #0.1;
            es_to_ms_valid = 1'b0;
            if (!ms_valid || !ms_to_ws_valid ||
                (mem_result !== expected) || exception_code[5]) begin
                $fatal(1, "load extension mismatch metadata=%b addr=%h raw=%h got=%h expected=%h",
                       metadata, load_address, raw_data, mem_result, expected);
            end
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

        // E0: exactly one aligned word-load request.
        base = 32'h1000;
        immediate = 32'b0;
        mem_op = 5'b00100;
        start = 1'b1;
        #0.1;
        if (!load_request_valid || busy || done || misaligned ||
            (address != 32'h1000) || (load_metadata != `LW)) begin
            $fatal(1, "Load E0 request/metadata mismatch");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        #0.1;

        // E1: resident holds, no repeated request.
        if (!busy || done || load_request_valid || (request_count != 1)) begin
            $fatal(1, "Load E1 did not hold after a single request");
        end
        @(posedge clk);
        #0.1;

        // E2: bridge response becomes valid after its registered selection.
        if (!busy || done || (request_count != 1)) begin
            $fatal(1, "Load E2 resident state mismatch");
        end
        response_data = 32'h89ab_cdef;
        response_valid = 1'b1;
        @(posedge clk);
        #0.1;
        response_valid = 1'b0;

        // E3: data and metadata release together.
        if (busy || !done || (request_count != 1) ||
            (load_response_data != 32'h89ab_cdef) ||
            (address != 32'h1000) || (load_metadata != `LW)) begin
            $fatal(1, "Load E3 response/release mismatch");
        end
        repeat (2) begin
            @(posedge clk);
            #0.1;
            if (load_request_valid || (request_count != 1) ||
                (load_response_data != 32'h89ab_cdef)) begin
                $fatal(1, "completed Load request/data was not stable under hold");
            end
        end

        // A7.5.2: a younger LSU may remain in the same dispatch domain, but the
        // shared LSU must still serialize it as a new E0-E3 transaction.  The
        // second request cannot overlap or reuse any beat of the first one.
        base = 32'h1020;
        start = 1'b1;
        #0.1;
        if (!load_request_valid || busy || done ||
            (request_count != 1) || (address != 32'h1020)) begin
            $fatal(1, "chained Load E0 did not start a distinct request");
        end
        @(posedge clk);
        #0.1;
        start = 1'b0;
        #0.1;

        if (!busy || done || load_request_valid || (request_count != 2)) begin
            $fatal(1, "chained Load E1 mismatch busy=%b done=%b request=%b count=%0d",
                   busy, done, load_request_valid, request_count);
        end
        @(posedge clk);
        #0.1;

        if (!busy || done || load_request_valid || (request_count != 2)) begin
            $fatal(1, "chained Load E2 resident state mismatch");
        end
        response_data = 32'h1234_5678;
        response_valid = 1'b1;
        @(posedge clk);
        #0.1;
        response_valid = 1'b0;

        if (busy || !done || load_request_valid || (request_count != 2) ||
            (load_response_data != 32'h1234_5678) ||
            (address != 32'h1020)) begin
            $fatal(1, "chained Load E3 response/release mismatch");
        end

        check_mem_extension(`LW,  32'h1000, 32'h89ab_cdef, 32'h89ab_cdef);
        check_mem_extension(`LB,  32'h1003, 32'h807f_0180, 32'hffff_ff80);
        check_mem_extension(`LBU, 32'h1000, 32'h807f_0180, 32'h0000_0080);
        check_mem_extension(`LH,  32'h1002, 32'h8001_7fff, 32'hffff_8001);
        check_mem_extension(`LHU, 32'h1000, 32'h8001_7fff, 32'h0000_7fff);

        if (store_commit_valid) begin
            $fatal(1, "Load test unexpectedly committed a Store");
        end
        $display("LSU FOUR BEAT LOAD TEST PASSED");
        $finish;
    end

endmodule
