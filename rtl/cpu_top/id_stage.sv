`include "defines.svh"
module id_stage (
    input logic clk,
    input logic rst_n,
    //与if_stage的数据接口
    input logic fs_to_ds_valid,
    output logic ds_allowin,
    input logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    //reggiles接口
    output logic [4:0] rs1_addr,
    output logic [4:0] rs2_addr,
    input logic [`DATA_WIDTH-1:0] rs1_data,
    input logic [`DATA_WIDTH-1:0] rs2_data,
    //regfile_fpu接口
    output logic [4:0] rs1_fpu_addr,
    output logic [4:0] rs2_fpu_addr,
    output logic [4:0] rs3_fpu_addr,//仅用于fpu指令中的三源寄存器
    output logic rs3_fpu_ren, //是否需要读取rs3_fpu寄存器
    input logic [`DATA_WIDTH-1:0] rs1_fpu_data,
    input logic [`DATA_WIDTH-1:0] rs2_fpu_data,
    //csr接口
    output logic [11:0] csr_addr,
    input logic [`DATA_WIDTH-1:0] csr_data,
    //与执行阶段的数据接口
    output logic ds_to_es_valid,
    input logic es_allowin,
    output logic ds_flush,
    output logic [`DS_ES_WIDTH-1:0] ds_to_es_bus,
    //数据前递接口--写回
    input logic regfile_wen,
    input logic reg_fpu_wen,
    input logic [4:0] regfile_waddr,
    input logic [`DATA_WIDTH-1:0] regfile_wdata,
    //数据前递接口--执行阶段--仅前递地址，数据选择统一在exe_stage完成
    input logic [4:0] exe_dest_addr,
    input logic exe_regfile_wen,
    input logic exe_reg_fpu_wen,
    input logic [11:0] exe_csr_addr,
    input logic exe_csr_wen,
    input logic es_valid,
    //数据前递接口--访存阶段--仅前递地址，数据选择统一在exe_stage完成
    input logic [4:0] mem_dest_addr,
    input logic mem_regfile_wen,
    input logic mem_reg_fpu_wen,
    input logic ms_valid,
    //跳转信号与异常信号
    input logic br_taken,
    input logic exception_flag,
    input logic [`EXC_WIDTH-1:0] fs_exc_bus,
    output logic [`EXC_WIDTH-1:0] ds_exc_bus
);  

    logic ds_valid;
    logic ds_ready_go;
    logic load_use_hazard;
    logic raw_hazard;
    assign ds_ready_go = !(load_use_hazard || raw_hazard); 
    assign ds_allowin = !ds_valid || ds_ready_go && es_allowin;
    assign ds_to_es_valid = ds_valid && ds_ready_go;
    //握手协议
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ds_valid <= 1'b0;
        end else if (ds_allowin) begin
            ds_valid <= fs_to_ds_valid;
        end else begin
            ds_valid <= ds_valid;
        end
    end

    //锁存数据
    logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus_r;
    logic [`EXC_WIDTH-1:0] fs_exc_bus_r;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fs_to_ds_bus_r <= '0;
            fs_exc_bus_r <= '0;
        end else if (fs_to_ds_valid && ds_allowin) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
            fs_exc_bus_r <= fs_exc_bus;
        end else begin
            fs_to_ds_bus_r <= fs_to_ds_bus_r;
            fs_exc_bus_r <= fs_exc_bus_r;
        end
    end
    always_comb begin
        if (!rst_n) begin
            ds_flush = 1'b0;
        end else begin
            if (exception_flag || br_taken) begin
                ds_flush <= 1'b1;
            end else begin
                ds_flush <= 1'b0;
            end
        end
    end

    logic [`ADDR_WIDTH-1:0] id_pc;
    logic [`DATA_WIDTH-1:0] id_inst;
    logic bp_pred_taken;
    logic [`ADDR_WIDTH-1:0] bp_pred_target;
    assign {id_inst, id_pc, bp_pred_taken, bp_pred_target} = fs_to_ds_bus_r;

    //译码逻辑
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    assign opcode = id_inst[6:0];
    assign funct3 = id_inst[14:12];
    assign funct7 = id_inst[31:25];
    assign rs1_addr = id_inst[19:15];
    assign rs2_addr = id_inst[24:20];
    assign rs1_fpu_addr = id_inst[19:15];
    assign rs2_fpu_addr = id_inst[24:20];
    assign rs3_fpu_addr = id_inst[31:27];
    assign csr_addr = id_inst[31:20];
    logic [4:0] rd_addr;
    assign rd_addr = id_inst[11:7];
    
    logic [11:0] imm_i;
    logic [11:0] imm_s;
    logic [12:0] imm_b;
    logic [19:0] imm_u;
    logic [20:0] imm_j;
    logic [4:0] imm_z;
    assign imm_i = id_inst[31:20];
    assign imm_s = {id_inst[31:25], id_inst[11:7]};
    assign imm_b = {id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
    assign imm_u = id_inst[31:12];
    assign imm_j = {id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
    assign imm_z = id_inst[19:15];

    logic [31:0] imm_i_ext , imm_s_ext , imm_b_ext , imm_u_ext , imm_j_ext , imm_z_ext;
    assign imm_i_ext = {{20{imm_i[11]}}, imm_i};
    assign imm_s_ext = {{20{imm_s[11]}}, imm_s};
    assign imm_b_ext = {{19{imm_b[12]}}, imm_b};
    assign imm_u_ext = {imm_u, 12'b0};
    assign imm_j_ext = {{11{imm_j[20]}}, imm_j};
    assign imm_z_ext = {{27{1'b0}}, imm_z};

    //指令定义
    logic is_load , is_store , is_branch , is_jal , is_jalr , is_op_imm , is_op_reg , is_lui , is_auipc , is_system , is_fence , is_fpu ;
    assign is_load   = (opcode == 7'b0000011);
    assign is_store  = (opcode == 7'b0100011);
    assign is_branch = (opcode == 7'b1100011);
    assign is_jal    = (opcode == 7'b1101111);
    assign is_jalr   = (opcode == 7'b1100111);
    assign is_op_imm = (opcode == 7'b0010011);
    assign is_op_reg = (opcode == 7'b0110011);
    assign is_lui    = (opcode == 7'b0110111);
    assign is_auipc  = (opcode == 7'b0010111);
    assign is_system = (opcode == 7'b1110011);
    assign is_fence  = (opcode == 7'b0001111);
    assign is_fpu    = (opcode == 7'b1010011);
    
    logic f3_000 , f3_001 , f3_010 , f3_011 , f3_100 , f3_101 , f3_110 , f3_111 ;
    assign f3_000 = (funct3 == 3'b000);
    assign f3_001 = (funct3 == 3'b001);
    assign f3_010 = (funct3 == 3'b010);
    assign f3_011 = (funct3 == 3'b011);
    assign f3_100 = (funct3 == 3'b100);
    assign f3_101 = (funct3 == 3'b101);
    assign f3_110 = (funct3 == 3'b110);
    assign f3_111 = (funct3 == 3'b111);

    logic f7_0000000 , f7_0100000 , f7_0000001 , f7_0011000 ;
    assign f7_0000000 = (funct7 == 7'b0000000);
    assign f7_0100000 = (funct7 == 7'b0100000);
    assign f7_0000001 = (funct7 == 7'b0000001);
    assign f7_0011000 = (funct7 == 7'b0011000);

    //加载指令--opcode=0000011
    logic inst_lw , inst_lb , inst_lh , inst_lbu , inst_lhu ;
    assign inst_lw  = is_load && f3_010;
    assign inst_lb  = is_load && f3_000;
    assign inst_lh  = is_load && f3_001;
    assign inst_lbu = is_load && f3_100;
    assign inst_lhu = is_load && f3_101;

    //存储指令--opcode=0100011
    logic inst_sw , inst_sb , inst_sh ;
    assign inst_sw = is_store && f3_010;
    assign inst_sb = is_store && f3_000;
    assign inst_sh = is_store && f3_001;

    //分支指令--opcode=1100011
    logic inst_beq , inst_bne , inst_blt , inst_bge , inst_bltu , inst_bgeu ;
    assign inst_beq  = is_branch && f3_000;
    assign inst_bne  = is_branch && f3_001;
    assign inst_blt  = is_branch && f3_100;
    assign inst_bge  = is_branch && f3_101;
    assign inst_bltu = is_branch && f3_110;
    assign inst_bgeu = is_branch && f3_111;

    //跳转指令--opcode=1101111或1100111
    logic inst_jal , inst_jalr ;
    assign inst_jal  = is_jal;
    assign inst_jalr = is_jalr;

    //立即数运算指令--opcode=0010011
    logic inst_addi , inst_slti , inst_sltiu , inst_xori , inst_ori , inst_andi , inst_slli , inst_srli , inst_srai ;
    assign inst_addi  = is_op_imm && f3_000;
    assign inst_slti  = is_op_imm && f3_010;
    assign inst_sltiu = is_op_imm && f3_011;
    assign inst_xori  = is_op_imm && f3_100;
    assign inst_ori   = is_op_imm && f3_110;
    assign inst_andi  = is_op_imm && f3_111;
    assign inst_slli  = is_op_imm && f3_001 && f7_0000000;
    assign inst_srli  = is_op_imm && f3_101 && f7_0000000;
    assign inst_srai  = is_op_imm && f3_101 && f7_0100000;

    //寄存器-寄存器运算指令--opcode=0110011
    logic inst_add , inst_sub , inst_sll , inst_slt , inst_sltu , inst_xor , inst_or , inst_and , inst_srl , inst_sra ;
    logic inst_mul , inst_mulh , inst_mulhsu , inst_mulhu , inst_div , inst_divu , inst_rem , inst_remu ;
    assign inst_add = is_op_reg && f3_000 && f7_0000000;
    assign inst_sub = is_op_reg && f3_000 && f7_0100000;
    assign inst_sll = is_op_reg && f3_001 && f7_0000000;
    assign inst_slt = is_op_reg && f3_010 && f7_0000000;
    assign inst_sltu= is_op_reg && f3_011 && f7_0000000;
    assign inst_xor = is_op_reg && f3_100 && f7_0000000;
    assign inst_or  = is_op_reg && f3_110 && f7_0000000;
    assign inst_and = is_op_reg && f3_111 && f7_0000000;
    assign inst_srl = is_op_reg && f3_101 && f7_0000000;
    assign inst_sra = is_op_reg && f3_101 && f7_0100000;
    assign inst_mul = is_op_reg && f3_000 && f7_0000001;
    assign inst_mulh = is_op_reg && f3_001 && f7_0000001;
    assign inst_mulhsu = is_op_reg && f3_010 && f7_0000001;
    assign inst_mulhu = is_op_reg && f3_011 && f7_0000001;
    assign inst_div = is_op_reg && f3_100 && f7_0000001;
    assign inst_divu = is_op_reg && f3_101 && f7_0000001;
    assign inst_rem = is_op_reg && f3_110 && f7_0000001;
    assign inst_remu = is_op_reg && f3_111 && f7_0000001;

    //lui和auipc指令--opcode=0110111或0010111
    logic inst_lui , inst_auipc ;
    assign inst_lui   = is_lui;
    assign inst_auipc = is_auipc;

    //系统指令--opcode=1110011
    logic inst_ecall , inst_ebreak , inst_mret , inst_csrrw , inst_csrrs , inst_csrrc , inst_csrrwi , inst_csrrsi , inst_csrrci ;
    assign inst_ecall  = is_system && f3_000 && id_inst[25:20] == 6'b000000;
    assign inst_ebreak = is_system && f3_000 && id_inst[25:20] == 6'b000001;
    assign inst_mret   = is_system && f3_000 && f7_0011000;
    assign inst_csrrw  = is_system && f3_001;
    assign inst_csrrs  = is_system && f3_010;
    assign inst_csrrc  = is_system && f3_011;
    assign inst_csrrwi = is_system && f3_101;
    assign inst_csrrsi = is_system && f3_110;
    assign inst_csrrci = is_system && f3_111;

    //fence指令--opcode=0001111
    logic inst_fence;
    assign inst_fence   = is_fence && f3_000;

    //fpu指令--opcode=1010011
    logic is_fload , is_fstore , is_fmadd , is_fmsub , is_fnmadd , is_fnmsub ;
    assign is_fload  = (opcode == 7'b0000111);
    assign is_fstore = (opcode == 7'b0100111);
    assign is_fmadd  = (opcode == 7'b1000011);
    assign is_fmsub  = (opcode == 7'b1000111);
    assign is_fnmsub = (opcode == 7'b1001011);
    assign is_fnmadd = (opcode == 7'b1001111);

    logic f7_0000100 , f7_0001000 , f7_0001100 , f7_0101100 , f7_0010100 , f7_1010000 , f7_1100000 , f7_1101000 , f7_1110000 , f7_1111000 ,f7_0010000 ;
    assign f7_0000100 = (funct7 == 7'b0000100);
    assign f7_0001000 = (funct7 == 7'b0001000);
    assign f7_0001100 = (funct7 == 7'b0001100);
    assign f7_0101100 = (funct7 == 7'b0101100);
    assign f7_0010100 = (funct7 == 7'b0010100);
    assign f7_1010000 = (funct7 == 7'b1010000);
    assign f7_1100000 = (funct7 == 7'b1100000);
    assign f7_1101000 = (funct7 == 7'b1101000);
    assign f7_1110000 = (funct7 == 7'b1110000);
    assign f7_1111000 = (funct7 == 7'b1111000);
    assign f7_0010000 = (funct7 == 7'b0010000);

    logic rs2_00000 , rs2_00001 ;
    logic fmt_s ;
    assign rs2_00000 = (id_inst[24:20] == 5'b00000);
    assign rs2_00001 = (id_inst[24:20] == 5'b00001);
    assign fmt_s = (id_inst[26:25] == 2'b00);

    logic inst_flw , inst_fsw;
    logic inst_fadd_s , inst_fsub_s , inst_fmul_s , inst_fdiv_s , inst_fsqrt_s , inst_fmin_s , inst_fmax_s , inst_fmadd_s , inst_fmsub_s , inst_fnmadd_s , inst_fnmsub_s;
    logic inst_fcvt_w_s , inst_fcvt_wu_s , inst_fcvt_s_w , inst_fcvt_s_wu;
    logic inst_fsgnj_s , inst_fsgnjn_s , inst_fsgnjx_s;
    logic inst_fmv_w_x , inst_fmv_x_w;
    logic inst_flt_s , inst_fle_s , inst_feq_s;
    logic inst_fclass_s;

    assign inst_flw      = is_fload  && f3_010;
    assign inst_fsw      = is_fstore && f3_010;
    assign inst_fadd_s   = is_fpu && f7_0000000;
    assign inst_fsub_s   = is_fpu && f7_0000100;
    assign inst_fmul_s   = is_fpu && f7_0001000;
    assign inst_fdiv_s   = is_fpu && f7_0001100;
    assign inst_fsqrt_s  = is_fpu && f7_0101100 && rs2_00000;
    assign inst_fmin_s   = is_fpu && f7_0010100 && f3_000;
    assign inst_fmax_s   = is_fpu && f7_0010100 && f3_001;
    assign inst_fmadd_s  = is_fmadd  && fmt_s;
    assign inst_fmsub_s  = is_fmsub   && fmt_s;
    assign inst_fnmadd_s = is_fnmadd  && fmt_s;
    assign inst_fnmsub_s = is_fnmsub  && fmt_s;
    assign inst_fcvt_w_s  = is_fpu && f7_1100000 && rs2_00000;
    assign inst_fcvt_wu_s = is_fpu && f7_1100000 && rs2_00001;
    assign inst_fcvt_s_w  = is_fpu && f7_1101000 && rs2_00000;
    assign inst_fcvt_s_wu = is_fpu && f7_1101000 && rs2_00001;
    assign inst_fsgnj_s   = is_fpu && f7_0010000 && f3_000;
    assign inst_fsgnjn_s  = is_fpu && f7_0010000 && f3_001;
    assign inst_fsgnjx_s  = is_fpu && f7_0010000 && f3_010;
    assign inst_fmv_w_x   = is_fpu && f7_1111000 && f3_000 && rs2_00000;
    assign inst_fmv_x_w   = is_fpu && f7_1110000 && f3_000 && rs2_00000;
    assign inst_flt_s     = is_fpu && f7_1010000 && f3_001;
    assign inst_fle_s     = is_fpu && f7_1010000 && f3_000;
    assign inst_feq_s     = is_fpu && f7_1010000 && f3_010;
    assign inst_fclass_s  = is_fpu && f7_1110000 && f3_001 && rs2_00000;

    //写回阶段数据前递结果
    logic [31:0] src1, src2;
    assign src1 = (rs1_addr == 5'b0) ? 32'b0 :
                  (regfile_wen && (regfile_waddr == rs1_addr)) ? regfile_wdata :
                   rs1_data;
    assign src2 = (rs2_addr == 5'b0) ? 32'b0 :
                  (regfile_wen && (regfile_waddr == rs2_addr)) ? regfile_wdata :
                   rs2_data;
    logic [31:0] src1_fpu, src2_fpu;
    assign src1_fpu = (rs1_fpu_addr == 5'b0) ? 32'b0 :
                      (reg_fpu_wen && (regfile_waddr == rs1_fpu_addr)) ? regfile_wdata :
                       rs1_fpu_data;
    assign src2_fpu = (rs2_fpu_addr == 5'b0) ? 32'b0 :
                      (reg_fpu_wen && (regfile_waddr == rs2_fpu_addr)) ? regfile_wdata :
                       rs2_fpu_data;

    //立即数选择
    logic IMI_valid , IMS_valid , IMB_valid , IMU_valid , IMJ_valid , IMZ_valid;
    assign IMI_valid = is_load || inst_addi || inst_slti || inst_sltiu || inst_xori || inst_ori || inst_andi || inst_slli || inst_srli || inst_srai || inst_flw || inst_jalr;
    assign IMS_valid = is_store || inst_fsw;
    assign IMB_valid = is_branch;
    assign IMU_valid = is_lui || is_auipc;
    assign IMJ_valid = is_jal;
    assign IMZ_valid = inst_csrrwi || inst_csrrsi || inst_csrrci;

    //ALU_PACKET打包
    logic [`ALU_PACKET_WIDTH-1:0] alu_packet;
    logic alu_src2_imm_sel;
    logic [9:0] alu_op;
    logic alu_add , alu_sub , alu_and , alu_or , alu_xor , alu_sll , alu_srl , alu_sra , alu_slt , alu_sltu;
    assign alu_src2_imm_sel = is_op_imm || is_lui || is_auipc;
    assign alu_add = inst_add || inst_addi || inst_lui || inst_auipc;
    assign alu_sub = inst_sub;
    assign alu_and = inst_and || inst_andi;
    assign alu_or  = inst_or  || inst_ori;
    assign alu_xor = inst_xor || inst_xori;
    assign alu_sll = inst_sll || inst_slli;
    assign alu_srl = inst_srl || inst_srli;
    assign alu_sra = inst_sra || inst_srai;
    assign alu_slt = inst_slt || inst_slti;
    assign alu_sltu= inst_sltu || inst_sltiu;
    assign alu_op = {alu_add, alu_sub, alu_and, alu_or, alu_xor, alu_sll, alu_srl, alu_sra, alu_slt, alu_sltu};
    assign alu_packet = alu_op;

    //FPU_PACKET打包
    logic [`FPU_PACKET_WIDTH-1:0] fpu_packet;
    logic [31:0] fpu_src1, fpu_src2;
    logic [25:0] fpu_op;
    logic [2:0] rm;
    logic [1:0] fpu_src1_fwd;
    logic [1:0] fpu_src2_fwd;
    logic [1:0] fpu_src3_fwd;
    assign rs3_fpu_ren = inst_fmadd_s || inst_fmsub_s || inst_fnmadd_s || inst_fnmsub_s; //仅当指令为三源寄存器的fpu指令时才需要读取rs3_fpu寄存器
    assign fpu_src1 = src1_fpu;
    assign fpu_src2 = src2_fpu;
    assign fpu_src1_fwd = (rs1_fpu_addr != 5'b0) ?
                          ((exe_reg_fpu_wen && (exe_dest_addr == rs1_fpu_addr)) ? 2'b01 :
                           (mem_reg_fpu_wen && (mem_dest_addr == rs1_fpu_addr)) ? 2'b10 : 2'b00) : 2'b00;
    assign fpu_src2_fwd = (rs2_fpu_addr != 5'b0) ?
                          ((exe_reg_fpu_wen && (exe_dest_addr == rs2_fpu_addr)) ? 2'b01 :
                           (mem_reg_fpu_wen && (mem_dest_addr == rs2_fpu_addr)) ? 2'b10 : 2'b00) : 2'b00;   
    assign fpu_src3_fwd = (rs3_fpu_addr != 5'b0) ?
                          ((exe_reg_fpu_wen && (exe_dest_addr == rs3_fpu_addr)) ? 2'b01 :
                           (mem_reg_fpu_wen && (mem_dest_addr == rs3_fpu_addr)) ? 2'b10 : 2'b00) : 2'b00;
    assign rm = id_inst[14:12];
    assign fpu_op = {inst_fadd_s, inst_fsub_s, inst_fmul_s, inst_fdiv_s, inst_fsqrt_s, inst_fmin_s, inst_fmax_s, inst_fmadd_s, inst_fmsub_s, inst_fnmadd_s, inst_fnmsub_s, 
                     inst_fcvt_w_s, inst_fcvt_wu_s, inst_fcvt_s_w, inst_fcvt_s_wu,
                     inst_fsgnj_s, inst_fsgnjn_s, inst_fsgnjx_s,
                     inst_fmv_w_x, inst_fmv_x_w,
                     inst_flt_s, inst_fle_s, inst_feq_s,
                     inst_fclass_s};
    assign fpu_packet = {fpu_op, rm, fpu_src1_fwd, fpu_src2_fwd, fpu_src3_fwd, fpu_src1, fpu_src2};

    //MUL_PACKET打包
    logic [`MUL_PACKET_WIDTH-1:0] mul_packet;
    logic [3:0] mul_op;
    logic src1_signed , src2_signed;
    assign src1_signed = inst_mul || inst_mulh || inst_mulhsu || inst_div || inst_rem;
    assign src2_signed = inst_mul || inst_mulh || inst_div || inst_rem;
    assign mul_op = {inst_mul , (inst_mulh || inst_mulhsu || inst_mulhu) ,
                     (inst_div || inst_divu) , (inst_rem || inst_remu)};
    assign mul_packet = {mul_op, src1_signed, src2_signed};

    //MEM_PACKET打包
    logic [`MEM_PACKET_WIDTH-1:0] mem_packet;
    logic [31:0] mem_imm;
    logic [4:0] mem_op;
    logic is_store_inst;
    assign is_store_inst = is_store || inst_fsw || inst_flw;
    assign mem_imm = {32{IMS_valid}} & imm_s_ext | {32{IMI_valid}} & imm_i_ext;
    assign mem_op = {(inst_lb || inst_sb) , (inst_lh || inst_sh) , (inst_lw || inst_sw || inst_flw || inst_fsw),inst_lbu, inst_lhu};
    assign mem_packet = {mem_imm, mem_op, is_store_inst};

    //CSR_PACKET打包
    logic [`CSR_PACKET_WIDTH-1:0] csr_packet;
    logic [31:0] csr_rdata;
    logic [31:0] csr_imm;
    logic [11:0] csr_waddr;
    logic [2:0] csr_op;
    logic csr_wen;
    logic csr_imm_sel;
    logic csr_rdata_fwd;
    assign csr_rdata = csr_data;
    assign csr_imm = {32{IMZ_valid}} & imm_z_ext;
    assign csr_waddr = csr_addr;
    assign csr_op = {(inst_csrrw || inst_csrrwi) , (inst_csrrs || inst_csrrsi) , (inst_csrrc || inst_csrrci)};
    assign csr_imm_sel = inst_csrrwi || inst_csrrsi || inst_csrrci;
    assign csr_rdata_fwd = (exe_csr_wen && (exe_csr_addr == csr_addr)) ? 1'b1 : 1'b0;
    assign csr_wen = inst_csrrw || inst_csrrs || inst_csrrc || inst_csrrwi || inst_csrrsi || inst_csrrci;
    assign csr_packet = {csr_rdata, csr_imm, csr_waddr, csr_op, csr_imm_sel, csr_rdata_fwd, csr_wen};

    //BR_JMP_PACKET打包
    logic [`BR_JMP_PACKET_WIDTH-1:0] br_jmp_packet;
    logic [31:0] br_jmp_target;
    logic [31:0] br_jmp_imm;
    logic [5:0] br_jmp_opcode;
    assign br_jmp_imm = ({32{IMB_valid}} & imm_b_ext) | ({32{IMJ_valid}} & imm_j_ext) | ({32{IMI_valid && is_jalr}} & imm_i_ext);
    assign br_jmp_opcode = {inst_beq, inst_bne, inst_blt, inst_bge, inst_bltu, inst_bgeu};
    assign br_jmp_target = id_pc + br_jmp_imm;
    assign br_jmp_packet = {bp_pred_taken, bp_pred_target, br_jmp_target, br_jmp_imm, br_jmp_opcode, is_jal, is_jalr};

    //CTRL_PACKET打包
    logic [`CTRL_PACKET_WIDTH-1:0] ctrl_packet;
    logic is_alu_inst , is_fpu_inst , is_mul_inst , is_mem_inst , is_csr_inst , is_br_jmp_inst;
    logic [4:0] ctrl_rd_addr;
    logic ctrl_regfile_wen;
    logic ctrl_reg_fpu_wen;
    logic is_multicycle_inst;    //是否多周期指令
    logic wb_exe_result;
    logic wb_mem_result;
    logic [1:0] exe_result_sel;
    assign is_alu_inst = alu_add || alu_sub || alu_and || alu_or || alu_xor || alu_sll || alu_srl || alu_sra || alu_slt || alu_sltu;
    assign is_fpu_inst = inst_fadd_s || inst_fsub_s || inst_fmul_s || inst_fdiv_s || inst_fsqrt_s || inst_fmin_s || inst_fmax_s || inst_fmadd_s || inst_fmsub_s || inst_fnmadd_s || inst_fnmsub_s ||
                         inst_fcvt_w_s  || inst_fcvt_wu_s || inst_fcvt_s_w  || inst_fcvt_s_wu ||
                         inst_fsgnj_s   || inst_fsgnjn_s  || inst_fsgnjx_s  ||
                         inst_fmv_w_x   || inst_fmv_x_w   ||
                         inst_flt_s     || inst_fle_s     || inst_feq_s     ||
                         inst_fclass_s;
    assign is_mul_inst = inst_mul || inst_mulh || inst_mulhsu || inst_mulhu || inst_div || inst_divu || inst_rem || inst_remu;
    assign is_mem_inst = is_load || is_store || inst_flw || inst_fsw;
    assign is_csr_inst = inst_csrrw || inst_csrrs || inst_csrrc || inst_csrrwi || inst_csrrsi || inst_csrrci;
    assign is_br_jmp_inst = is_branch || is_jal || is_jalr;
    assign ctrl_rd_addr = rd_addr;
    assign ctrl_regfile_wen = is_alu_inst || is_fpu_inst || is_mul_inst || is_load || inst_flw || is_csr_inst || is_jal || is_jalr;
    assign ctrl_reg_fpu_wen = is_fpu_inst;
    assign is_multicycle_inst = (inst_fdiv_s || inst_fsqrt_s || inst_fmadd_s || inst_fmsub_s || inst_fnmadd_s || inst_fnmsub_s ||
                           inst_fcvt_w_s  || inst_fcvt_wu_s || inst_fcvt_s_w  || inst_fcvt_s_wu ||
                           inst_fsgnj_s   || inst_fsgnjn_s  || inst_fsgnjx_s  ||
                           inst_fmv_w_x   || inst_fmv_x_w   ||
                           inst_flt_s     || inst_fle_s     || inst_feq_s     ||
                           inst_fclass_s  ||
                           ((inst_mul || inst_mulh || inst_mulhsu || inst_mulhu) && `MUL_MULTICYCLE_ENABLE) || inst_div || inst_divu || inst_rem || inst_remu) && `MULTICYCLE_ENABLE;
    assign wb_exe_result = is_alu_inst || is_fpu_inst || is_mul_inst || is_csr_inst || is_jal || is_jalr;
    assign wb_mem_result = is_mem_inst;
    assign exe_result_sel = {wb_exe_result, wb_mem_result};
    assign ctrl_packet = {id_pc,exe_result_sel,is_alu_inst, is_fpu_inst, is_mul_inst, is_mem_inst, is_csr_inst, is_br_jmp_inst, ctrl_rd_addr, ctrl_regfile_wen, ctrl_reg_fpu_wen, is_multicycle_inst};

    //SRC_PACKET打包
    logic [`SRC_PACKET_WIDTH-1:0] src_packet;
    logic [31:0] reg_src1, reg_src2;
    logic [1:0] src1_fwd, src2_fwd;
    assign src1_fwd = (inst_lui || inst_auipc) ? 2'b00 :
                      (rs1_addr != 5'b0) ?
                      ((exe_regfile_wen && (exe_dest_addr == rs1_addr) && es_valid) ? 2'b01 :
                       (mem_regfile_wen && (mem_dest_addr == rs1_addr) && ms_valid) ? 2'b10 : 2'b00) : 2'b00;
    assign src2_fwd = alu_src2_imm_sel ? 2'b00 :
                      (rs2_addr != 5'b0) ?
                      ((exe_regfile_wen && (exe_dest_addr == rs2_addr) && es_valid) ? 2'b01 :
                       (mem_regfile_wen && (mem_dest_addr == rs2_addr) && ms_valid) ? 2'b10 : 2'b00) : 2'b00; //仅当第二个源操作数不是立即数时才进行前递
    assign reg_src1 = (inst_flw || inst_fsw) ? src1_fpu : 
                      inst_lui   ? 32'b0 :
                      inst_auipc ? id_pc : src1;
    assign reg_src2 = alu_src2_imm_sel ? ({32{IMI_valid}} & imm_i_ext) | ({32{IMU_valid}} & imm_u_ext) : src2;
    assign src_packet = {reg_src1, reg_src2, src1_fwd, src2_fwd};

    //输出到下一级
    assign ds_to_es_bus = {alu_packet, fpu_packet, mul_packet, mem_packet, csr_packet, br_jmp_packet, ctrl_packet , src_packet};

    //异常处理
    logic [6:0] exc_code;
    logic [31:0] exc_mtval;
    assign exc_code = ds_flush ? 7'b0 :
                      (inst_ecall && ds_allowin) ? 7'b0101011 :   //环境调用异常
                      (inst_ebreak && ds_allowin) ? 7'b0100011 :  //断点异常
                      (inst_mret && ds_allowin) ? 7'b1000000 :   //机器模式返回异常
                      fs_exc_bus_r[38:32];  //来自取指阶段的异常
    assign exc_mtval = ds_flush ? 32'b0 :
                       (inst_ecall && ds_allowin) ? 32'b0 :
                       (inst_ebreak && ds_allowin) ? 32'b0 :
                       (inst_mret && ds_allowin) ? 32'b0 :
                       fs_exc_bus_r[31:0];
    assign ds_exc_bus = {exc_code, exc_mtval};
    
    //load_use冒险检测
    logic need_rs1 , need_rs2;
    logic exe_load_use_hazard;
    assign need_rs1 = is_op_reg || is_op_imm || is_load || is_store || is_branch || inst_jalr || is_fpu || inst_csrrw || inst_csrrs || inst_csrrc;
    assign need_rs2 = is_op_reg || is_store || is_branch || is_fpu;
    logic prev_load;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_load <= 1'b0;
        end else if (ds_allowin) begin
            prev_load <= is_load || inst_flw; //仅当当前指令为加载指令时才更新prev_load信号
        end
    end
    always_comb begin
        if (!rst_n) begin
            exe_load_use_hazard = 1'b0;
        end else begin
            // 保守策略：当前指令读取到上一条EXE写寄存器时停顿1拍，
            // 统一等待到MEM前递/寄存器写回，避免地址/数据相关指令误用旧值。
            exe_load_use_hazard = ((need_rs1 && (rs1_addr != 5'b0) && (rs1_addr == exe_dest_addr)) ||
                                  (need_rs2 && (rs2_addr != 5'b0) && (rs2_addr == exe_dest_addr))) &&
                                  es_valid && exe_regfile_wen && prev_load;
        end
    end
    assign load_use_hazard = exe_load_use_hazard && ds_valid;
    assign raw_hazard = ds_valid &&
                        (((need_rs1 && (rs1_addr != 5'b0)) &&
                          ((es_valid && exe_regfile_wen && (exe_dest_addr == rs1_addr)) ||
                           (ms_valid && mem_regfile_wen && (mem_dest_addr == rs1_addr)))) ||
                         ((need_rs2 && (rs2_addr != 5'b0)) &&
                          ((es_valid && exe_regfile_wen && (exe_dest_addr == rs2_addr)) ||
                           (ms_valid && mem_regfile_wen && (mem_dest_addr == rs2_addr)))));


endmodule
