`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"

module tb_mem_commit;
    logic clk;
    logic rst_n;
    logic es_flush;
    logic [`ES_MS_WIDTH-1:0] es_to_ms_bus;
    logic [`MS_WS_WIDTH-1:0] ms_to_ws_bus;
    logic es_to_ms_valid;
    logic ms_to_ws_valid;
    logic ms_allowin;
    logic ws_allowin;
    logic ms_valid;
    logic [31:0] dmem_rdata;
    logic commit_kill;
    logic store_commit_valid;
    logic [31:0] store_commit_pc;
    logic [31:0] store_commit_addr;
    logic [3:0] store_commit_wen;
    logic [31:0] store_commit_wdata;
    logic [4:0] mem_dst_addr;
    logic mem_regfile_wen;
    logic mem_reg_fpu_wen;
    logic [31:0] mem_result;
    logic [`EXE_EXC_BUS-1:0] exe_exc_bus;
    logic csr_we;
    logic [11:0] csr_waddr;
    logic [31:0] csr_wdata;
    logic [6:0] exception_code;
    logic [31:0] exception_mtval;
    logic [1:0] retire_count;
    int failures;

    mem_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .es_flush(es_flush),
        .es_to_ms_bus(es_to_ms_bus),
        .ms_to_ws_bus(ms_to_ws_bus),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_allowin(ms_allowin),
        .ws_allowin(ws_allowin),
        .ms_valid(ms_valid),
        .dmem_rdata(dmem_rdata),
        .commit_kill(commit_kill),
        .store_commit_valid(store_commit_valid),
        .store_commit_pc(store_commit_pc),
        .store_commit_addr(store_commit_addr),
        .store_commit_wen(store_commit_wen),
        .store_commit_wdata(store_commit_wdata),
        .mem_dst_addr(mem_dst_addr),
        .mem_regfile_wen(mem_regfile_wen),
        .mem_reg_fpu_wen(mem_reg_fpu_wen),
        .mem_result(mem_result),
        .exception_flag(1'b0),
        .exe_exc_bus(exe_exc_bus),
        .plic_irq(1'b0),
        .external_irq_enable(1'b0),
        .csr_we(csr_we),
        .csr_waddr(csr_waddr),
        .csr_wdata(csr_wdata),
        .exception_code(exception_code),
        .exception_mtval(exception_mtval),
        .retire_count(retire_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [`ES_MS_WIDTH-1:0] make_bus(
        input logic [31:0] pc,
        input logic [31:0] addr,
        input logic [5:0] load_inst,
        input logic [3:0] store_wen,
        input logic [31:0] store_data,
        input logic [4:0] rd,
        input logic reg_wen
    );
        make_bus = {
            pc,
            `NOP_INST,
            addr,
            load_inst,
            store_wen,
            store_data,
            rd,
            reg_wen,
            1'b0,
            2'b10,
            1'b0,
            12'b0,
            32'b0
        };
    endfunction

    task automatic check(input string name, input logic condition);
        if (!condition) begin
            failures++;
            $display("MEM_COMMIT_CHECK_FAIL %s time=%0t", name, $time);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            es_flush = 1'b0;
            es_to_ms_bus = '0;
            es_to_ms_valid = 1'b0;
            ws_allowin = 1'b1;
            dmem_rdata = 32'h1234_5678;
            commit_kill = 1'b0;
            exe_exc_bus = '0;
            repeat (2) @(posedge clk);
            #1 rst_n = 1'b1;
        end
    endtask

    task automatic send_bus(input logic [`ES_MS_WIDTH-1:0] bus);
        begin
            @(negedge clk);
            check("mem ready", ms_allowin);
            es_to_ms_bus = bus;
            es_to_ms_valid = 1'b1;
            @(posedge clk);
            #1;
            es_to_ms_valid = 1'b0;
        end
    endtask

    initial begin
        failures = 0;

        reset_dut();
        send_bus(make_bus(32'h8000_0100, 32'h0000_0020, `SW,
                          4'b1111, 32'hdead_beef, 5'b0, 1'b0));
        check("aligned store commits", store_commit_valid);
        check("aligned store PC", store_commit_pc == 32'h8000_0100);
        check("aligned store address", store_commit_addr == 32'h0000_0020);
        check("aligned store mask", store_commit_wen == 4'b1111);
        check("aligned store data", store_commit_wdata == 32'hdead_beef);
        check("aligned store retires", retire_count == 2'd1);

        reset_dut();
        send_bus(make_bus(32'h8000_0200, 32'h0000_0022, `SW,
                          4'b1111, 32'hcafe_babe, 5'b0, 1'b0));
        check("misaligned store exception", exception_code == `EXC_SAM);
        check("misaligned store mtval", exception_mtval == 32'h0000_0022);
        check("misaligned store suppressed", !store_commit_valid);
        check("misaligned store not retired", retire_count == 2'd0);

        reset_dut();
        commit_kill = 1'b1;
        send_bus(make_bus(32'h8000_0300, 32'h0000_0024, `SW,
                          4'b1111, 32'h1122_3344, 5'b0, 1'b0));
        check("younger killed store suppressed", !store_commit_valid);
        check("younger killed store not retired", retire_count == 2'd0);

        reset_dut();
        commit_kill = 1'b1;
        send_bus(make_bus(32'h8000_0400, 32'h0000_0055, 6'b0,
                          4'b0, 32'b0, 5'd6, 1'b1));
        check("younger killed GPR write suppressed", !mem_regfile_wen);
        check("younger killed ALU not retired", retire_count == 2'd0);

        if (failures == 0) begin
            $display("MEM_COMMIT_TEST_PASSED");
        end else begin
            $fatal(1, "MEM_COMMIT_TEST_FAILED failures=%0d", failures);
        end
        $finish;
    end

endmodule
