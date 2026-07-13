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
    // A1 keeps the old single-uop Decode interface.  The IF1 packet is
    // serialized lane0 then lane1; A2 will replace this with the Fetch FIFO.
    input  logic                         ds_allowin,
    output logic                         fs_to_ds_valid,
    output logic [`FS_DS_WIDTH-1:0]      fs_to_ds_bus,
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

    logic if_epoch;
    logic if_active;
    logic [`ADDR_WIDTH-1:0] if0_pc;

    logic req_valid;
    logic req_epoch;
    logic [`ADDR_WIDTH-1:0] req_pc;
    logic req_ras_valid;
    logic [`ADDR_WIDTH-1:0] req_ras_target;

    logic packet_valid;
    logic packet_lane;
    logic packet_lane1_valid;
    logic [`ADDR_WIDTH-1:0] packet_pc;
    logic [`DATA_WIDTH-1:0] packet_inst0;
    logic [`DATA_WIDTH-1:0] packet_inst1;
    logic packet_pred_taken0;
    logic packet_pred_taken1;
    logic [`ADDR_WIDTH-1:0] packet_pred_target0;
    logic [`ADDR_WIDTH-1:0] packet_pred_target1;

    logic prefetch_valid;
    logic prefetch_lane1_valid;
    logic [`ADDR_WIDTH-1:0] prefetch_pc;
    logic [`DATA_WIDTH-1:0] prefetch_inst0;
    logic [`DATA_WIDTH-1:0] prefetch_inst1;
    logic prefetch_pred_taken0;
    logic prefetch_pred_taken1;
    logic [`ADDR_WIDTH-1:0] prefetch_pred_target0;
    logic [`ADDR_WIDTH-1:0] prefetch_pred_target1;

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

    logic redirect_event;
    logic [`ADDR_WIDTH-1:0] redirect_pc;
    logic request_fire;
    logic fs_fire;
    logic packet_last_fire;

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

    assign redirect_event = exception_flag || (br_taken && bp_update_valid);
    assign redirect_pc = exception_flag ? exception_addr : br_target;

    assign inst_ren = rst_n && if_active && !redirect_event &&
                      !req_valid && !prefetch_valid;
    assign request_fire = inst_ren;
    assign pc_out = if0_pc;
    assign pc_out1 = if0_pc + 32'd4;

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

    // A1 uses resolved control-flow updates for the RAS.  It is deliberately
    // non-speculative; the request captures the current top alongside its epoch.
    always_ff @(posedge clk) begin : ras_state
        integer i;
        if (!rst_n) begin
            ras_sp <= '0;
            ras_count <= '0;
            for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                ras_stack[i] <= '0;
            end
        end else if (bp_update_valid) begin
            if (bp_update_type == `BP_TYPE_CALL) begin
                ras_stack[ras_sp] <= bp_update_pc + 32'd4;
                ras_sp <= ras_sp + 1'b1;
                if (ras_count != RAS_DEPTH) begin
                    ras_count <= ras_count + 1'b1;
                end
            end else if ((bp_update_type == `BP_TYPE_RETURN) &&
                         (ras_count != 0)) begin
                ras_sp <= ras_sp - 1'b1;
                ras_count <= ras_count - 1'b1;
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
            if_epoch <= 1'b0;
            if0_pc <= `PC_START;
            req_valid <= 1'b0;
            req_epoch <= 1'b0;
            req_pc <= '0;
            req_ras_valid <= 1'b0;
            req_ras_target <= '0;
            packet_valid <= 1'b0;
            packet_lane <= 1'b0;
            packet_lane1_valid <= 1'b0;
            packet_pc <= '0;
            packet_inst0 <= `NOP_INST;
            packet_inst1 <= `NOP_INST;
            packet_pred_taken0 <= 1'b0;
            packet_pred_taken1 <= 1'b0;
            packet_pred_target0 <= '0;
            packet_pred_target1 <= '0;
            prefetch_valid <= 1'b0;
            prefetch_lane1_valid <= 1'b0;
            prefetch_pc <= '0;
            prefetch_inst0 <= `NOP_INST;
            prefetch_inst1 <= `NOP_INST;
            prefetch_pred_taken0 <= 1'b0;
            prefetch_pred_taken1 <= 1'b0;
            prefetch_pred_target0 <= '0;
            prefetch_pred_target1 <= '0;
        end else if (redirect_event) begin
            if_epoch <= ~if_epoch;
            if0_pc <= redirect_pc;
            req_valid <= 1'b0;
            packet_valid <= 1'b0;
            packet_lane <= 1'b0;
            packet_lane1_valid <= 1'b0;
            prefetch_valid <= 1'b0;
        end else begin
            if (request_fire) begin
                req_valid <= 1'b1;
                req_epoch <= if_epoch;
                req_pc <= if0_pc;
                if (bp_update_valid && (bp_update_type == `BP_TYPE_CALL)) begin
                    req_ras_valid <= 1'b1;
                    req_ras_target <= bp_update_pc + 32'd4;
                end else begin
                    req_ras_valid <= (ras_count != 0);
                    req_ras_target <= ras_top_value;
                end
            end

            if (fs_fire) begin
                if (!packet_lane && packet_lane1_valid) begin
                    packet_lane <= 1'b1;
                end else if (prefetch_valid) begin
                    packet_valid <= 1'b1;
                    packet_lane <= 1'b0;
                    packet_lane1_valid <= prefetch_lane1_valid;
                    packet_pc <= prefetch_pc;
                    packet_inst0 <= prefetch_inst0;
                    packet_inst1 <= prefetch_inst1;
                    packet_pred_taken0 <= prefetch_pred_taken0;
                    packet_pred_taken1 <= prefetch_pred_taken1;
                    packet_pred_target0 <= prefetch_pred_target0;
                    packet_pred_target1 <= prefetch_pred_target1;
                    prefetch_valid <= 1'b0;
                end else begin
                    packet_valid <= 1'b0;
                    packet_lane <= 1'b0;
                end
            end

            if (req_valid) begin
                req_valid <= 1'b0;
                if (req_epoch == if_epoch) begin
                    if0_pc <= predicted_packet_next_pc;
                    if (!packet_valid || packet_last_fire) begin
                        packet_valid <= 1'b1;
                        packet_lane <= 1'b0;
                        packet_lane1_valid <= !pred_taken0;
                        packet_pc <= req_pc;
                        packet_inst0 <= inst_in;
                        packet_inst1 <= inst_in1;
                        packet_pred_taken0 <= pred_taken0;
                        packet_pred_taken1 <= pred_taken1;
                        packet_pred_target0 <= pred_target0;
                        packet_pred_target1 <= pred_target1;
                    end else begin
                        prefetch_valid <= 1'b1;
                        prefetch_lane1_valid <= !pred_taken0;
                        prefetch_pc <= req_pc;
                        prefetch_inst0 <= inst_in;
                        prefetch_inst1 <= inst_in1;
                        prefetch_pred_taken0 <= pred_taken0;
                        prefetch_pred_taken1 <= pred_taken1;
                        prefetch_pred_target0 <= pred_target0;
                        prefetch_pred_target1 <= pred_target1;
                    end
                end
            end
        end
    end

    assign fs_to_ds_valid = packet_valid && !redirect_event;
    assign fs_fire = fs_to_ds_valid && ds_allowin;
    assign packet_last_fire = fs_fire &&
                              (packet_lane || !packet_lane1_valid);
    assign fs_to_ds_bus = packet_lane ?
                          {packet_inst1, packet_pc + 32'd4,
                           packet_pred_taken1, packet_pred_target1} :
                          {packet_inst0, packet_pc,
                           packet_pred_taken0, packet_pred_target0};

    assign fs_exc_bus = {7'b0, {`MTVAL_WIDTH{1'b0}}};

endmodule
