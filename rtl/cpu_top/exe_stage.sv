`include "defines.svh"
module exe_stage(
    input logic clk,
    input logic rst_n,
    //握手信号
    input logic ds_to_es_valid,
    output logic es_allowin,
    input logic ms_allowin,
    output logic es_to_ms_valid,
    //来自ID阶段的信息
    input logic ds_flush,
    input logic [`DS_ES_WIDTH-1:0] ds_to_es_bus,
    //输出到MEM阶段的信息
    output logic [`ES_MS_WIDTH-1:0] es_to_ms_bus,
    output logic es_flush,
    //mem阶段数据前递接口
    input logic [31:0] mem_result,
    //reg_fpu数据3接口，仅在部分情况使用
    input logic [31:0] reg_fpu_data3,
    //DMEM接口
    input logic [31:0] dmem_rdata,
    input logic dmem_rvalid,
    input logic lsu_port_ready,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    //数据前递接口-仅地址
    output logic [4:0] exe_dest_addr,
    output logic exe_regfile_wen,
    output logic exe_reg_fpu_wen,
    output logic [11:0] exe_csr_addr,
    output logic exe_csr_wen,
    output logic exe_load_pending,
    output logic exe_result_pending,
    output logic es_valid,
    //异常接口
    input logic [`EXC_WIDTH-1:0] ds_exc_bus,
    output logic [`EXE_EXC_BUS - 1:0] exe_exc_bus,
    input logic exception_flag,
    //跳转接口
    output logic br_taken,
    output logic [31:0] br_target,
    output logic br_redirect,
    output logic [31:0] br_redirect_target,
    output logic bp_update_valid,
    output logic [31:0] bp_update_pc,
    output logic bp_update_taken,
    output logic [31:0] bp_update_target,
    output logic [`BP_TYPE_WIDTH-1:0] bp_update_type,
    //性能计数事件
    output logic branch_event,
    output logic branch_mispredict_event,
    output logic execute_stall_event
);

    logic es_ready_go;
    logic es_core_allowin;
    logic es_allowin_r;
    logic es_skid_valid_next;
    logic fpu_stall;
    logic is_alu;
    logic is_fpu;
    logic is_mul;
    logic is_mem;
    logic is_csr;
    logic is_br_jmp;
    logic is_bitman;
    logic resident_ready;
    logic resident_killed;
    logic resident_start;
    logic resident_started;
    logic resident_completed;
    logic [31:0] resident_result;
    logic selected_unit_busy;
    logic selected_unit_done;
    logic [31:0] selected_unit_result;
    logic selected_unit_ready;

    assign es_ready_go = is_fpu ? !fpu_stall : resident_ready;
    assign es_core_allowin = !es_valid || es_ready_go && ms_allowin;
    assign es_allowin = es_allowin_r;
    assign es_to_ms_valid = es_valid && es_ready_go;

    //锁存数据信号
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus_r;
    logic ds_flush_r;
    logic [31:0] exe_result;
    logic [31:0] csr_wdata;
    logic [31:0] csr_wdata_reg;
    logic [31:0] mem_result_reg;
    logic [31:0] exe_result_reg; 
    logic [31:0] reg_fpu_data3_reg;
    logic [`EXC_WIDTH-1:0] ds_exc_bus_r;  

    logic es_in_fire;
    logic skid_valid;
    logic [`DS_ES_WIDTH-1:0] skid_ds_to_es_bus;
    logic skid_ds_flush;
    logic [`EXC_WIDTH-1:0] skid_ds_exc_bus;
    logic [31:0] skid_exe_result;
    logic [31:0] skid_csr_wdata;
    logic [31:0] skid_mem_result;
    logic [31:0] skid_reg_fpu_data3;
    assign es_in_fire = ds_to_es_valid && es_allowin;

    always_comb begin
        es_skid_valid_next = skid_valid;
        if (exception_flag) begin
            es_skid_valid_next = 1'b0;
        end else if (es_core_allowin) begin
            es_skid_valid_next = 1'b0;
        end else if (es_in_fire && !skid_valid) begin
            es_skid_valid_next = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            es_valid <= 1'b0;
            es_allowin_r <= 1'b1;
            ds_to_es_bus_r <= '0;
            exe_result_reg <= '0;
            csr_wdata_reg <= '0;
            reg_fpu_data3_reg <= '0;
            ds_flush_r <= 1'b0;
            ds_exc_bus_r <= '0;
            mem_result_reg <= '0;
            skid_valid <= 1'b0;
            skid_ds_to_es_bus <= '0;
            skid_ds_flush <= 1'b0;
            skid_ds_exc_bus <= '0;
            skid_exe_result <= '0;
            skid_csr_wdata <= '0;
            skid_mem_result <= '0;
            skid_reg_fpu_data3 <= '0;
        end else begin
            skid_valid <= es_skid_valid_next;
            es_allowin_r <= !es_skid_valid_next;

            if (es_core_allowin) begin
                if (skid_valid) begin
                    es_valid <= 1'b1;
                    ds_flush_r <= skid_ds_flush;
                    ds_to_es_bus_r <= skid_ds_to_es_bus;
                    ds_exc_bus_r <= skid_ds_exc_bus;
                    exe_result_reg <= skid_exe_result;
                    csr_wdata_reg <= skid_csr_wdata;
                    mem_result_reg <= skid_mem_result;
                    reg_fpu_data3_reg <= skid_reg_fpu_data3;
                end else begin
                    es_valid <= es_in_fire;
                    if (es_in_fire) begin
                        ds_flush_r <= ds_flush;
                        ds_to_es_bus_r <= ds_to_es_bus;
                        ds_exc_bus_r <= ds_exc_bus;
                        exe_result_reg <= exe_result;
                        csr_wdata_reg <= csr_wdata;
                        mem_result_reg <= mem_result;
                        reg_fpu_data3_reg <= reg_fpu_data3;
                    end
                end
            end else if (es_in_fire && !skid_valid) begin
                skid_ds_flush <= ds_flush;
                skid_ds_to_es_bus <= ds_to_es_bus;
                skid_ds_exc_bus <= ds_exc_bus;
                skid_exe_result <= exe_result;
                skid_csr_wdata <= csr_wdata;
                skid_mem_result <= mem_result;
                skid_reg_fpu_data3 <= reg_fpu_data3;
            end
        end
    end
    assign es_flush = rst_n && resident_killed;
    //一级解包
    `ifdef Z_BITMAIN_ENABLE
        logic [`BITMAN_PACKET_WIDTH-1:0] bitman_packet;
    `endif
    logic [`ALU_PACKET_WIDTH-1:0] alu_packet;
    logic [`FPU_PACKET_WIDTH-1:0] fpu_packet;
    logic [`MUL_PACKET_WIDTH-1:0] mul_packet;
    logic [`MEM_PACKET_WIDTH-1:0] mem_packet;
    logic [`CSR_PACKET_WIDTH-1:0] csr_packet;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [`CTRL_PACKET_WIDTH-1:0] ctrl_packet;
    logic [`SRC_PACKET_WIDTH-1:0] src_packet;
    `ifdef Z_BITMAIN_ENABLE
        assign {bitman_packet, alu_packet, fpu_packet, mul_packet, mem_packet, csr_packet, br_jmp_packet, ctrl_packet , src_packet} = ds_to_es_bus_r;
    `else
        assign {alu_packet, fpu_packet, mul_packet, mem_packet, csr_packet, br_jmp_packet, ctrl_packet , src_packet} = ds_to_es_bus_r;
    `endif
    //二级解包
    //BITMAN_PACKET解包
    `ifdef Z_BITMAIN_ENABLE
        logic [`BITMAN_OP_WIDTH-1:0] bitman_op;
        assign bitman_op = bitman_packet;
    `endif
    //ALU_PACKET解包
    logic [9:0] alu_op;
    assign alu_op = alu_packet[9:0];
    //FPU_PACKET解包
    logic [31:0] fpu_src1, fpu_src2;
    logic [25:0] fpu_op;
    logic [2:0] rm;
    logic [1:0] fpu_src1_fwd;
    logic [1:0] fpu_src2_fwd;
    logic [1:0] fpu_src3_fwd;
    assign {fpu_op, rm, fpu_src1_fwd, fpu_src2_fwd, fpu_src3_fwd, fpu_src1, fpu_src2} = fpu_packet;
    //MUL_PACKET解包
    logic [3:0] mul_op;
    logic src1_signed, src2_signed;
    assign {mul_op, src1_signed, src2_signed} = mul_packet;
    //MEM_PACKET解包
    logic [31:0] mem_imm;
    logic [4:0] mem_op;
    logic is_store;
    assign {mem_imm, mem_op, is_store} = mem_packet;
    //CSR_PACKET解包
    logic [31:0] csr_rdata;
    logic [31:0] csr_imm;
    logic [11:0] csr_waddr;
    logic [2:0] csr_op;
    logic csr_wen;
    logic csr_imm_sel;
    logic csr_rdata_fwd;
    assign {csr_rdata, csr_imm, csr_waddr, csr_op, csr_imm_sel, csr_rdata_fwd, csr_wen} = csr_packet;
    //BR_JMP_PACKET解包
    logic [31:0] br_jmp_imm;
    logic [31:0] br_jmp_target;
    logic [5:0] br_jmp_opcode;
    logic is_jal, is_jalr;
    logic bp_pred_taken;
    logic [31:0] bp_pred_target;
    assign {bp_pred_taken, bp_pred_target, br_jmp_target, br_jmp_imm, br_jmp_opcode, is_jal, is_jalr} = br_jmp_packet;
    //CTRL_PACKET解包
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic reg_fpu_wen;
    logic is_multicycle;
    logic [1:0] exe_result_sel;
    logic [31:0] exe_pc;
    logic [31:0] exe_inst;
    assign {exe_pc, exe_inst, exe_result_sel, is_bitman, is_alu, is_fpu, is_mul, is_mem, is_csr, is_br_jmp, rd_addr, regfile_wen, reg_fpu_wen, is_multicycle} = ctrl_packet;
    //SRC_PACKET解包
    logic [31:0] reg_src1;
    logic [31:0] reg_src2;
    logic [1:0] src1_fwd;
    logic [1:0] src2_fwd;
    assign {reg_src1, reg_src2, src1_fwd, src2_fwd} = src_packet;

    //操作数选择（除FPU，其它都在这里完成）
    logic [31:0] src1, src2;
    logic [31:0] csr_data;
    always_comb begin
        src1 = 32'b0;
        unique case (1'b1)
            src1_fwd[0]: src1 = exe_result_reg;
            src1_fwd[1]: src1 = mem_result_reg;
            default: src1 = reg_src1;
        endcase
    end
    always_comb begin
        src2 = 32'b0;
        unique case (1'b1)
            src2_fwd[0]: src2 = exe_result_reg;
            src2_fwd[1]: src2 = mem_result_reg;
            default: src2 = reg_src2;
        endcase
    end
    /*
    assign src1 = (src1_fwd == 2'b01) ? exe_result_reg :
                  (src1_fwd == 2'b10) ? mem_result_reg :
                  reg_src1;
    assign src2 = (src2_fwd == 2'b01) ? exe_result_reg :
                  (src2_fwd == 2'b10) ? mem_result_reg :
                  reg_src2;*/
    assign csr_data = csr_rdata_fwd ? csr_wdata_reg : csr_rdata;

    //BITMAN计算
    `ifdef Z_BITMAIN_ENABLE
        logic [31:0] bitman_result;
        logic bm_sh1add, bm_sh2add, bm_sh3add;
        logic bm_andn, bm_orn, bm_xnor;
        logic bm_min, bm_max, bm_minu, bm_maxu;
        logic bm_sextb, bm_sexth, bm_zexth;
        logic bm_orcb, bm_rev8, bm_brev8, bm_pack, bm_packh, bm_zip, bm_unzip;
        logic bm_bclr, bm_bclri, bm_bext, bm_bexti, bm_binv, bm_binvi, bm_bset, bm_bseti;
        logic [4:0] bit_idx;
        logic [31:0] bit_mask;

        assign {
            bm_sh1add, bm_sh2add, bm_sh3add,
            bm_andn, bm_orn, bm_xnor,
            bm_min, bm_max, bm_minu, bm_maxu,
            bm_sextb, bm_sexth, bm_zexth,
            bm_orcb, bm_rev8, bm_brev8,
            bm_pack, bm_packh, bm_zip, bm_unzip,
            bm_bclr, bm_bclri, bm_bext, bm_bexti,
            bm_binv, bm_binvi, bm_bset, bm_bseti
        } = bitman_op;
        assign bit_idx = src2[4:0];
        assign bit_mask = 32'b1 << bit_idx;

        function automatic [7:0] reverse8(input logic [7:0] data);
            reverse8 = {data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]};
        endfunction

        function automatic [31:0] zip32(input logic [31:0] data);
            for (int i = 0; i < 16; i++) begin
                zip32[2*i] = data[i];
                zip32[2*i+1] = data[i+16];
            end
        endfunction

        function automatic [31:0] unzip32(input logic [31:0] data);
            for (int i = 0; i < 16; i++) begin
                unzip32[i] = data[2*i];
                unzip32[i+16] = data[2*i+1];
            end
        endfunction

        always_comb begin
            unique case (1'b1)
                bm_sh1add: bitman_result = (src1 << 1) + src2;
                bm_sh2add: bitman_result = (src1 << 2) + src2;
                bm_sh3add: bitman_result = (src1 << 3) + src2;
                bm_andn: bitman_result = src1 & ~src2;
                bm_orn: bitman_result = src1 | ~src2;
                bm_xnor: bitman_result = ~(src1 ^ src2);
                bm_min: bitman_result = ($signed(src1) < $signed(src2)) ? src1 : src2;
                bm_max: bitman_result = ($signed(src1) < $signed(src2)) ? src2 : src1;
                bm_minu: bitman_result = (src1 < src2) ? src1 : src2;
                bm_maxu: bitman_result = (src1 < src2) ? src2 : src1;
                bm_sextb: bitman_result = {{24{src1[7]}}, src1[7:0]};
                bm_sexth: bitman_result = {{16{src1[15]}}, src1[15:0]};
                bm_zexth: bitman_result = {16'b0, src1[15:0]};
                bm_orcb: bitman_result = {
                    {8{|src1[31:24]}},
                    {8{|src1[23:16]}},
                    {8{|src1[15:8]}},
                    {8{|src1[7:0]}}
                };
                bm_rev8: bitman_result = {src1[7:0], src1[15:8], src1[23:16], src1[31:24]};
                bm_brev8: bitman_result = {
                    reverse8(src1[31:24]),
                    reverse8(src1[23:16]),
                    reverse8(src1[15:8]),
                    reverse8(src1[7:0])
                };
                bm_pack: bitman_result = {src2[15:0], src1[15:0]};
                bm_packh: bitman_result = {16'b0, src2[7:0], src1[7:0]};
                bm_zip: bitman_result = zip32(src1);
                bm_unzip: bitman_result = unzip32(src1);
                bm_bclr, bm_bclri: bitman_result = src1 & ~bit_mask;
                bm_bext, bm_bexti: bitman_result = {31'b0, src1[bit_idx]};
                bm_binv, bm_binvi: bitman_result = src1 ^ bit_mask;
                bm_bset, bm_bseti: bitman_result = src1 | bit_mask;
                default: bitman_result = 32'b0;
            endcase
        end
    `else
        //如果不启用Z-bitman，bitman_result直接为0，不参与后续计算
        logic [31:0] bitman_result;
        assign bitman_result = 32'b0;
    `endif

    //ALU计算
    logic [31:0] alu_result;
    logic alu_busy;
    logic alu_done;
    alu_exec_unit u_alu (
        .start(resident_start && is_alu),
        .kill(resident_killed),
        .op(alu_op),
        .src1(src1),
        .src2(src2),
        .busy(alu_busy),
        .done(alu_done),
        .result(alu_result)
    );

    //MUL/DIV计算；两个共享单元由 resident 类型天然互斥。
    logic [31:0] mul_result;
    logic mul_busy;
    logic mul_done;
    logic [31:0] div_result;
    logic div_busy;
    logic div_done;
    logic mul_op_mul;
    logic mul_op_div;
    assign mul_op_mul = mul_op[3] || mul_op[2];
    assign mul_op_div = mul_op[1] || mul_op[0];

    mul u_mul (
        .clk(clk),
        .rst_n(rst_n),
        .start(resident_start && is_mul && mul_op_mul),
        .kill(resident_killed),
        .src1(src1),
        .src2(src2),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .high_result(mul_op[2]),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_result)
    );

    divider u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .start(resident_start && is_mul && mul_op_div),
        .kill(resident_killed),
        .dividend(src1),
        .divisor(src2),
        .signed_mode(src1_signed && src2_signed),
        .remainder(mul_op[0]),
        .busy(div_busy),
        .done(div_done),
        .result(div_result)
    );

    //FPU计算
    logic [31:0] fpu_result;
    logic [31:0] src1_fpu, src2_fpu, src3_fpu;
    assign src1_fpu = (fpu_src1_fwd == 2'b01) ? exe_result_reg :
                      (fpu_src1_fwd == 2'b10) ? mem_result_reg :
                      fpu_src1;
    assign src2_fpu = (fpu_src2_fwd == 2'b01) ? exe_result_reg :
                      (fpu_src2_fwd == 2'b10) ? mem_result_reg :
                      fpu_src2;
    assign src3_fpu = (fpu_src3_fwd == 2'b01) ? exe_result_reg :
                      (fpu_src3_fwd == 2'b10) ? mem_result_reg :
                      reg_fpu_data3_reg;
    fpu u_fpu (
        .clk(clk),
        .rst_n(rst_n),
        .is_fpu(is_fpu),
        .is_multicycle(is_multicycle),
        .fpu_op(fpu_op),
        .rm(rm),
        .fpu_src1(src1_fpu),
        .fpu_src2(src2_fpu),
        .fpu_src3(src3_fpu),
        .fpu_result(fpu_result),
        .fpu_stall(fpu_stall)
    );

    //MEM访问
    logic [5:0] lsu_load_metadata;
    logic lsu_busy;
    logic lsu_done;
    logic [31:0] lsu_store_wdata;
    logic [3:0] lsu_store_wen;
    logic [31:0] lsu_response_data;
    logic lsu_misaligned;
    lsu_exec_unit u_lsu (
        .clk(clk),
        .rst_n(rst_n),
        .start(resident_start && is_mem),
        .kill(resident_killed),
        .response_valid(dmem_rvalid),
        .response_data(dmem_rdata),
        .base(src1),
        .store_data(src2),
        .immediate(mem_imm),
        .mem_op(mem_op),
        .is_store(is_store),
        .busy(lsu_busy),
        .done(lsu_done),
        .load_request_valid(dmem_en),
        .address(dmem_addr),
        .write_data(lsu_store_wdata),
        .write_enable(lsu_store_wen),
        .load_metadata(lsu_load_metadata),
        .load_response_data(lsu_response_data),
        .misaligned(lsu_misaligned)
    );
    assign dmem_wen = 4'b0000;
    assign dmem_wdata = 32'b0;

    //CSR访问
    logic inst_csrrw, inst_csrrs, inst_csrrc, inst_csrrwi, inst_csrrsi, inst_csrrci;
    assign inst_csrrw  = csr_op == 3'b100 && csr_imm_sel == 1'b0;
    assign inst_csrrs  = csr_op == 3'b010 && csr_imm_sel == 1'b0;
    assign inst_csrrc  = csr_op == 3'b001 && csr_imm_sel == 1'b0;
    assign inst_csrrwi = csr_op == 3'b100 && csr_imm_sel == 1'b1;
    assign inst_csrrsi = csr_op == 3'b010 && csr_imm_sel == 1'b1;
    assign inst_csrrci = csr_op == 3'b001 && csr_imm_sel == 1'b1;
    assign exe_csr_wen = es_valid && csr_wen && !es_flush;
    assign exe_csr_addr = csr_waddr;
    assign csr_wdata = inst_csrrw ? src1 :
                       inst_csrrs ? (csr_data | src1) :
                       inst_csrrc ? (csr_data & ~src1) :
                       inst_csrrwi ? csr_imm :
                       inst_csrrsi ? (csr_data | csr_imm) :
                       inst_csrrci ? (csr_data & ~csr_imm) :
                       32'b0;
    
    //BR/JMP计算
    logic branch_resolve_fire;
    logic branch_busy;
    logic branch_done;
    logic branch_mispredict;

    branch_exec_unit u_branch (
        .start(resident_start && is_br_jmp),
        .kill(resident_killed),
        .pc(exe_pc),
        .src1(src1),
        .src2(src2),
        .immediate(br_jmp_imm),
        .direct_target(br_jmp_target),
        .branch_opcode(br_jmp_opcode),
        .is_jal(is_jal),
        .is_jalr(is_jalr),
        .predicted_taken(bp_pred_taken),
        .predicted_target(bp_pred_target),
        .busy(branch_busy),
        .done(branch_done),
        .taken(br_taken),
        .target(br_target),
        .mispredict(branch_mispredict),
        .redirect_target(br_redirect_target)
    );

    assign branch_resolve_fire = es_to_ms_valid && ms_allowin &&
                                 !es_flush && is_br_jmp;
    assign br_redirect = branch_resolve_fire && branch_mispredict;

    assign bp_update_valid = branch_resolve_fire;
    assign bp_update_pc = exe_pc;
    assign bp_update_taken = br_taken;
    assign bp_update_target = br_target;
    logic bp_update_is_call;
    logic bp_update_is_return;
    assign bp_update_is_call = (is_jal || is_jalr) &&
                               ((exe_inst[11:7] == 5'd1) ||
                                (exe_inst[11:7] == 5'd5));
    assign bp_update_is_return = is_jalr &&
                                 (exe_inst[11:7] == 5'd0) &&
                                 ((exe_inst[19:15] == 5'd1) ||
                                  (exe_inst[19:15] == 5'd5)) &&
                                 (exe_inst[31:20] == 12'd0);

    always_comb begin
        if (bp_update_is_return) begin
            bp_update_type = `BP_TYPE_RETURN;
        end else if (bp_update_is_call) begin
            bp_update_type = `BP_TYPE_CALL;
        end else if (is_jalr) begin
            bp_update_type = `BP_TYPE_JALR;
        end else if (is_jal) begin
            bp_update_type = `BP_TYPE_JAL;
        end else begin
            bp_update_type = `BP_TYPE_BRANCH;
        end
    end
    assign branch_event = branch_resolve_fire;
    assign branch_mispredict_event = branch_event && br_redirect;

    logic other_done;
    assign other_done = resident_start &&
                        !is_alu && !is_br_jmp && !is_mem &&
                        !is_mul && !is_fpu;
    assign selected_unit_ready = !is_mem || lsu_port_ready;
    assign selected_unit_busy = (is_mul && mul_op_mul) ? mul_busy :
                                (is_mul && mul_op_div) ? div_busy :
                                alu_busy || branch_busy || lsu_busy;
    assign selected_unit_done = alu_done || branch_done || lsu_done ||
                                mul_done || div_done || other_done;

    always_comb begin
        unique case (1'b1)
            is_bitman: selected_unit_result = bitman_result;
            is_alu: selected_unit_result = alu_result;
            is_mem: selected_unit_result = dmem_addr;
            is_mul && mul_op_mul: selected_unit_result = mul_result;
            is_mul && mul_op_div: selected_unit_result = div_result;
            is_csr: selected_unit_result = csr_data;
            default: selected_unit_result = exe_pc + 32'd4;
        endcase
    end

    ex_resident_control u_resident_control (
        .clk(clk),
        .rst_n(rst_n),
        .resident_valid(es_valid && !is_fpu),
        .resident_kill(ds_flush_r || exception_flag),
        .slot_replace(es_core_allowin),
        .unit_ready(selected_unit_ready),
        .unit_busy(selected_unit_busy),
        .unit_done(selected_unit_done),
        .unit_result(selected_unit_result),
        .unit_start(resident_start),
        .resident_ready(resident_ready),
        .resident_result(resident_result),
        .resident_killed(resident_killed),
        .resident_started(resident_started),
        .resident_completed(resident_completed)
    );

    //结果选择
    always_comb begin
        exe_result = 32'b0;
        if (!es_flush) begin
            exe_result = is_fpu ? fpu_result : resident_result;
        end
    end

    //数据前递接口
    assign exe_dest_addr = rd_addr;
    assign exe_regfile_wen = es_valid && regfile_wen && !es_flush;
    assign exe_reg_fpu_wen = es_valid && reg_fpu_wen && !es_flush;
    assign exe_load_pending = es_valid && !es_flush && exe_result_sel[0] &&
                              (regfile_wen || reg_fpu_wen);
    assign exe_result_pending = es_valid && !es_flush && !es_ready_go;
    assign execute_stall_event = exe_result_pending;

    logic [5:0] es_lsu_metadata;
    logic [31:0] es_lsu_response_data;
    logic [3:0] es_store_wen;
    logic [31:0] es_store_wdata;
    assign es_lsu_metadata = is_mem ? lsu_load_metadata : 6'b0;
    assign es_lsu_response_data = (is_mem && !is_store) ?
                                  lsu_response_data : 32'b0;
    assign es_store_wen = (is_mem && is_store) ? lsu_store_wen : 4'b0;
    assign es_store_wdata = (is_mem && is_store) ? lsu_store_wdata : 32'b0;

    //输出到下一级
    assign es_to_ms_bus = {
        exe_pc,     //32
        exe_inst,   //32
        exe_result, //32
        es_lsu_response_data,
        es_store_wen,
        es_store_wdata,
        es_lsu_metadata,
        rd_addr,
        regfile_wen,
        reg_fpu_wen,
        exe_result_sel,
        exe_csr_wen,
        exe_csr_addr,
        csr_wdata
    };

    //异常接口
    //exe阶段产生的异常均为地址非对齐异常，由于exe阶段时序压力，故不在此做处理，而是传递给mem阶段处理
    logic [32:0] br_bus;
    assign br_bus = {br_taken, br_target};
    assign exe_exc_bus = {br_bus, ds_exc_bus_r};

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && resident_killed && resident_start) begin
            $fatal(1, "killed EX resident attempted to start a unit");
        end
        if (rst_n && dmem_en && (!resident_start || resident_killed)) begin
            $fatal(1, "LSU request was not a live resident start pulse");
        end
        if (rst_n && (dmem_wen != 4'b0000)) begin
            $fatal(1, "Store write enable escaped EX before MEM commit");
        end
        if (rst_n && resident_killed &&
            (branch_resolve_fire || exe_csr_wen || dmem_en)) begin
            $fatal(1, "killed EX resident produced an architectural side effect");
        end
    end
`endif


endmodule
