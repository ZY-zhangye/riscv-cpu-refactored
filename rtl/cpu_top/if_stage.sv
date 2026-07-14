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
    localparam integer BTB_ENTRY_WIDTH = BTB_TAG_WIDTH + 2 +
                                         `ADDR_WIDTH + `BP_TYPE_WIDTH;
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
    logic [`ADDR_WIDTH-1:0] packet_next_pc;

    logic response_valid;
    logic [1:0] response_count;
    logic response_fire;
    logic response_hold;
    logic output_packet_valid;
    logic [1:0] output_packet_count;
    logic [`FETCH_EPOCH_WIDTH-1:0] output_packet_epoch;
    logic [`ADDR_WIDTH-1:0] output_packet_pc;
    logic [`DATA_WIDTH-1:0] output_packet_inst0;
    logic [`DATA_WIDTH-1:0] output_packet_inst1;
    logic output_packet_pred_taken0;
    logic output_packet_pred_taken1;
    logic [`ADDR_WIDTH-1:0] output_packet_pred_target0;
    logic [`ADDR_WIDTH-1:0] output_packet_pred_target1;
    logic [`BP_TYPE_WIDTH-1:0] output_packet_pred_type0;
    logic [`BP_TYPE_WIDTH-1:0] output_packet_pred_type1;
    logic output_packet_btb_hit0;
    logic output_packet_btb_hit1;
    logic output_packet_ras_valid;
    logic [`ADDR_WIDTH-1:0] output_packet_ras_target;
    logic [`ADDR_WIDTH-1:0] output_packet_next_pc;

    logic [BTB_ENTRIES-1:0] btb_valid0;
    logic [BTB_ENTRIES-1:0] btb_valid1;
    logic [BTB_ENTRIES-1:0] btb_valid_update;
    // The lookup copies have one synchronous read and one update write each.
    // The small distributed shadow supplies the asynchronous read needed by
    // the saturating-counter read/modify/write path.  Payload RAMs are not
    // reset; validity is the architectural reset state.
    (* ram_style = "distributed" *)
    logic [BTB_ENTRY_WIDTH-1:0] btb_lookup_mem0 [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [BTB_ENTRY_WIDTH-1:0] btb_lookup_mem1 [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [BTB_ENTRY_WIDTH-1:0] btb_update_mem [0:BTB_ENTRIES-1];

    logic btb_q_valid0;
    logic btb_q_valid1;
    logic [BTB_ENTRY_WIDTH-1:0] btb_q_entry0;
    logic [BTB_ENTRY_WIDTH-1:0] btb_q_entry1;
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
    logic [`ADDR_WIDTH-1:0] request_pc;
    logic request_fire;
    logic packet_fire;

    logic [BTB_INDEX_WIDTH-1:0] request_index0;
    logic [BTB_INDEX_WIDTH-1:0] request_index1;
    logic [`ADDR_WIDTH-1:0] request_pc1;
    logic lane1_index_wrap;
    logic [BTB_INDEX_WIDTH-1:0] update_index;
    logic [BTB_TAG_WIDTH-1:0] update_tag;
    logic [BTB_ENTRY_WIDTH-1:0] update_entry;
    logic [BTB_ENTRY_WIDTH-1:0] update_entry_next;
    logic [BTB_TAG_WIDTH-1:0] update_entry_tag;
    logic [1:0] update_entry_counter;
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

    // A live one-cycle IROM response normally bypasses the skid packet and is
    // pushed directly into the Fetch FIFO.  Its predicted next PC may launch a
    // new request on the same edge.  If the response cannot push, it occupies
    // packet_valid and request issue stops until that complete packet releases.
    assign response_valid = req_valid && (req_epoch == if_epoch);
    assign response_count = pred_taken0 ? 2'd1 : 2'd2;
    assign response_fire = !packet_valid && response_valid && packet_fire;
    assign response_hold = response_valid && !response_fire;
    assign request_pc = packet_fire ? output_packet_next_pc : if0_pc;
    assign request_fire = rst_n && if_active && !redirect_event &&
                          ((req_valid && response_fire) ||
                           (!req_valid && (!packet_valid || packet_fire)));
    assign inst_ren = request_fire;
    assign pc_out = request_pc;
    assign pc_out1 = request_pc + 32'd4;
    assign frontend_redirect = redirect_event;

    assign request_pc1 = request_pc + 32'd4;
    assign request_index0 = request_pc[BTB_INDEX_WIDTH+1:2];
    assign request_index1 = request_pc1[BTB_INDEX_WIDTH+1:2];
    assign lane1_index_wrap = &req_pc[BTB_INDEX_WIDTH+1:2];
    assign update_index = bp_update_pc[BTB_INDEX_WIDTH+1:2];
    assign update_tag = bp_update_pc[`ADDR_WIDTH-1:BTB_INDEX_WIDTH+2];
    assign update_entry = btb_update_mem[update_index];
    assign {update_entry_tag, update_entry_counter} =
        update_entry[BTB_ENTRY_WIDTH-1 -: BTB_TAG_WIDTH+2];
    assign update_tag_match = btb_valid_update[update_index] &&
                              (update_entry_tag == update_tag);
    assign update_counter_next = update_tag_match ?
                                 counter_update(update_entry_counter,
                                                bp_update_taken) :
                                 (bp_update_taken ? 2'b10 : 2'b01);
    assign update_entry_next = {
        update_tag,
        update_counter_next,
        bp_update_target,
        bp_update_type
    };

    assign {
        btb_q_tag0,
        btb_q_counter0,
        btb_q_target0,
        btb_q_type0
    } = btb_q_entry0;
    assign {
        btb_q_tag1,
        btb_q_counter1,
        btb_q_target1,
        btb_q_type1
    } = btb_q_entry1;

    // Both BTB copies are updated together.  A query colliding with an update
    // to the same index observes the new entry (explicit write-through).
    always_ff @(posedge clk) begin : btb_valid_state
        if (!rst_n) begin
            btb_valid0 <= '0;
            btb_valid1 <= '0;
            btb_valid_update <= '0;
        end else if (bp_update_valid) begin
            btb_valid0[update_index] <= 1'b1;
            btb_valid1[update_index] <= 1'b1;
            btb_valid_update[update_index] <= 1'b1;
        end
    end

    // Query payload registers update every cycle.  req_valid/q_valid determine
    // whether the data belongs to a live IROM response, so holding stale query
    // metadata is unnecessary and would add a wide CE mux to this path.
    always_ff @(posedge clk) begin : btb_lookup_ram0
        if (bp_update_valid) begin
            btb_lookup_mem0[update_index] <= update_entry_next;
        end
        if (!rst_n) begin
            btb_q_entry0 <= '0;
        end else if (bp_update_valid &&
                     (update_index == request_index0)) begin
            btb_q_entry0 <= update_entry_next;
        end else begin
            btb_q_entry0 <= btb_lookup_mem0[request_index0];
        end
    end

    always_ff @(posedge clk) begin : btb_lookup_ram1
        if (bp_update_valid) begin
            btb_lookup_mem1[update_index] <= update_entry_next;
        end
        if (!rst_n) begin
            btb_q_entry1 <= '0;
        end else if (bp_update_valid &&
                     (update_index == request_index1)) begin
            btb_q_entry1 <= update_entry_next;
        end else begin
            btb_q_entry1 <= btb_lookup_mem1[request_index1];
        end
    end

    always_ff @(posedge clk) begin : btb_update_shadow_write
        if (bp_update_valid) begin
            btb_update_mem[update_index] <= update_entry_next;
        end
    end

    always_ff @(posedge clk) begin : btb_lookup_state
        if (!rst_n) begin
            btb_q_valid0 <= 1'b0;
            btb_q_valid1 <= 1'b0;
        end else begin
            btb_q_valid0 <= request_fire &&
                ((bp_update_valid && (update_index == request_index0)) ||
                 btb_valid0[request_index0]);
            btb_q_valid1 <= request_fire &&
                ((bp_update_valid && (update_index == request_index1)) ||
                 btb_valid1[request_index1]);
        end
    end

    assign ras_top_index = ras_sp - 1'b1;
    assign ras_top_value = ras_stack[ras_top_index];
    assign ras_after_pop_index = ras_sp - 2'd2;
    assign ras_after_pop_value = ras_stack[ras_after_pop_index];
    assign packet_lane0_call = instruction_is_call(output_packet_inst0);
    assign packet_lane0_return = instruction_is_return(output_packet_inst0);
    assign packet_lane1_call = (output_packet_count == 2) &&
                               instruction_is_call(output_packet_inst1);
    assign packet_lane1_return = (output_packet_count == 2) &&
                                 instruction_is_return(output_packet_inst1);
    assign packet_ras_call = packet_lane0_call ||
                             (!packet_lane0_return && packet_lane1_call);
    assign packet_ras_return = packet_lane0_return ||
                               (!packet_lane0_call && packet_lane1_return);
    assign packet_ras_return_pc = (packet_lane0_call || packet_lane0_return) ?
                                  output_packet_pc + 32'd4 :
                                  output_packet_pc + 32'd8;
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
    // At the single 128-word boundary, suppress lane1 prediction instead of
    // carrying +4 through the full PC tag.  Sequential fetch remains correct;
    // only that boundary's optional lane1 prediction opportunity is skipped.
    assign btb_hit1 = !lane1_index_wrap && btb_q_valid1 &&
                      (btb_q_tag1 ==
                       req_pc[`ADDR_WIDTH-1:BTB_INDEX_WIDTH+2]);
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

    // packet_valid is a skid entry used only under backpressure.  In the
    // steady state the synchronous response drives the Fetch FIFO directly.
    assign output_packet_valid = packet_valid || response_valid;
    assign output_packet_count = packet_valid ? packet_count : response_count;
    assign output_packet_epoch = packet_valid ? packet_epoch : req_epoch;
    assign output_packet_pc = packet_valid ? packet_pc : req_pc;
    assign output_packet_inst0 = packet_valid ? packet_inst0 : inst_in;
    assign output_packet_inst1 = packet_valid ? packet_inst1 : inst_in1;
    assign output_packet_pred_taken0 = packet_valid ?
                                           packet_pred_taken0 : pred_taken0;
    assign output_packet_pred_taken1 = packet_valid ?
                                           packet_pred_taken1 : pred_taken1;
    assign output_packet_pred_target0 = packet_valid ?
                                            packet_pred_target0 : pred_target0;
    assign output_packet_pred_target1 = packet_valid ?
                                            packet_pred_target1 : pred_target1;
    assign output_packet_pred_type0 = packet_valid ?
                                          packet_pred_type0 : btb_q_type0;
    assign output_packet_pred_type1 = packet_valid ?
                                          packet_pred_type1 : btb_q_type1;
    assign output_packet_btb_hit0 = packet_valid ? packet_btb_hit0 : btb_hit0;
    assign output_packet_btb_hit1 = packet_valid ? packet_btb_hit1 : btb_hit1;
    assign output_packet_ras_valid = packet_valid ?
                                         packet_ras_valid : req_ras_valid;
    assign output_packet_ras_target = packet_valid ?
                                          packet_ras_target : req_ras_target;
    assign output_packet_next_pc = packet_valid ?
                                      packet_next_pc : predicted_packet_next_pc;

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
            packet_next_pc <= `PC_START;
        end else if (redirect_event) begin
            if_epoch <= if_epoch + 1'b1;
            if0_pc <= redirect_pc;
            req_valid <= 1'b0;
            packet_valid <= 1'b0;
            packet_count <= 2'd0;
        end else begin
            // Every request owns exactly the next synchronous response.  A
            // same-edge response bypass may replace it with a new request;
            // otherwise req_valid clears while a blocked response enters skid.
            req_valid <= request_fire;
            if (request_fire) begin
                req_epoch <= if_epoch;
                req_pc <= request_pc;
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
                if0_pc <= output_packet_next_pc;
                age_counter <= age_counter + output_packet_count;
                if (packet_valid) begin
                    packet_valid <= 1'b0;
                    packet_count <= 2'd0;
                end
            end

            if (response_hold) begin
                packet_valid <= 1'b1;
                packet_count <= response_count;
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
                packet_next_pc <= predicted_packet_next_pc;
            end
        end
    end

    assign fetch_push_count = (!redirect_event && output_packet_valid &&
                               (fetch_free_count >= output_packet_count)) ?
                              output_packet_count : 2'd0;
    assign packet_fire = (fetch_push_count != 0);
    assign fetch_push_uop0 = {
        output_packet_epoch,
        age_counter,
        output_packet_inst0,
        output_packet_pc,
        output_packet_pred_taken0,
        output_packet_pred_target0,
        output_packet_pred_type0,
        output_packet_btb_hit0,
        output_packet_ras_valid,
        output_packet_ras_target
    };
    assign fetch_push_uop1 = {
        output_packet_epoch,
        age_counter + 1'b1,
        output_packet_inst1,
        output_packet_pc + 32'd4,
        output_packet_pred_taken1,
        output_packet_pred_target1,
        output_packet_pred_type1,
        output_packet_btb_hit1,
        output_packet_ras_valid,
        output_packet_ras_target
    };

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && !redirect_event) begin
            if (packet_valid && req_valid) begin
                $fatal(1, "IF skid packet overlapped an in-flight response");
            end
            if (request_fire && req_valid && !response_fire) begin
                $fatal(1, "IF replaced an unconsumed synchronous response");
            end
            if (packet_fire &&
                ((output_packet_count == 0) || (output_packet_count > 2))) begin
                $fatal(1, "IF pushed an invalid packet count=%0d",
                       output_packet_count);
            end
        end
    end
`endif

    assign fs_exc_bus = {7'b0, {`MTVAL_WIDTH{1'b0}}};

endmodule
