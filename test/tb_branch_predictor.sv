`timescale 1ns/1ps
`include "defines.svh"

module tb_branch_predictor;
    localparam int CLK_PERIOD_NS = 10;

    logic clk;
    logic rst_n;
    logic [`ADDR_WIDTH-1:0] lookup_pc0;
    logic pred_taken0;
    logic [`ADDR_WIDTH-1:0] pred_target0;
    logic [`ADDR_WIDTH-1:0] lookup_pc1;
    logic pred_taken1;
    logic [`ADDR_WIDTH-1:0] pred_target1;
    logic update_valid;
    logic [`ADDR_WIDTH-1:0] update_pc;
    logic update_taken;
    logic [`ADDR_WIDTH-1:0] update_target;
    logic update_is_jalr;

    int errors;

    branch_predictor #(
        .INDEX_WIDTH(6)
    ) u_branch_predictor (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_pc0(lookup_pc0),
        .pred_taken0(pred_taken0),
        .pred_target0(pred_target0),
        .lookup_pc1(lookup_pc1),
        .pred_taken1(pred_taken1),
        .pred_target1(pred_target1),
        .update_valid(update_valid),
        .update_pc(update_pc),
        .update_taken(update_taken),
        .update_target(update_target),
        .update_is_jalr(update_is_jalr)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    task automatic check(input string name, input logic cond);
        begin
            if (!cond) begin
                errors++;
                $display("[FAIL] %s", name);
            end else begin
                $display("[PASS] %s", name);
            end
        end
    endtask

    task automatic apply_update(
        input logic [`ADDR_WIDTH-1:0] pc,
        input logic taken,
        input logic [`ADDR_WIDTH-1:0] target,
        input logic is_jalr
    );
        begin
            @(negedge clk);
            update_valid = 1'b1;
            update_pc = pc;
            update_taken = taken;
            update_target = target;
            update_is_jalr = is_jalr;
            @(negedge clk);
            update_valid = 1'b0;
            update_pc = '0;
            update_taken = 1'b0;
            update_target = '0;
            update_is_jalr = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        lookup_pc0 = 32'h0000_0100;
        lookup_pc1 = 32'h0000_0104;
        update_valid = 1'b0;
        update_pc = '0;
        update_taken = 1'b0;
        update_target = '0;
        update_is_jalr = 1'b0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        check("cold lane0 lookup predicts not taken", !pred_taken0);
        check("cold lane1 lookup predicts not taken", !pred_taken1);

        apply_update(32'h0000_0100, 1'b1, 32'h0000_0200, 1'b0);
        lookup_pc0 = 32'h0000_0100;
        lookup_pc1 = 32'h0000_0104;
        #1;
        check("new taken update predicts taken on lane0", pred_taken0);
        check("taken update target is visible on lane0", pred_target0 == 32'h0000_0200);
        check("untrained lane1 remains not taken", !pred_taken1);

        apply_update(32'h0000_0104, 1'b1, 32'h0000_0300, 1'b0);
        #1;
        check("second lookup port predicts trained lane1", pred_taken1);
        check("second lookup port target is visible", pred_target1 == 32'h0000_0300);

        apply_update(32'h0000_0100, 1'b0, 32'h0000_0200, 1'b0);
        #1;
        check("one not-taken from weak taken predicts not taken", !pred_taken0);

        apply_update(32'h0000_0100, 1'b1, 32'h0000_0200, 1'b0);
        apply_update(32'h0000_0100, 1'b1, 32'h0000_0200, 1'b0);
        #1;
        check("two taken updates predict taken", pred_taken0);

        apply_update(32'h0000_0100, 1'b0, 32'h0000_0200, 1'b0);
        #1;
        check("strong taken survives one not-taken", pred_taken0);

        apply_update(32'h0000_0100, 1'b0, 32'h0000_0200, 1'b0);
        #1;
        check("second not-taken drops to not taken", !pred_taken0);

        lookup_pc0 = 32'h0001_0100;
        #1;
        check("same index different tag misses", !pred_taken0);

        apply_update(32'h0000_0300, 1'b1, 32'h0000_0400, 1'b1);
        lookup_pc0 = 32'h0000_0300;
        #1;
        check("jalr update is ignored", !pred_taken0);

        if (errors == 0) begin
            $display("tb_branch_predictor PASSED");
        end else begin
            $display("tb_branch_predictor FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
