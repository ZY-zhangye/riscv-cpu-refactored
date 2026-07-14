`include "defines.svh"
module if_stage (
    input logic clk,
    input logic rst_n,
    //取指端口
    output logic [`ADDR_WIDTH-1:0] pc_out,
    output logic inst_ren,
    input logic [`DATA_WIDTH-1:0] inst_in,
    output logic [`ADDR_WIDTH-1:0] pc_out1,
    output logic inst_ren1,
    input logic [`DATA_WIDTH-1:0] inst_in1,
    //与issue阶段的数据接口
    input logic ds_allowin,
    output logic fs_to_ds_valid,
    output logic fs_to_ds_valid1,
    output logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus,
    output logic [`FS_DS_WIDTH-1:0] fs_to_ds_bus1,
    //分支跳转接口
    input logic br_taken,
    input logic [`ADDR_WIDTH-1:0] br_target,
    //分支预测器更新接口
    input logic bp_update_valid,
    input logic [`ADDR_WIDTH-1:0] bp_update_pc,
    input logic bp_update_taken,
    input logic [`ADDR_WIDTH-1:0] bp_update_target,
    input logic bp_update_is_jalr,
    input logic bp_update_is_call,
    input logic bp_update_is_return,
    //异常包接口
    output logic [`EXC_WIDTH-1:0] fs_exc_bus,
    //异常跳转接口
    input logic exception_flag,
    input logic [`ADDR_WIDTH-1:0] exception_addr
);

    logic [`ADDR_WIDTH-1:0] seq_pc;
    logic [`ADDR_WIDTH-1:0] next_pc;
    logic [`ADDR_WIDTH-1:0] fs_out_pc;
    logic [`DATA_WIDTH-1:0] fs_out_inst;
    // fs_pc feeds both the packet bus and the predictor. Keep its fanout
    // bounded so Vivado can replicate the source register near the BTB RAMs
    // instead of routing one long high-fanout net across the IF stage.
    (* max_fanout = 32 *) logic [31:0] fs_pc;
    logic br_taken_reg;
    logic [31:0] br_target_reg;

    `ifdef L3H_BTB_16_ENTRIES
    localparam BP_INDEX_WIDTH = 4;
    `else
    localparam BP_INDEX_WIDTH = 7;
    `endif
    localparam BP_ENTRIES = 1 << BP_INDEX_WIDTH;
    localparam BP_TAG_WIDTH = `ADDR_WIDTH - BP_INDEX_WIDTH - 2;
    localparam BP_ENTRY_WIDTH = 2 + 1 + BP_TAG_WIDTH + `ADDR_WIDTH;

    // The two fetch copies use synchronous block-RAM reads. Their request
    // addresses advance with the one-cycle IROM request, so the registered BTB
    // entries, fs_pc and returned instructions describe the same packet.
    (* ram_style = "block" *)
    logic [BP_ENTRY_WIDTH-1:0] bp_mem_lookup0 [0:BP_ENTRIES-1];
    (* ram_style = "block" *)
    logic [BP_ENTRY_WIDTH-1:0] bp_mem_lookup1 [0:BP_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [BP_ENTRY_WIDTH-1:0] bp_mem_update [0:BP_ENTRIES-1];
    logic bp_valid_lookup0 [0:BP_ENTRIES-1];
    logic bp_valid_lookup1 [0:BP_ENTRIES-1];
    logic bp_valid_update [0:BP_ENTRIES-1];

    logic [BP_INDEX_WIDTH-1:0] bp_request_index0;
    logic [BP_INDEX_WIDTH-1:0] bp_request_index1;
    logic [BP_INDEX_WIDTH-1:0] bp_lookup_index0;
    logic [BP_TAG_WIDTH-1:0] bp_lookup_tag0;
    logic [BP_TAG_WIDTH-1:0] bp_lookup_tag1;
    logic lane1_index_wrap;
    logic [BP_ENTRY_WIDTH-1:0] bp_lookup_entry0;
    logic [BP_ENTRY_WIDTH-1:0] bp_lookup_entry1;
    logic [BP_ENTRY_WIDTH-1:0] bp_update_entry;
    logic bp_lookup_valid0;
    logic bp_lookup_valid1;
    logic [1:0] bp_lookup_counter0;
    logic [1:0] bp_lookup_counter1;
    logic [1:0] bp_update_counter;
    logic [1:0] bp_update_counter_next;
    logic bp_lookup_is_return0;
    logic bp_lookup_is_return1;
    logic bp_update_entry_is_return;
    logic [BP_TAG_WIDTH-1:0] bp_lookup_entry_tag0;
    logic [BP_TAG_WIDTH-1:0] bp_lookup_entry_tag1;
    logic [BP_TAG_WIDTH-1:0] bp_update_entry_tag;
    logic [`ADDR_WIDTH-1:0] bp_lookup_entry_target0;
    logic [`ADDR_WIDTH-1:0] bp_lookup_entry_target1;
    logic [`ADDR_WIDTH-1:0] bp_update_entry_target;
    logic [BP_ENTRY_WIDTH-1:0] bp_update_entry_next;
    logic bp_update_hit;
    logic bp_hit0;
    logic bp_hit1;
    logic bp_pred_taken0;
    logic bp_pred_taken1;
    logic [`ADDR_WIDTH-1:0] bp_pred_target0;
    logic [`ADDR_WIDTH-1:0] bp_pred_target1;
    logic [BP_INDEX_WIDTH-1:0] bp_update_index;
    logic [BP_TAG_WIDTH-1:0] bp_update_tag;
    logic bp_update_valid_r;
    logic [`ADDR_WIDTH-1:0] bp_update_pc_r;
    logic bp_update_taken_r;
    logic [`ADDR_WIDTH-1:0] bp_update_target_r;
    logic bp_update_is_return_r;

    `ifndef L3I_DISABLE_RAS
    localparam RAS_DEPTH = 8;
    localparam RAS_INDEX_WIDTH = 3;
    logic [`ADDR_WIDTH-1:0] ras_commit_stack [RAS_DEPTH-1:0];
    logic [`ADDR_WIDTH-1:0] ras_spec_stack [RAS_DEPTH-1:0];
    logic [RAS_INDEX_WIDTH-1:0] ras_commit_sp;
    logic [RAS_INDEX_WIDTH:0] ras_commit_count;
    logic [RAS_INDEX_WIDTH-1:0] ras_spec_sp;
    logic [RAS_INDEX_WIDTH:0] ras_spec_count;
    logic [RAS_INDEX_WIDTH-1:0] ras_top_index;
    logic [`ADDR_WIDTH-1:0] ras_top;
    logic ras_call0;
    logic ras_call1;
    logic ras_return0;
    logic ras_return1;
    logic ras_pred_taken0;
    logic ras_pred_taken1;
    `endif
    logic effective_pred_taken0;
    logic effective_pred_taken1;
    logic [`ADDR_WIDTH-1:0] effective_pred_target0;
    logic [`ADDR_WIDTH-1:0] effective_pred_target1;

    // The board instruction ROM consumes only addr[13:2]. Keep the lane1
    // increment on that word-address slice; reconstruct the unused upper
    // address bits separately so the BRAM address path does not inherit a
    // full 32-bit +4 carry chain.
    logic [11:0] imem_word_addr1;
    logic        imem_word_carry1;
    logic [17:0] imem_hi_addr1;

    assign bp_request_index0 = next_pc[BP_INDEX_WIDTH+1:2];
    assign bp_request_index1 = bp_request_index0 + 1'b1;
    assign bp_lookup_index0 = fs_out_pc[BP_INDEX_WIDTH+1:2];
    assign lane1_index_wrap = &bp_lookup_index0;
    assign bp_lookup_tag0 = fs_out_pc[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign bp_lookup_tag1 = bp_lookup_tag0;
    assign bp_update_entry = bp_mem_update[bp_update_index];
    assign {
        bp_lookup_counter0,
        bp_lookup_is_return0,
        bp_lookup_entry_tag0,
        bp_lookup_entry_target0
    } = bp_lookup_entry0;
    assign {
        bp_lookup_counter1,
        bp_lookup_is_return1,
        bp_lookup_entry_tag1,
        bp_lookup_entry_target1
    } = bp_lookup_entry1;
    assign {
        bp_update_counter,
        bp_update_entry_is_return,
        bp_update_entry_tag,
        bp_update_entry_target
    } = bp_update_entry;
    assign bp_hit0 = bp_lookup_valid0 &&
                     (bp_lookup_entry_tag0 == bp_lookup_tag0);
    assign bp_hit1 = !lane1_index_wrap &&
                     bp_lookup_valid1 &&
                     (bp_lookup_entry_tag1 == bp_lookup_tag1);
    assign bp_pred_taken0 = bp_hit0 && bp_lookup_counter0[1];
    assign bp_pred_taken1 = bp_hit1 && bp_lookup_counter1[1];
    assign bp_pred_target0 = bp_lookup_entry_target0;
    assign bp_pred_target1 = bp_lookup_entry_target1;
    assign bp_update_index = bp_update_pc_r[BP_INDEX_WIDTH+1:2];
    assign bp_update_tag = bp_update_pc_r[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign bp_update_hit = bp_valid_update[bp_update_index] &&
                           (bp_update_entry_tag == bp_update_tag);
    always_comb begin
        if (!bp_update_hit) begin
            bp_update_counter_next = bp_update_taken_r ? 2'b10 : 2'b01;
        end else if (bp_update_taken_r) begin
            bp_update_counter_next = (bp_update_counter == 2'b11) ?
                                     2'b11 : bp_update_counter + 1'b1;
        end else begin
            bp_update_counter_next = (bp_update_counter == 2'b00) ?
                                     2'b00 : bp_update_counter - 1'b1;
        end
    end
    assign bp_update_entry_next = {
        bp_update_counter_next,
        bp_update_is_return_r,
        bp_update_tag,
        bp_update_target_r
    };

    `ifndef L3I_DISABLE_RAS
    assign ras_top_index = ras_spec_sp - 1'b1;
    assign ras_top = ras_spec_stack[ras_top_index];
    assign ras_call0 = ((fs_out_inst[6:0] == 7'b1101111) ||
                        (fs_out_inst[6:0] == 7'b1100111)) &&
                       ((fs_out_inst[11:7] == 5'd1) ||
                        (fs_out_inst[11:7] == 5'd5));
    assign ras_call1 = ((inst_in1[6:0] == 7'b1101111) ||
                        (inst_in1[6:0] == 7'b1100111)) &&
                       ((inst_in1[11:7] == 5'd1) ||
                        (inst_in1[11:7] == 5'd5));
    assign ras_return0 = (fs_out_inst[6:0] == 7'b1100111) &&
                         (fs_out_inst[11:7] == 5'd0) &&
                         ((fs_out_inst[19:15] == 5'd1) ||
                          (fs_out_inst[19:15] == 5'd5)) &&
                         (fs_out_inst[31:20] == 12'd0);
    assign ras_return1 = (inst_in1[6:0] == 7'b1100111) &&
                         (inst_in1[11:7] == 5'd0) &&
                         ((inst_in1[19:15] == 5'd1) ||
                          (inst_in1[19:15] == 5'd5)) &&
                         (inst_in1[31:20] == 12'd0);
    // A trained BTB entry carries return classification, removing synchronous
    // IROM data decode from the same-cycle next-address path. Instruction
    // decode remains below for speculative RAS push/pop state updates.
    assign ras_pred_taken0 = (ras_spec_count != 0) && bp_hit0 &&
                             bp_lookup_is_return0;
    assign ras_pred_taken1 = (ras_spec_count != 0) && bp_hit1 &&
                             bp_lookup_is_return1;
    assign effective_pred_taken0 = ras_pred_taken0 || bp_pred_taken0;
    assign effective_pred_taken1 = ras_pred_taken1 || bp_pred_taken1;
    assign effective_pred_target0 = ras_pred_taken0 ? ras_top : bp_pred_target0;
    assign effective_pred_target1 = ras_pred_taken1 ? ras_top : bp_pred_target1;
    `else
    assign effective_pred_taken0 = bp_pred_taken0;
    assign effective_pred_taken1 = bp_pred_taken1;
    assign effective_pred_target0 = bp_pred_target0;
    assign effective_pred_target1 = bp_pred_target1;
    `endif

    assign imem_word_addr1 = next_pc[13:2] + 12'd1;
    assign imem_word_carry1 = &next_pc[13:2];
    assign imem_hi_addr1 = next_pc[31:14] + imem_word_carry1;

    logic fetch_kill;
    assign seq_pc = fs_out_pc + 8;
    assign next_pc = exception_flag ? exception_addr :
                     br_taken_reg ? br_target_reg :
                     effective_pred_taken0 ? effective_pred_target0 :
                     effective_pred_taken1 ? effective_pred_target1 :
                     seq_pc;
    logic fs_valid;
    logic fs_ready_go;
    logic fs_allowin;
    assign fs_ready_go = 1'b1;
    assign fs_allowin = !fs_valid || fs_ready_go && ds_allowin;
    assign fetch_kill = br_taken || br_taken_reg || exception_flag;
    assign fs_to_ds_valid = fs_valid && fs_ready_go && !fetch_kill;
    // lane0预测跳转时顺序lane1无效；lane1预测跳转时两条均有效，下一fetch转向目标。
    assign fs_to_ds_valid1 = fs_to_ds_valid && !effective_pred_taken0;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fs_valid <= 1'b0;
        end else if (fs_allowin) begin
            fs_valid <= 1'b1;
        end
        if (!rst_n) begin
            fs_pc <= `PC_START - 8;
        end else if (fs_allowin) begin
            fs_pc <= next_pc;
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            br_taken_reg <= 1'b0;
            br_target_reg <= 32'b0;
        end else if (exception_flag) begin
            // A trap redirect is older than any branch currently leaving EX.
            // Do not retain that younger branch for replay after the one-cycle
            // exception pulse has cleared.
            br_taken_reg <= 1'b0;
            br_target_reg <= 32'b0;
        end else if (fs_allowin) begin
            br_taken_reg <= br_taken;
            br_target_reg <= br_target;
        end
    end

    // 将远端EX/flush生成的更新请求先收进IF本地寄存器，切断其到128项表写口的长路径。
    // 更新延后一拍，但仍保持每拍一个请求的吞吐率。
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bp_update_valid_r <= 1'b0;
            bp_update_pc_r <= '0;
            bp_update_taken_r <= 1'b0;
            bp_update_target_r <= '0;
            bp_update_is_return_r <= 1'b0;
        end else begin
            bp_update_valid_r <= bp_update_valid;
            if (bp_update_valid) begin
                bp_update_pc_r <= bp_update_pc;
                bp_update_taken_r <= bp_update_taken;
                bp_update_target_r <= bp_update_target;
                bp_update_is_return_r <= bp_update_is_return;
            end
        end
    end

    // Only validity bits need reset. The payload copies retain don't-care data
    // while invalid, which is required for distributed-RAM inference.
    always_ff @(posedge clk) begin
        integer i;
        if (!rst_n) begin
            for (i = 0; i < BP_ENTRIES; i = i + 1) begin
                bp_valid_lookup0[i] <= 1'b0;
                bp_valid_lookup1[i] <= 1'b0;
                bp_valid_update[i] <= 1'b0;
            end
        end else if (bp_update_valid_r) begin
            bp_valid_lookup0[bp_update_index] <= 1'b1;
            bp_valid_lookup1[bp_update_index] <= 1'b1;
            bp_valid_update[bp_update_index] <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (bp_update_valid_r) begin
            bp_mem_lookup0[bp_update_index] <= bp_update_entry_next;
            bp_mem_lookup1[bp_update_index] <= bp_update_entry_next;
            bp_mem_update[bp_update_index] <= bp_update_entry_next;
        end
    end

    // Explicit write-through defines the read-during-write case independently
    // of the inferred block-RAM mode. Holding fs_allowin also holds the IROM
    // response, fs_pc and these BTB response registers together.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bp_lookup_entry0 <= '0;
            bp_lookup_entry1 <= '0;
            bp_lookup_valid0 <= 1'b0;
            bp_lookup_valid1 <= 1'b0;
        end else if (fs_allowin) begin
            if (bp_update_valid_r &&
                (bp_update_index == bp_request_index0)) begin
                bp_lookup_entry0 <= bp_update_entry_next;
                bp_lookup_valid0 <= 1'b1;
            end else begin
                bp_lookup_entry0 <= bp_mem_lookup0[bp_request_index0];
                bp_lookup_valid0 <= bp_valid_lookup0[bp_request_index0];
            end

            if (bp_update_valid_r &&
                (bp_update_index == bp_request_index1)) begin
                bp_lookup_entry1 <= bp_update_entry_next;
                bp_lookup_valid1 <= 1'b1;
            end else begin
                bp_lookup_entry1 <= bp_mem_lookup1[bp_request_index1];
                bp_lookup_valid1 <= bp_valid_lookup1[bp_request_index1];
            end
        end
    end

    `ifndef L3I_DISABLE_RAS
    always_ff @(posedge clk) begin
        integer ras_i;
        if (!rst_n) begin
            ras_commit_sp <= '0;
            ras_commit_count <= '0;
            ras_spec_sp <= '0;
            ras_spec_count <= '0;
            for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
                ras_commit_stack[ras_i] <= '0;
                ras_spec_stack[ras_i] <= '0;
            end
        end else if (exception_flag) begin
            ras_commit_sp <= '0;
            ras_commit_count <= '0;
            ras_spec_sp <= '0;
            ras_spec_count <= '0;
        end else begin
            if (bp_update_valid && bp_update_is_call) begin
                ras_commit_stack[ras_commit_sp] <= bp_update_pc + 32'd4;
                ras_commit_sp <= ras_commit_sp + 1'b1;
                if (ras_commit_count < RAS_DEPTH) begin
                    ras_commit_count <= ras_commit_count + 1'b1;
                end
            end else if (bp_update_valid && bp_update_is_return &&
                         (ras_commit_count != 0)) begin
                ras_commit_sp <= ras_commit_sp - 1'b1;
                ras_commit_count <= ras_commit_count - 1'b1;
            end

            // Redirect recovery is delayed to br_taken_reg. The committed RAS
            // was updated one edge earlier from bp_update_valid, so copying it
            // here is sufficient; replaying the registered call/return would
            // push or pop the resolving branch twice.
            if (br_taken_reg) begin
                for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
                    ras_spec_stack[ras_i] <= ras_commit_stack[ras_i];
                end
                ras_spec_sp <= ras_commit_sp;
                ras_spec_count <= ras_commit_count;
            end else if (fs_to_ds_valid && ds_allowin) begin
                if (ras_call0) begin
                    ras_spec_stack[ras_spec_sp] <= fs_out_pc + 32'd4;
                    ras_spec_sp <= ras_spec_sp + 1'b1;
                    if (ras_spec_count < RAS_DEPTH) begin
                        ras_spec_count <= ras_spec_count + 1'b1;
                    end
                end else if (ras_return0 && (ras_spec_count != 0)) begin
                    ras_spec_sp <= ras_spec_sp - 1'b1;
                    ras_spec_count <= ras_spec_count - 1'b1;
                end else if (fs_to_ds_valid1 && ras_call1) begin
                    ras_spec_stack[ras_spec_sp] <= fs_out_pc + 32'd8;
                    ras_spec_sp <= ras_spec_sp + 1'b1;
                    if (ras_spec_count < RAS_DEPTH) begin
                        ras_spec_count <= ras_spec_count + 1'b1;
                    end
                end else if (fs_to_ds_valid1 && ras_return1 &&
                             (ras_spec_count != 0)) begin
                    ras_spec_sp <= ras_spec_sp - 1'b1;
                    ras_spec_count <= ras_spec_count - 1'b1;
                end
            end
        end
    end
    `endif

    assign pc_out = next_pc;
    assign fs_out_inst = (br_taken || br_taken_reg || exception_flag) ? `NOP_INST : inst_in; // 分支指令在分支预测失败时用NOP占位
    assign inst_ren = fs_allowin;
    assign fs_out_pc = fs_pc;
    assign fs_to_ds_bus = {fs_out_inst, fs_out_pc,
                           (effective_pred_taken0 && !br_taken && !br_taken_reg && !exception_flag),
                           effective_pred_target0};
    assign pc_out1 = {imem_hi_addr1, imem_word_addr1, next_pc[1:0]};
    assign inst_ren1 = fs_allowin;
    assign fs_to_ds_bus1 = {inst_in1, fs_out_pc + 32'd4,
                            (effective_pred_taken1 && !br_taken && !br_taken_reg && !exception_flag),
                            effective_pred_target1};

    /*logic exception_iam;
    assign exception_iam = fs_to_ds_valid && fs_out_pc[1:0] != 2'b00;*/
    logic [6:0] exception_code;
    assign exception_code = /*exception_iam ? 7'b010_0000 : */7'b000_0000; 
    logic [`MTVAL_WIDTH-1:0] exception_mtval;
    assign exception_mtval = /*exception_iam ? fs_out_pc : */32'b0;
    assign fs_exc_bus = {exception_code, exception_mtval};

endmodule
