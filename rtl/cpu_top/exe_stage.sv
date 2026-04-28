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
    output logic es_valid,
    //异常接口
    input logic [`EXC_WIDTH-1:0] ds_exc_bus,
    output logic [`EXE_EXC_BUS - 1:0] exe_exc_bus,
    input logic exception_flag,
    //跳转接口
    output logic br_taken,
    output logic [31:0] br_target
);

    logic es_ready_go;
    logic mul_stall;
    logic fpu_stall;
    assign es_ready_go = !mul_stall && !fpu_stall;
    assign es_allowin = !es_valid || es_ready_go && ms_allowin;
    assign es_to_ms_valid = es_valid && es_ready_go;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            es_valid <= 1'b0;
        end else if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end
    end

    //锁存数据信号
    logic [`DS_ES_WIDTH-1:0] ds_to_es_bus_r;
    logic ds_flush_r;
    logic [31:0] exe_result;
    logic [31:0] csr_wdata;
    logic [31:0] csr_wdata_reg;
    logic [31:0] mem_result_reg;
    logic [31:0] exe_result_reg; 
    logic [`EXC_WIDTH-1:0] ds_exc_bus_r;  
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ds_to_es_bus_r <= '0;
            exe_result_reg <= '0;
            csr_wdata_reg <= '0;
            ds_flush_r <= 1'b0;
            ds_exc_bus_r <= '0;
        end else if (ds_to_es_valid && es_allowin) begin
            ds_flush_r <= ds_flush;
            ds_to_es_bus_r <= ds_to_es_bus;
            ds_exc_bus_r <= ds_exc_bus;
            exe_result_reg <= exe_result;
            csr_wdata_reg <= csr_wdata;
        end else begin
            exe_result_reg <= exe_result;
            csr_wdata_reg <= csr_wdata;
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_result_reg <= '0;
        end else if (ds_to_es_valid && es_allowin) begin
            mem_result_reg <= mem_result;
        end else begin
            mem_result_reg <= mem_result;
        end
    end
    assign es_flush = rst_n && (ds_flush_r || exception_flag);
    //一级解包
    logic [`ALU_PACKET_WIDTH-1:0] alu_packet;
    logic [`FPU_PACKET_WIDTH-1:0] fpu_packet;
    logic [`MUL_PACKET_WIDTH-1:0] mul_packet;
    logic [`MEM_PACKET_WIDTH-1:0] mem_packet;
    logic [`CSR_PACKET_WIDTH-1:0] csr_packet;
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [`CTRL_PACKET_WIDTH-1:0] ctrl_packet;
    logic [`SRC_PACKET_WIDTH-1:0] src_packet;
    assign {alu_packet, fpu_packet, mul_packet, mem_packet, csr_packet, br_jmp_packet, ctrl_packet , src_packet} = ds_to_es_bus_r;
    //二级解包
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
    assign {br_jmp_target, br_jmp_imm, br_jmp_opcode, is_jal, is_jalr} = br_jmp_packet;
    //CTRL_PACKET解包
    logic is_alu, is_fpu, is_mul, is_mem, is_csr, is_br_jmp;
    logic [4:0] rd_addr;
    logic regfile_wen;
    logic reg_fpu_wen;
    logic is_multicycle;
    logic [1:0] exe_result_sel;
    logic [31:0] exe_pc;
    assign {exe_pc, exe_result_sel,is_alu, is_fpu, is_mul, is_mem, is_csr, is_br_jmp, rd_addr, regfile_wen, reg_fpu_wen, is_multicycle} = ctrl_packet;
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

    //ALU计算
    logic [31:0] alu_result;
    always_comb begin
        case (alu_op)
            `ALU_OP_ADD: alu_result = src1 + src2;
            `ALU_OP_SUB: alu_result = src1 - src2;
            `ALU_OP_AND: alu_result = src1 & src2;
            `ALU_OP_OR:  alu_result = src1 | src2;
            `ALU_OP_XOR: alu_result = src1 ^ src2;
            `ALU_OP_SLL: alu_result = src1 << src2[4:0];
            `ALU_OP_SRL: alu_result = src1 >> src2[4:0];
            `ALU_OP_SRA: alu_result = $signed(src1) >>> src2[4:0];
            `ALU_OP_SLT: alu_result = ($signed(src1) < $signed(src2)) ? 32'b1 : 32'b0;
            `ALU_OP_SLTU: alu_result = (src1 < src2) ? 32'b1 : 32'b0;
            default: alu_result = 32'b0;
        endcase
    end

    //MUL计算
    logic [31:0] mul_result;
    mul u_mul (
        .clk(clk),
        .rst_n(rst_n),
        .is_mul(is_mul),
        .is_multicycle(is_multicycle),
        .mul_src1(src1),
        .mul_src2(src2),
        .src1_signed(src1_signed),
        .src2_signed(src2_signed),
        .mul_op(mul_op),
        .mul_result(mul_result),
        .mul_stall(mul_stall)
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
                      reg_fpu_data3;
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
    logic inst_lb, inst_sb, inst_lh, inst_sh, inst_lw, inst_sw,inst_lbu, inst_lhu;
    logic [5:0] load_inst;
    assign load_inst = {(inst_lb || inst_sb), (inst_lh || inst_sh), (inst_lw || inst_sw), inst_lbu, inst_lhu, is_store};
    assign inst_lb  = mem_op[4] & ~is_store;
    assign inst_lh  = mem_op[3] & ~is_store;
    assign inst_lw  = mem_op[2] & ~is_store;
    assign inst_lbu = mem_op[1] & ~is_store;
    assign inst_lhu = mem_op[0] & ~is_store;

    assign inst_sb  = mem_op[4] & is_store;
    assign inst_sh  = mem_op[3] & is_store;
    assign inst_sw  = mem_op[2] & is_store;
    assign dmem_addr = src1 + mem_imm;
    assign dmem_wdata = (inst_sb) ? {4{src2[7:0]}} :
                       (inst_sh) ? {2{src2[15:0]}} :
                       src2;
    logic [3:0] sb_wen, sh_wen;
    always_comb begin
        case (dmem_addr[1:0])
            2'b00: sb_wen = 4'b0001;
            2'b01: sb_wen = 4'b0010;
            2'b10: sb_wen = 4'b0100;
            default: sb_wen = 4'b1000;
        endcase
    end
    always_comb begin
        case (dmem_addr[1])
            1'b0: sh_wen = 4'b0011;
            default: sh_wen = 4'b1100;
        endcase
    end
    always_comb begin
        dmem_wen = 4'b0000;
        if (!es_flush) begin
            unique case (1'b1)
                inst_sb: dmem_wen = sb_wen;
                inst_sh: dmem_wen = sh_wen;
                inst_sw: dmem_wen = 4'b1111;
                default: dmem_wen = 4'b0000;
            endcase
        end
    end
    assign dmem_en = |mem_op && !es_flush;

    //CSR访问
    logic inst_csrrw, inst_csrrs, inst_csrrc, inst_csrrwi, inst_csrrsi, inst_csrrci;
    assign inst_csrrw  = csr_op == 3'b100 && csr_imm_sel == 1'b0;
    assign inst_csrrs  = csr_op == 3'b010 && csr_imm_sel == 1'b0;
    assign inst_csrrc  = csr_op == 3'b001 && csr_imm_sel == 1'b0;
    assign inst_csrrwi = csr_op == 3'b100 && csr_imm_sel == 1'b1;
    assign inst_csrrsi = csr_op == 3'b010 && csr_imm_sel == 1'b1;
    assign inst_csrrci = csr_op == 3'b001 && csr_imm_sel == 1'b1;
    assign exe_csr_wen = csr_wen;
    assign exe_csr_addr = csr_waddr;
    assign csr_wdata = inst_csrrw ? src1 :
                       inst_csrrs ? (csr_data | src1) :
                       inst_csrrc ? (csr_data & ~src1) :
                       inst_csrrwi ? csr_imm :
                       inst_csrrsi ? (csr_data | csr_imm) :
                       inst_csrrci ? (csr_data & ~csr_imm) :
                       32'b0;
    
    //BR/JMP计算
    logic is_beq, is_bne, is_blt, is_bge, is_bltu, is_bgeu;
    assign is_beq = br_jmp_opcode[5];
    assign is_bne = br_jmp_opcode[4];
    assign is_blt = br_jmp_opcode[3];
    assign is_bge = br_jmp_opcode[2];
    assign is_bltu= br_jmp_opcode[1];
    assign is_bgeu= br_jmp_opcode[0];
    // 1. 预计算减法和标志位 (FPGA 会将其映射到进位链)
    logic [32:0] sub_res;
    assign sub_res = {1'b0, src1} - {1'b0, src2};

    logic eq, lt, ltu;
    assign eq  = (src1 == src2); // 部分综合器对 == 0 优化更好，但直接比较通常也能进位链优化
    assign ltu = sub_res[32];    // 无符号小于即看减法的借位

    // 有符号小于：如果符号不同，则 src1负数时为真；如果符号相同，看减法结果
    assign lt  = (src1[31] != src2[31]) ? src1[31] : ltu;

    // 2. 并行选择逻辑 (代替 case(1'b1))
    // 这种写法在 FPGA 中会被优化为单层 LUT 逻辑
    logic br_cond_raw;
    assign br_cond_raw = (is_beq  & eq)
                       | (is_bne  & !eq)
                       | (is_blt  & lt)
                       | (is_bge  & !lt)
                       | (is_bltu & ltu)
                       | (is_bgeu & !ltu);

    // 3. 优化 br_taken 的判定路径
    // 将 br_jmp_opcode 是否有效的判断与 br_cond 合并
    logic is_branch;
    assign is_branch = |br_jmp_opcode;

    assign br_taken = es_flush ? 1'b0 : (is_jal | is_jalr | (is_branch & br_cond_raw));

    // 4. 计算目标地址
    // JALR 的掩码操作直接在加法后进行位截断，保持路径简洁
    logic [31:0] jalr_sum;
    logic [31:0] pc_jalr;
    assign jalr_sum = src1 + br_jmp_imm;
    assign pc_jalr = { jalr_sum[31:1], 1'b0 };
    assign br_target = is_jalr ? pc_jalr : br_jmp_target;
    //结果选择
    always_comb begin
        exe_result = 32'b0;
        if (!es_flush) begin
            unique case (1'b1)
                is_alu: exe_result = alu_result;
                is_fpu: exe_result = fpu_result;
                is_mem: exe_result = dmem_addr;
                is_mul: exe_result = mul_result;
                is_csr: exe_result = csr_data;
                default: exe_result = exe_pc + 4; //默认写回PC+4，方便调试和实现JAL/JALR
            endcase
        end
    end

    //数据前递接口
    assign exe_dest_addr = rd_addr;
    assign exe_regfile_wen = regfile_wen && !es_flush;
    assign exe_reg_fpu_wen = reg_fpu_wen && !es_flush;

    //输出到下一级
    assign es_to_ms_bus = {
        exe_pc,     //32
        exe_result, //32
        load_inst,  //6
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


endmodule