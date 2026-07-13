`include "defines.svh"

module if_stage (
    input  logic                         clk,
    input  logic                         rst_n,
    // Dual-lane synchronous instruction-memory request/response.
    output logic [`ADDR_WIDTH-1:0]       pc_out,
    output logic [`ADDR_WIDTH-1:0]       pc_out1,
    output logic                         inst_ren,
    input  logic [`DATA_WIDTH-1:0]       inst_in,
    input  logic [`DATA_WIDTH-1:0]       inst_in1,
    // Atomic IF1 packet output into the A2 Fetch FIFO.
    input  logic [3:0]                   fetch_free_count,
    output logic [1:0]                   fetch_push_count,
    output logic [`FETCH_UOP_WIDTH-1:0]  fetch_push_uop0,
    output logic [`FETCH_UOP_WIDTH-1:0]  fetch_push_uop1,
    output logic                         frontend_redirect,
    // Redirect interface.
    input  logic                         br_taken,
    input  logic [`ADDR_WIDTH-1:0]       br_target,
    // Resolved predictor update interface.
    input  logic                         bp_update_valid,
    input  logic [`ADDR_WIDTH-1:0]       bp_update_pc,
    input  logic                         bp_update_taken,
    input  logic [`ADDR_WIDTH-1:0]       bp_update_target,
    input  logic [`BP_TYPE_WIDTH-1:0]    bp_update_type,
    // Exception metadata and redirect.
    output logic [`EXC_WIDTH-1:0]        fs_exc_bus,
    input  logic                         exception_flag,
    input  logic [`ADDR_WIDTH-1:0]       exception_addr
);

    localparam integer BTB_INDEX_WIDTH = 7;
    localparam integer BTB_ENTRIES = 1 << BTB_INDEX_WIDTH;
    localparam integer BTB_TAG_WIDTH = `ADDR_WIDTH - BTB_INDEX_WIDTH - 2;
    localparam integer RAS_DEPTH = 8;

    logic [`FETCH_EPOCH_WIDTH-1:0] if_epoch;
    logic if_active;
    logic [`ADDR_WIDTH-1:0] if0_pc;
    logic [`FETCH_AGE_WIDTH-1:0] age_counter;

    logic req_valid;
    logic [`FETCH_EPOCH_WIDTH-1:0] req_epoch;
    logic [`ADDR_WIDTH-1:0] req_pc;
    logic req_ras_valid;
    logic [`ADDR_WIDTH-1:0] req_ras_target;

    logic packet_valid;
    logic [1:0] packet_count;
    logic [`FETCH_EPOCH_WIDTH-1:0] packet_epoch;
    logic [`ADDR_WIDTH-1:0] packet_pc;
    logic [`DATA_WIDTH-1:0] packet_inst0;
    logic [`DATA_WIDTH-1:0] packet_inst1;
    logic packet_pred_taken0;
    logic packet_pred_taken1;
    logic [`ADDR_WIDTH-1:0] packet_pred_target0;
    logic [`ADDR_WIDTH-1:0] packet_pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] packet_pred_type0;
    logic [`BP_TYPE_WIDTH-1:0] packet_pred_type1;
    logic packet_btb_hit0;
    logic packet_btb_hit1;
    logic packet_ras_valid;
    logic [`ADDR_WIDTH-1:0] packet_ras_target;

    logic [BTB_ENTRIES-1:0] btb_valid0;
    logic [BTB_ENTRIES-1:0] btb_valid1;
    logic [BTB_TAG_WIDTH-1:0] btb_tag0 [0:BTB_ENTRIES-1];
    logic [BTB_TAG_WIDTH-1:0] btb_tag1 [0:BTB_ENTRIES-1];
    logic [1:0] btb_counter0 [0:BTB_ENTRIES-1];
    logic [1:0] btb_counter1 [0:BTB_ENTRIES-1];
    logic [`ADDR_WIDTH-1:0] btb_target0 [0:BTB_ENTRIES-1];
    logic [`ADDR_WIDTH-1:0] btb_target1 [0:BTB_ENTRIES-1];
    logic [`BP_TYPE_WIDTH-1:0] btb_type0 [0:BTB_ENTRIES-1];
    logic [`BP_TYPE_WIDTH-1:0] btb_type1 [0:BTB_ENTRIES-1];

    logic btb_q_valid0;
    logic btb_q_valid1;
    logic [BTB_TAG_WIDTH-1:0] btb_q_tag0;
    logic [BTB_TAG_WIDTH-1:0] btb_q_tag1;
    logic [1:0] btb_q_counter0;
    logic [1:0] btb_q_counter1;
    logic [`ADDR_WIDTH-1:0] btb_q_target0;
    logic [`ADDR_WIDTH-1:0] btb_q_target1;
    logic [`BP_TYPE_WIDTH-1:0] btb_q_type0;
    logic [`BP_TYPE_WIDTH-1:0] btb_q_type1;

    logic [`ADDR_WIDTH-1:0] ras_stack [0:RAS_DEPTH-1];
    logic [$clog2(RAS_DEPTH)-1:0] ras_sp;
    logic [$clog2(RAS_DEPTH+1)-1:0] ras_count;
    logic [`ADDR_WIDTH-1:0] ras_commit_stack [0:RAS_DEPTH-1];
    logic [$clog2(RAS_DEPTH)-1:0] ras_commit_sp;
    logic [$clog2(RAS_DEPTH+1)-1:0] ras_commit_count;

    logic redirect_event;
    logic [`ADDR_WIDTH-1:0] redirect_pc;
    logic request_fire;
    logic packet_fire;

    logic [BTB_INDEX_WIDTH-1:0] request_index0;
    logic [BTB_INDEX_WIDTH-1:0] request_index1;
    logic [`ADDR_WIDTH-1:0] request_pc1;
    logic [`ADDR_WIDTH-1:0] req_pc1;
    logic [BTB_INDEX_WIDTH-1:0] update_index;
    logic [BTB_TAG_WIDTH-1:0] update_tag;
    logic update_tag_match;
    logic [1:0] update_counter_next;

    logic btb_hit0;
    logic btb_hit1;
    logic pred_taken0;
    logic pred_taken1;
    logic [`ADDR_WIDTH-1:0] pred_target0;
    logic [`ADDR_WIDTH-1:0] pred_target1;
    logic [`ADDR_WIDTH-1:0] predicted_packet_next_pc;

    logic [$clog2(RAS_DEPTH)-1:0] ras_top_index;
    logic [`ADDR_WIDTH-1:0] ras_top_value;
    logic [$clog2(RAS_DEPTH)-1:0] ras_after_pop_index;
    logic [`ADDR_WIDTH-1:0] ras_after_pop_value;
    logic packet_lane0_call;
    logic packet_lane0_return;
    logic packet_lane1_call;
    logic packet_lane1_return;
    logic packet_ras_call;
    logic packet_ras_return;
    logic [`ADDR_WIDTH-1:0] packet_ras_return_pc;
    logic packet_contains_ras_op;

    function automatic logic [1:0] counter_update(
        input logic [1:0] current,
        input logic       taken
    );
        begin
            if (taken) begin
                counter_update = (current == 2'b11) ? current : current + 1'b1;
            end else begin
                counter_update = (current == 2'b00) ? current : current - 1'b1;
            end
        end
    endfunction

    function automatic logic instruction_is_call(input logic [31:0] inst);
        logic is_jal;
        logic is_jalr;
        begin
            is_jal = (inst[6:0] == 7'b1101111);
            is_jalr = (inst[6:0] == 7'b1100111);
            instruction_is_call = (is_jal || is_jalr) &&
                                  ((inst[11:7] == 5'd1) ||
                                   (inst[11:7] == 5'd5));
        end
    endfunction

    function automatic logic instruction_is_return(input logic [31:0] inst);
        instruction_is_return = (inst[6:0] == 7'b1100111) &&
                                (inst[11:7] == 5'd0) &&
                                ((inst[19:15] == 5'd1) ||
                                 (inst[19:15] == 5'd5)) &&
                                (inst[31:20] == 12'd0);
    endfunction

    assign redirect_event = exception_flag || (br_taken && bp_update_valid);
    assign redirect_pc = exception_flag ? exception_addr : br_target;

    assign inst_ren = rst_n && if_active && !redirect_event &&
                      !req_valid && (!packet_valid || packet_fire);
    assign request_fire = inst_ren;
    assign pc_out = if0_pc;
    assign pc_out1 = if0_pc + 32'd4;
    assign frontend_redirect = redirect_event;

    assign request_pc1 = if0_pc + 32'd4;
    assign req_pc1 = req_pc + 32'd4;
    assign request_index0 = if0_pc[BTB_INDEX_WIDTH+1:2];
    assign request_index1 = request_pc1[BTB_INDEX_WIDTH+1:2];
    assign update_index = bp_update_pc[BTB_INDEX_WIDTH+1:2];
    assign update_tag = bp_update_pc[`ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign update_tag_match = btb_valid0[update_index] &&
                              (btb_tag0[update_index] == update_tag);
    assign update_counter_next = update_tag_match ?
                                 counter_update(btb_counter0[update_index],
                                                bp_update_taken) :
                                 (bp_update_taken ? 2'b10 : 2'b01);

    // Both BTB copies are updated together.  A query colliding with an update
    // to the same index observes the new entry (explicit write-through).
    always_ff @(posedge clk) begin : btb_state
        integer i;
        if (!rst_n) begin
            btb_valid0 <= '0;
            btb_valid1 <= '0;
            btb_q_valid0 <= 1'b0;
            btb_q_valid1 <= 1'b0;
            btb_q_tag0 <= '0;
            btb_q_tag1 <= '0;
            btb_q_counter0 <= 2'b01;
            btb_q_counter1 <= 2'b01;
            btb_q_target0 <= '0;
            btb_q_target1 <= '0;
            btb_q_type0 <= `BP_TYPE_BRANCH;
            btb_q_type1 <= `BP_TYPE_BRANCH;
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_tag0[i] <= '0;
                btb_tag1[i] <= '0;
                btb_counter0[i] <= 2'b01;
                btb_counter1[i] <= 2'b01;
                btb_target0[i] <= '0;
                btb_target1[i] <= '0;
                btb_type0[i] <= `BP_TYPE_BRANCH;
                btb_type1[i] <= `BP_TYPE_BRANCH;
            end
        end else begin
            if (bp_update_valid) begin
                btb_valid0[update_index] <= 1'b1;
                btb_valid1[update_index] <= 1'b1;
                btb_tag0[update_index] <= update_tag;
                btb_tag1[update_index] <= update_tag;
                btb_counter0[update_index] <= update_counter_next;
                btb_counter1[update_index] <= update_counter_next;
                btb_target0[update_index] <= bp_update_target;
                btb_target1[update_index] <= bp_update_target;
                btb_type0[update_index] <= bp_update_type;
                btb_type1[update_index] <= bp_update_type;
            end

            if (request_fire) begin
                if (bp_update_valid && (update_index == request_index0)) begin
                    btb_q_valid0 <= 1'b1;
                    btb_q_tag0 <= update_tag;
                    btb_q_counter0 <= update_counter_next;
                    btb_q_target0 <= bp_update_target;
                    btb_q_type0 <= bp_update_type;
                end else begin
                    btb_q_valid0 <= btb_valid0[request_index0];
                    btb_q_tag0 <= btb_tag0[request_index0];
                    btb_q_counter0 <= btb_counter0[request_index0];
                    btb_q_target0 <= btb_target0[request_index0];
                    btb_q_type0 <= btb_type0[request_index0];
                end

                if (bp_update_valid && (update_index == request_index1)) begin
                    btb_q_valid1 <= 1'b1;
                    btb_q_tag1 <= update_tag;
                    btb_q_counter1 <= update_counter_next;
                    btb_q_target1 <= bp_update_target;
                    btb_q_type1 <= bp_update_type;
                end else begin
                    btb_q_valid1 <= btb_valid1[request_index1];
                    btb_q_tag1 <= btb_tag1[request_index1];
                    btb_q_counter1 <= btb_counter1[request_index1];
                    btb_q_target1 <= btb_target1[request_index1];
                    btb_q_type1 <= btb_type1[request_index1];
                end
            end
        end
    end

    assign ras_top_index = ras_sp - 1'b1;
    assign ras_top_value = ras_stack[ras_top_index];
    assign ras_after_pop_index = ras_sp - 2'd2;
    assign ras_after_pop_value = ras_stack[ras_after_pop_index];
    assign packet_lane0_call = instruction_is_call(packet_inst0);
    assign packet_lane0_return = instruction_is_return(packet_inst0);
    assign packet_lane1_call = (packet_count == 2) &&
                               instruction_is_call(packet_inst1);
    assign packet_lane1_return = (packet_count == 2) &&
                                 instruction_is_return(packet_inst1);
    assign packet_ras_call = packet_lane0_call ||
                             (!packet_lane0_return && packet_lane1_call);
    assign packet_ras_return = packet_lane0_return ||
                               (!packet_lane0_call && packet_lane1_return);
    assign packet_ras_return_pc = (packet_lane0_call || packet_lane0_return) ?
                                  packet_pc + 32'd4 : packet_pc + 32'd8;
    assign packet_contains_ras_op = packet_ras_call || packet_ras_return;

    // The committed RAS is updated exactly once at branch_resolve_fire.  The
    // speculative RAS follows packets entering the Fetch FIFO and is restored
    // from committed state on every redirect.
    always_ff @(posedge clk) begin : ras_state
        integer i;
        if (!rst_n) begin
            ras_sp <= '0;
            ras_count <= '0;
            ras_commit_sp <= '0;
            ras_commit_count <= '0;
            for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                ras_stack[i] <= '0;
                ras_commit_stack[i] <= '0;
            end
        end else begin
            if (bp_update_valid) begin
                if (bp_update_type == `BP_TYPE_CALL) begin
                    ras_commit_stack[ras_commit_sp] <= bp_update_pc + 32'd4;
                    ras_commit_sp <= ras_commit_sp + 1'b1;
                    if (ras_commit_count != RAS_DEPTH) begin
                        ras_commit_count <= ras_commit_count + 1'b1;
                    end
                end else if ((bp_update_type == `BP_TYPE_RETURN) &&
                             (ras_commit_count != 0)) begin
                    ras_commit_sp <= ras_commit_sp - 1'b1;
                    ras_commit_count <= ras_commit_count - 1'b1;
                end
            end

            if (redirect_event) begin
                for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                    ras_stack[i] <= ras_commit_stack[i];
                end
                ras_sp <= ras_commit_sp;
                ras_count <= ras_commit_count;

                // Include the resolving control instruction in the recovery
                // image because committed registers update on this same edge.
                if (bp_update_valid && (bp_update_type == `BP_TYPE_CALL)) begin
                    ras_stack[ras_commit_sp] <= bp_update_pc + 32'd4;
                    ras_sp <= ras_commit_sp + 1'b1;
                    if (ras_commit_count != RAS_DEPTH) begin
                        ras_count <= ras_commit_count + 1'b1;
                    end
                end else if (bp_update_valid &&
                             (bp_update_type == `BP_TYPE_RETURN) &&
                             (ras_commit_count != 0)) begin
                    ras_sp <= ras_commit_sp - 1'b1;
                    ras_count <= ras_commit_count - 1'b1;
                end
            end else if (packet_fire) begin
                if (packet_ras_call) begin
                    ras_stack[ras_sp] <= packet_ras_return_pc;
                    ras_sp <= ras_sp + 1'b1;
                    if (ras_count != RAS_DEPTH) begin
                        ras_count <= ras_count + 1'b1;
                    end
                end else if (packet_ras_return && (ras_count != 0)) begin
                    ras_sp <= ras_sp - 1'b1;
                    ras_count <= ras_count - 1'b1;
                end
            end
        end
    end

    assign btb_hit0 = btb_q_valid0 &&
                      (btb_q_tag0 == req_pc[`ADDR_WIDTH-1:BTB_INDEX_WIDTH+2]);
    assign btb_hit1 = btb_q_valid1 &&
                      (btb_q_tag1 == req_pc1[`ADDR_WIDTH-1:BTB_INDEX_WIDTH+2]);
    assign pred_taken0 = btb_hit0 &&
                         ((btb_q_type0 != `BP_TYPE_BRANCH) ||
                          btb_q_counter0[1]);
    assign pred_taken1 = btb_hit1 &&
                         ((btb_q_type1 != `BP_TYPE_BRANCH) ||
                          btb_q_counter1[1]);
    assign pred_target0 = ((btb_q_type0 == `BP_TYPE_RETURN) && req_ras_valid) ?
                          req_ras_target : btb_q_target0;
    assign pred_target1 = ((btb_q_type1 == `BP_TYPE_RETURN) && req_ras_valid) ?
                          req_ras_target : btb_q_target1;
    assign predicted_packet_next_pc = pred_taken0 ? pred_target0 :
                                      pred_taken1 ? pred_target1 :
                                      req_pc + 32'd8;

    // Keep IF0 idle for one complete clock after reset release.  Besides being
    // a clean hardware reset boundary, this prevents a request/RAM disagreement
    // when a testbench deasserts reset on the active clock edge.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            if_active <= 1'b0;
        end else begin
            if_active <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin : request_and_packet_state
        if (!rst_n) begin
            if_epoch <= '0;
            if0_pc <= `PC_START;
            age_counter <= '0;
            req_valid <= 1'b0;
            req_epoch <= '0;
            req_pc <= '0;
            req_ras_valid <= 1'b0;
            req_ras_target <= '0;
            packet_valid <= 1'b0;
            packet_count <= 2'd0;
            packet_epoch <= '0;
            packet_pc <= '0;
            packet_inst0 <= `NOP_INST;
            packet_inst1 <= `NOP_INST;
            packet_pred_taken0 <= 1'b0;
            packet_pred_taken1 <= 1'b0;
            packet_pred_target0 <= '0;
            packet_pred_target1 <= '0;
            packet_pred_type0 <= `BP_TYPE_BRANCH;
            packet_pred_type1 <= `BP_TYPE_BRANCH;
            packet_btb_hit0 <= 1'b0;
            packet_btb_hit1 <= 1'b0;
            packet_ras_valid <= 1'b0;
            packet_ras_target <= '0;
        end else if (redirect_event) begin
            if_epoch <= if_epoch + 1'b1;
            if0_pc <= redirect_pc;
            req_valid <= 1'b0;
            packet_valid <= 1'b0;
            packet_count <= 2'd0;
        end else begin
            if (request_fire) begin
                req_valid <= 1'b1;
                req_epoch <= if_epoch;
                req_pc <= if0_pc;
                if (packet_fire && packet_ras_call) begin
                    req_ras_valid <= 1'b1;
                    req_ras_target <= packet_ras_return_pc;
                end else if (packet_fire && packet_ras_return) begin
                    req_ras_valid <= (ras_count > 1);
                    req_ras_target <= ras_after_pop_value;
                end else begin
                    req_ras_valid <= (ras_count != 0);
                    req_ras_target <= ras_top_value;
                end
            end

            if (packet_fire) begin
                packet_valid <= 1'b0;
                packet_count <= 2'd0;
                age_counter <= age_counter + packet_count;
            end

            if (req_valid) begin
                req_valid <= 1'b0;
                if (req_epoch == if_epoch) begin
                    if0_pc <= predicted_packet_next_pc;
                    packet_valid <= 1'b1;
                    packet_count <= pred_taken0 ? 2'd1 : 2'd2;
                    packet_epoch <= req_epoch;
                    packet_pc <= req_pc;
                    packet_inst0 <= inst_in;
                    packet_inst1 <= inst_in1;
                    packet_pred_taken0 <= pred_taken0;
                    packet_pred_taken1 <= pred_taken1;
                    packet_pred_target0 <= pred_target0;
                    packet_pred_target1 <= pred_target1;
                    packet_pred_type0 <= btb_q_type0;
                    packet_pred_type1 <= btb_q_type1;
                    packet_btb_hit0 <= btb_hit0;
                    packet_btb_hit1 <= btb_hit1;
                    packet_ras_valid <= req_ras_valid;
                    packet_ras_target <= req_ras_target;
                end
            end
        end
    end

    assign fetch_push_count = (!redirect_event && packet_valid &&
                               (fetch_free_count >= packet_count)) ?
                              packet_count : 2'd0;
    assign packet_fire = (fetch_push_count != 0);
    assign fetch_push_uop0 = {
        packet_epoch,
        age_counter,
        packet_inst0,
        packet_pc,
        packet_pred_taken0,
        packet_pred_target0,
        packet_pred_type0,
        packet_btb_hit0,
        packet_ras_valid,
        packet_ras_target
    };
    assign fetch_push_uop1 = {
        packet_epoch,
        age_counter + 1'b1,
        packet_inst1,
        packet_pc + 32'd4,
        packet_pred_taken1,
        packet_pred_target1,
        packet_pred_type1,
        packet_btb_hit1,
        packet_ras_valid,
        packet_ras_target
    };

    assign fs_exc_bus = {7'b0, {`MTVAL_WIDTH{1'b0}}};

endmodule
