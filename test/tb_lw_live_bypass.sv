`include "defines.svh"

module tb_lw_live_bypass;
    logic clk;
    logic rst_n;
    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic imem_en;
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr;
    logic [3:0] dmem_wen;
    logic dmem_en;
    logic [31:0] dmem_wdata;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:127];
    integer live_issue_count;
    integer load_stall_count;

    function automatic [31:0] enc_i(
        input logic [11:0] imm,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        enc_i = {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_s(
        input logic [11:0] imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );
        enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic [31:0] enc_b(
        input logic [12:0] imm,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [6:0] opcode
    );
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], opcode};
    endfunction

    cpu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .plic_irq(1'b0),
        .debug_wb_pc(),
        .debug_wb_rf_addr(),
        .debug_wb_rf_data(),
        .debug_wb_rf_wen(),
        .debug_wb_fpu_rf_wen(),
        .debug_data()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        for (int i = 0; i < 64; i++) begin
            imem[i] = `NOP_INST;
        end
        for (int i = 0; i < 128; i++) begin
            dmem[i] = 32'b0;
        end

        imem[0]  = enc_i(12'd256, 5'd0, 3'b000, 5'd1, 7'b0010011); // addi x1,x0,256
        imem[1]  = enc_i(12'd0,   5'd1, 3'b010, 5'd5, 7'b0000011); // lw x5,0(x1)
        imem[2]  = enc_i(12'd3,   5'd5, 3'b000, 5'd6, 7'b0010011); // addi x6,x5,3
        imem[3]  = enc_i(12'd4,   5'd1, 3'b010, 5'd7, 7'b0000011); // lw x7,4(x1)
        imem[4]  = enc_r(7'b0, 5'd7, 5'd7, 3'b000, 5'd8, 7'b0110011); // add x8,x7,x7
        imem[5]  = enc_i(12'd8,   5'd1, 3'b010, 5'd9, 7'b0000011); // lw x9,8(x1)
        imem[6]  = enc_s(12'd12,  5'd9, 5'd1, 3'b010, 7'b0100011); // sw x9,12(x1)
        imem[7]  = enc_i(12'd16,  5'd1, 3'b010, 5'd10, 7'b0000011); // lw x10,16(x1)
        imem[8]  = enc_b(13'd8,   5'd0, 5'd10, 3'b000, 7'b1100011); // beq x10,x0,+8
        imem[9]  = enc_i(12'd1,   5'd0, 3'b000, 5'd12, 7'b0010011); // addi x12,x0,1
        imem[10] = enc_i(12'd24,  5'd1, 3'b000, 5'd13, 7'b0000011); // lb x13,24(x1)
        imem[11] = enc_i(12'd1,   5'd13, 3'b000, 5'd14, 7'b0010011); // addi x14,x13,1
        imem[12] = 32'h0000_006f; // jal x0,0

        dmem[64] = 32'd7;
        dmem[65] = 32'd9;
        dmem[66] = 32'd11;
        dmem[68] = 32'd1;
        dmem[70] = 32'h0000_007f;

        imem_rdata = `NOP_INST;
        dmem_rdata = 32'b0;
        live_issue_count = 0;
        load_stall_count = 0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n && imem_en) begin
            imem_rdata <= imem[imem_addr[7:2]];
        end
    end

    always @(posedge clk) begin
        if (rst_n && dmem_en) begin
            if (dmem_wen[0]) dmem[dmem_addr[8:2]][7:0] <= dmem_wdata[7:0];
            if (dmem_wen[1]) dmem[dmem_addr[8:2]][15:8] <= dmem_wdata[15:8];
            if (dmem_wen[2]) dmem[dmem_addr[8:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wen[3]) dmem[dmem_addr[8:2]][31:24] <= dmem_wdata[31:24];
            dmem_rdata <= dmem[dmem_addr[8:2]];
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_id_stage.ds_to_es_valid && dut.u_id_stage.es_allowin &&
                ((dut.u_id_stage.src1_fwd == 2'b11) ||
                 (dut.u_id_stage.src2_fwd == 2'b11))) begin
                live_issue_count <= live_issue_count + 1;
            end
            if (dut.u_id_stage.load_use_hazard) begin
                load_stall_count <= load_stall_count + 1;
            end
        end
    end

    initial begin
        wait (rst_n);
        fork
            begin
                wait (dut.u_regfiles.regfile[14] == 32'd128);
                repeat (3) @(posedge clk);

                assert (dut.u_regfiles.regfile[6] == 32'd10)
                    else $fatal(1, "LW->ADDI result mismatch");
                assert (dut.u_regfiles.regfile[8] == 32'd18)
                    else $fatal(1, "LW->ADD result mismatch");
                assert (dmem[67] == 32'd11)
                    else $fatal(1, "LW->SW result mismatch");
                assert (dut.u_regfiles.regfile[12] == 32'd1)
                    else $fatal(1, "LW->BEQ result mismatch");

                `ifdef LW_LIVE_BYPASS_ENABLE
                assert (live_issue_count == 2)
                    else $fatal(1, "expected 2 live issues, got %0d", live_issue_count);
                assert (load_stall_count == 3)
                    else $fatal(1, "expected 3 excluded stalls, got %0d", load_stall_count);
                `else
                assert (live_issue_count == 0)
                    else $fatal(1, "disabled bypass issued live forwarding");
                assert (load_stall_count == 5)
                    else $fatal(1, "expected 5 baseline stalls, got %0d", load_stall_count);
                `endif

                $display("PASS tb_lw_live_bypass live=%0d stalls=%0d",
                         live_issue_count, load_stall_count);
                $finish;
            end
            begin
                repeat (200) @(posedge clk);
                $fatal(1, "tb_lw_live_bypass timeout");
            end
        join_any
        disable fork;
    end
endmodule
