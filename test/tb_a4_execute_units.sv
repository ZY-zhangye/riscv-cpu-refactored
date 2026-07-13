`timescale 1ns/1ps
`include "defines.svh"

module tb_a4_execute_units;
    logic clk;
    logic rst_n;

    logic alu_start;
    logic alu_kill;
    logic [9:0] alu_op;
    logic [31:0] alu_src1;
    logic [31:0] alu_src2;
    logic alu_busy;
    logic alu_done;
    logic [31:0] alu_result;

    logic branch_start;
    logic branch_kill;
    logic [31:0] branch_pc;
    logic [31:0] branch_src1;
    logic [31:0] branch_src2;
    logic [31:0] branch_immediate;
    logic [31:0] branch_direct_target;
    logic [5:0] branch_opcode;
    logic branch_is_jal;
    logic branch_is_jalr;
    logic branch_pred_taken;
    logic [31:0] branch_pred_target;
    logic branch_busy;
    logic branch_done;
    logic branch_taken;
    logic [31:0] branch_target;
    logic branch_mispredict;
    logic [31:0] branch_redirect_target;

    logic lsu_start;
    logic lsu_kill;
    logic [31:0] lsu_base;
    logic [31:0] lsu_store_data;
    logic [31:0] lsu_immediate;
    logic [4:0] lsu_mem_op;
    logic lsu_is_store;
    logic lsu_busy;
    logic lsu_done;
    logic lsu_request_valid;
    logic [31:0] lsu_address;
    logic [31:0] lsu_write_data;
    logic [3:0] lsu_write_enable;
    logic [5:0] lsu_load_metadata;
    logic lsu_response_valid;
    logic [31:0] lsu_response_data;
    logic [31:0] lsu_load_response_data;
    logic lsu_misaligned;

    logic resident_valid;
    logic resident_kill;
    logic slot_replace;
    logic select_divider;
    logic resident_unit_busy;
    logic resident_unit_done;
    logic [31:0] resident_unit_result;
    logic resident_unit_start;
    logic resident_ready;
    logic [31:0] resident_result;
    logic resident_killed;
    logic resident_started;
    logic resident_completed;

    logic [31:0] md_src1;
    logic [31:0] md_src2;
    logic md_src1_signed;
    logic md_src2_signed;
    logic md_high_result;
    logic md_remainder;
    logic mul_busy;
    logic mul_done;
    logic [31:0] mul_result;
    logic div_busy;
    logic div_done;
    logic [31:0] div_result;

    integer start_count;
    integer done_count;

    always #1 clk = ~clk;

    alu_exec_unit u_alu (
        .start(alu_start), .kill(alu_kill), .op(alu_op),
        .src1(alu_src1), .src2(alu_src2), .busy(alu_busy),
        .done(alu_done), .result(alu_result)
    );

    branch_exec_unit u_branch (
        .start(branch_start), .kill(branch_kill), .pc(branch_pc),
        .src1(branch_src1), .src2(branch_src2),
        .immediate(branch_immediate),
        .direct_target(branch_direct_target),
        .branch_opcode(branch_opcode), .is_jal(branch_is_jal),
        .is_jalr(branch_is_jalr), .predicted_taken(branch_pred_taken),
        .predicted_target(branch_pred_target), .busy(branch_busy),
        .done(branch_done), .taken(branch_taken), .target(branch_target),
        .mispredict(branch_mispredict),
        .redirect_target(branch_redirect_target)
    );

    lsu_exec_unit u_lsu (
        .clk(clk), .rst_n(rst_n),
        .start(lsu_start), .kill(lsu_kill),
        .response_valid(lsu_response_valid),
        .response_data(lsu_response_data), .base(lsu_base),
        .store_data(lsu_store_data), .immediate(lsu_immediate),
        .mem_op(lsu_mem_op), .is_store(lsu_is_store), .busy(lsu_busy),
        .done(lsu_done), .load_request_valid(lsu_request_valid),
        .address(lsu_address), .write_data(lsu_write_data),
        .write_enable(lsu_write_enable),
        .load_metadata(lsu_load_metadata),
        .load_response_data(lsu_load_response_data),
        .misaligned(lsu_misaligned)
    );

    mul u_mul (
        .clk(clk), .rst_n(rst_n),
        .start(resident_unit_start && !select_divider),
        .kill(resident_killed), .src1(md_src1), .src2(md_src2),
        .src1_signed(md_src1_signed), .src2_signed(md_src2_signed),
        .high_result(md_high_result), .busy(mul_busy),
        .done(mul_done), .result(mul_result)
    );

    divider u_divider (
        .clk(clk), .rst_n(rst_n),
        .start(resident_unit_start && select_divider),
        .kill(resident_killed), .dividend(md_src1), .divisor(md_src2),
        .signed_mode(md_src1_signed && md_src2_signed),
        .remainder(md_remainder), .busy(div_busy),
        .done(div_done), .result(div_result)
    );

    assign resident_unit_busy = select_divider ? div_busy : mul_busy;
    assign resident_unit_done = select_divider ? div_done : mul_done;
    assign resident_unit_result = select_divider ? div_result : mul_result;

    ex_resident_control u_resident (
        .clk(clk), .rst_n(rst_n), .resident_valid(resident_valid),
        .resident_kill(resident_kill), .slot_replace(slot_replace),
        .unit_ready(1'b1),
        .unit_busy(resident_unit_busy), .unit_done(resident_unit_done),
        .unit_result(resident_unit_result), .unit_start(resident_unit_start),
        .resident_ready(resident_ready), .resident_result(resident_result),
        .resident_killed(resident_killed),
        .resident_started(resident_started),
        .resident_completed(resident_completed)
    );

    always @(posedge resident_unit_start) begin
        if (rst_n) begin
            start_count = start_count + 1;
        end
    end

    always @(posedge resident_unit_done) begin
        if (rst_n) begin
            done_count = done_count + 1;
        end
    end

    task automatic clear_resident;
        begin
            resident_valid = 1'b0;
            resident_kill = 1'b0;
            slot_replace = 1'b1;
            @(posedge clk);
            #0.1;
            slot_replace = 1'b0;
        end
    endtask

    task automatic wait_resident_ready(input integer max_cycles);
        integer cycle;
        begin
            cycle = 0;
            while (!resident_ready && (cycle < max_cycles)) begin
                @(posedge clk);
                #0.1;
                cycle = cycle + 1;
            end
            if (!resident_ready) begin
                $fatal(1, "resident did not complete within %0d cycles", max_cycles);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        alu_start = 1'b0;
        alu_kill = 1'b0;
        alu_op = `ALU_OP_ADD;
        alu_src1 = 32'b0;
        alu_src2 = 32'b0;
        branch_start = 1'b0;
        branch_kill = 1'b0;
        branch_pc = 32'b0;
        branch_src1 = 32'b0;
        branch_src2 = 32'b0;
        branch_immediate = 32'b0;
        branch_direct_target = 32'b0;
        branch_opcode = 6'b0;
        branch_is_jal = 1'b0;
        branch_is_jalr = 1'b0;
        branch_pred_taken = 1'b0;
        branch_pred_target = 32'b0;
        lsu_start = 1'b0;
        lsu_kill = 1'b0;
        lsu_base = 32'b0;
        lsu_store_data = 32'b0;
        lsu_immediate = 32'b0;
        lsu_mem_op = 5'b0;
        lsu_is_store = 1'b0;
        lsu_response_valid = 1'b0;
        lsu_response_data = 32'b0;
        resident_valid = 1'b0;
        resident_kill = 1'b0;
        slot_replace = 1'b0;
        select_divider = 1'b0;
        md_src1 = 32'b0;
        md_src2 = 32'b0;
        md_src1_signed = 1'b0;
        md_src2_signed = 1'b0;
        md_high_result = 1'b0;
        md_remainder = 1'b0;
        start_count = 0;
        done_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #0.1;

        alu_start = 1'b1;
        alu_op = `ALU_OP_SRA;
        alu_src1 = 32'hffff_fff0;
        alu_src2 = 32'd2;
        #0.1;
        if (alu_busy || !alu_done || (alu_result != 32'hffff_fffc)) begin
            $fatal(1, "ALU protocol/result mismatch");
        end
        alu_kill = 1'b1;
        #0.1;
        if (alu_done) begin
            $fatal(1, "killed ALU request completed");
        end
        alu_start = 1'b0;
        alu_kill = 1'b0;

        branch_start = 1'b1;
        branch_pc = 32'h1000;
        branch_src1 = 32'hffff_ffff;
        branch_src2 = 32'd1;
        branch_direct_target = 32'h1080;
        branch_opcode = 6'b001000;
        #0.1;
        if (!branch_done || !branch_taken || !branch_mispredict ||
            (branch_target != 32'h1080) ||
            (branch_redirect_target != 32'h1080)) begin
            $fatal(1, "signed branch resolution mismatch");
        end
        branch_is_jalr = 1'b1;
        branch_opcode = 6'b0;
        branch_src1 = 32'h2000;
        branch_immediate = 32'd3;
        #0.1;
        if (!branch_taken || (branch_target != 32'h2002)) begin
            $fatal(1, "JALR target masking mismatch");
        end
        branch_start = 1'b0;
        #0.1;
        if (branch_done || !branch_taken || !branch_mispredict ||
            (branch_target != 32'h2002)) begin
            $fatal(1, "completed branch metadata was not stable under hold");
        end
        branch_kill = 1'b1;
        #0.1;
        if (branch_done || branch_taken) begin
            $fatal(1, "killed branch produced a result");
        end
        branch_kill = 1'b0;
        branch_is_jalr = 1'b0;

        lsu_start = 1'b1;
        lsu_base = 32'h1000;
        lsu_immediate = 32'd3;
        lsu_store_data = 32'h0000_00a5;
        lsu_mem_op = 5'b10000;
        lsu_is_store = 1'b1;
        #0.1;
        if (lsu_done || lsu_request_valid ||
            (lsu_address != 32'h1003) ||
            (lsu_write_data != 32'ha5a5_a5a5) ||
            (lsu_write_enable != 4'b1000)) begin
            $fatal(1, "LSU Store E0 command mismatch");
        end
        @(posedge clk);
        #0.1;
        lsu_start = 1'b0;
        if (!lsu_done || lsu_busy || lsu_request_valid ||
            (lsu_address != 32'h1003) ||
            (lsu_write_enable != 4'b1000)) begin
            $fatal(1, "LSU Store E1 completion mismatch");
        end
        lsu_kill = 1'b1;
        #0.1;
        if (lsu_done || lsu_request_valid || (lsu_write_enable != 4'b0)) begin
            $fatal(1, "killed LSU request escaped");
        end
        lsu_kill = 1'b0;

        clear_resident();
        select_divider = 1'b0;
        md_src1 = 32'd7;
        md_src2 = 32'd9;
        md_src1_signed = 1'b0;
        md_src2_signed = 1'b0;
        md_high_result = 1'b0;
        resident_valid = 1'b1;
        #0.1;
        if (!resident_unit_start) begin
            $fatal(1, "multiply resident did not start");
        end
        @(posedge clk);
        #0.1;
        md_src1 = 32'd100;
        md_src2 = 32'd100;
        wait_resident_ready(10);
        if ((resident_result != 32'd63) || (start_count != 1) ||
            (done_count != 1)) begin
            $fatal(1, "multiply start/done or operand retention mismatch");
        end
        repeat (3) begin
            @(posedge clk);
            #0.1;
            if (!resident_ready || (resident_result != 32'd63) ||
                resident_unit_start || (start_count != 1) ||
                (done_count != 1)) begin
                $fatal(1, "completed multiply was not retained under hold");
            end
        end

        clear_resident();
        select_divider = 1'b1;
        md_src1 = 32'd100;
        md_src2 = 32'd7;
        md_src1_signed = 1'b0;
        md_src2_signed = 1'b0;
        md_remainder = 1'b0;
        resident_valid = 1'b1;
        @(posedge clk);
        #0.1;
        md_src1 = 32'd1;
        md_src2 = 32'd1;
        wait_resident_ready(20);
        if ((resident_result != 32'd14) || (start_count != 2) ||
            (done_count != 2)) begin
            $fatal(1, "divider start/done or forwarded operand latch mismatch");
        end
        repeat (2) @(posedge clk);
        #0.1;
        if ((start_count != 2) || (done_count != 2) ||
            (resident_result != 32'd14)) begin
            $fatal(1, "completed divide restarted during downstream hold");
        end

        clear_resident();
        select_divider = 1'b1;
        md_src1 = 32'h8000_0000;
        md_src2 = 32'hffff_ffff;
        md_src1_signed = 1'b1;
        md_src2_signed = 1'b1;
        md_remainder = 1'b0;
        resident_valid = 1'b1;
        #0.1;
        wait_resident_ready(4);
        if ((resident_result != 32'h8000_0000) ||
            (start_count != 3) || (done_count != 3)) begin
            $fatal(1, "signed divide overflow result mismatch");
        end

        clear_resident();
        select_divider = 1'b0;
        resident_valid = 1'b1;
        resident_kill = 1'b1;
        #0.1;
        if (resident_unit_start || !resident_ready || !resident_killed) begin
            $fatal(1, "kill-before-start resident protocol mismatch");
        end
        repeat (2) @(posedge clk);
        #0.1;
        if ((start_count != 3) || (done_count != 3) || mul_busy) begin
            $fatal(1, "killed resident started or waited for a unit");
        end

        clear_resident();
        select_divider = 1'b1;
        md_src1 = 32'd12345;
        md_src2 = 32'd37;
        md_src1_signed = 1'b0;
        md_src2_signed = 1'b0;
        md_remainder = 1'b0;
        resident_valid = 1'b1;
        @(posedge clk);
        #0.1;
        if (!div_busy || (start_count != 4)) begin
            $fatal(1, "kill-during-wait divider did not start");
        end
        resident_kill = 1'b1;
        #0.1;
        if (!resident_ready || !resident_killed) begin
            $fatal(1, "kill-during-wait did not release resident immediately");
        end
        @(posedge clk);
        #0.1;
        if (div_busy || (done_count != 3) || resident_unit_start) begin
            $fatal(1, "killed divider remained busy or completed");
        end

        $display("A4 EXECUTION UNIT TEST PASSED");
        $finish;
    end

endmodule
