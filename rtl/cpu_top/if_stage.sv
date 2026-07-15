`include "defines.svh"

module if_stage (
    input  logic                         clk,
    input  logic                         rst_n,
    // One-cycle synchronous instruction-memory request/response.
    output logic [`ADDR_WIDTH-1:0]       pc_out,
    output logic                         inst_ren,
    input  logic [`DATA_WIDTH-1:0]       inst_in,
    // Decode interface.
    input  logic                         ds_allowin,
    output logic                         fs_to_ds_valid,
    output logic [`FS_DS_WIDTH-1:0]      fs_to_ds_bus,
    // Resolved redirect interface. br_taken is the misprediction redirect.
    input  logic                         br_taken,
    input  logic [`ADDR_WIDTH-1:0]       br_target,
    // Resolved predictor update interface.
    input  logic                         bp_update_valid,
    input  logic [`ADDR_WIDTH-1:0]       bp_update_pc,
    input  logic                         bp_update_taken,
    input  logic [`ADDR_WIDTH-1:0]       bp_update_target,
    input  logic                         bp_update_is_jalr,
    // Exception metadata and redirect.
    output logic [`EXC_WIDTH-1:0]        fs_exc_bus,
    input  logic                         exception_flag,
    input  logic [`ADDR_WIDTH-1:0]       exception_addr
);

    localparam integer BP_INDEX_WIDTH = 7;
    localparam integer BP_ENTRIES = 1 << BP_INDEX_WIDTH;
    localparam integer BP_TAG_WIDTH = `ADDR_WIDTH - BP_INDEX_WIDTH - 2;
    localparam integer BP_ENTRY_WIDTH = BP_TAG_WIDTH + 2 + `ADDR_WIDTH;

    logic if_active;
    logic req_valid;
    logic [`ADDR_WIDTH-1:0] req_pc;

    logic redirect_pending;
    logic [`ADDR_WIDTH-1:0] redirect_pc_r;
    logic redirect_now;

    logic response_fire;
    logic request_fire;
    logic [`ADDR_WIDTH-1:0] request_pc;
    logic [`ADDR_WIDTH-1:0] predicted_next_pc;

    logic [BP_ENTRIES-1:0] bp_valid_lookup;
    logic [BP_ENTRIES-1:0] bp_valid_update;

    // The payload arrays are intentionally not reset. Validity is held in the
    // separately reset bitmaps so Vivado can infer distributed RAM.
    (* ram_style = "distributed" *)
    logic [BP_ENTRY_WIDTH-1:0] bp_lookup_mem [0:BP_ENTRIES-1];
    (* ram_style = "distributed" *)
    logic [BP_ENTRY_WIDTH-1:0] bp_update_mem [0:BP_ENTRIES-1];

    logic bp_q_valid;
    logic [BP_ENTRY_WIDTH-1:0] bp_q_entry;
    logic [BP_TAG_WIDTH-1:0] bp_q_tag;
    logic [1:0] bp_q_counter;
    logic [`ADDR_WIDTH-1:0] bp_q_target;
    logic bp_hit;
    logic bp_pred_taken;
    logic [`ADDR_WIDTH-1:0] bp_pred_target;

    logic bp_update_valid_r;
    logic [`ADDR_WIDTH-1:0] bp_update_pc_r;
    logic bp_update_taken_r;
    logic [`ADDR_WIDTH-1:0] bp_update_target_r;
    logic [BP_INDEX_WIDTH-1:0] bp_update_index;
    logic [BP_TAG_WIDTH-1:0] bp_update_tag;
    logic [BP_ENTRY_WIDTH-1:0] bp_update_entry;
    logic [BP_TAG_WIDTH-1:0] bp_update_entry_tag;
    logic [1:0] bp_update_entry_counter;
    logic bp_update_tag_match;
    logic [1:0] bp_update_counter_next;
    logic [BP_ENTRY_WIDTH-1:0] bp_update_entry_next;

    logic [BP_INDEX_WIDTH-1:0] bp_request_index;
    logic bp_lookup_update_collision;

    function automatic logic [1:0] bp_counter_update(
        input logic [1:0] current,
        input logic       taken
    );
        begin
            if (taken) begin
                bp_counter_update = (current == 2'b11) ?
                                    current : current + 1'b1;
            end else begin
                bp_counter_update = (current == 2'b00) ?
                                    current : current - 1'b1;
            end
        end
    endfunction

    assign redirect_now = exception_flag || br_taken;

    assign {bp_q_tag, bp_q_counter, bp_q_target} = bp_q_entry;
    assign bp_hit = bp_q_valid &&
                    (bp_q_tag == req_pc[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2]);
    assign bp_pred_taken = bp_hit && bp_q_counter[1];
    assign bp_pred_target = bp_hit ? bp_q_target : '0;
    assign predicted_next_pc = bp_pred_taken ? bp_q_target : req_pc + 32'd4;

    // A response may be replaced by its successor on the same edge. When
    // Decode stalls, no new request is launched and both IROM and BTB outputs
    // remain aligned with req_pc.
    assign response_fire = req_valid && ds_allowin && !redirect_now;
    assign request_fire = rst_n && if_active && !redirect_now &&
                          (!req_valid || response_fire);
    assign request_pc = redirect_pending ? redirect_pc_r :
                        req_valid ? predicted_next_pc : `PC_START;

    assign pc_out = request_pc;
    assign inst_ren = request_fire;
    assign fs_to_ds_valid = req_valid && !redirect_now;
    assign fs_to_ds_bus = {inst_in, req_pc, bp_pred_taken, bp_pred_target};

    // The redirect itself kills the current response immediately. Its target
    // is registered independently of Decode backpressure and requested on the
    // following cycle, cutting the EX-to-IROM address path.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            if_active <= 1'b0;
            req_valid <= 1'b0;
            req_pc <= '0;
            redirect_pending <= 1'b0;
            redirect_pc_r <= '0;
        end else begin
            if_active <= 1'b1;

            if (exception_flag) begin
                redirect_pending <= 1'b1;
                redirect_pc_r <= exception_addr;
            end else if (br_taken) begin
                redirect_pending <= 1'b1;
                redirect_pc_r <= br_target;
            end else if (request_fire && redirect_pending) begin
                redirect_pending <= 1'b0;
            end

            if (redirect_now) begin
                req_valid <= 1'b0;
            end else if (request_fire) begin
                req_valid <= 1'b1;
                req_pc <= request_pc;
            end else if (response_fire) begin
                req_valid <= 1'b0;
            end
        end
    end

    // Register predictor training at the IF boundary. This keeps the resolved
    // EX result off the table write path while preserving one update per cycle.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bp_update_valid_r <= 1'b0;
            bp_update_pc_r <= '0;
            bp_update_taken_r <= 1'b0;
            bp_update_target_r <= '0;
        end else begin
            bp_update_valid_r <= bp_update_valid && !bp_update_is_jalr;
            if (bp_update_valid && !bp_update_is_jalr) begin
                bp_update_pc_r <= bp_update_pc;
                bp_update_taken_r <= bp_update_taken;
                bp_update_target_r <= bp_update_target;
            end
        end
    end

    assign bp_update_index =
        bp_update_pc_r[BP_INDEX_WIDTH+1:2];
    assign bp_update_tag =
        bp_update_pc_r[`ADDR_WIDTH-1:BP_INDEX_WIDTH+2];
    assign bp_update_entry = bp_update_mem[bp_update_index];
    assign {bp_update_entry_tag, bp_update_entry_counter} =
        bp_update_entry[BP_ENTRY_WIDTH-1 -: BP_TAG_WIDTH+2];
    assign bp_update_tag_match = bp_valid_update[bp_update_index] &&
                                 (bp_update_entry_tag == bp_update_tag);
    assign bp_update_counter_next = bp_update_tag_match ?
        bp_counter_update(bp_update_entry_counter, bp_update_taken_r) :
        (bp_update_taken_r ? 2'b10 : 2'b01);
    assign bp_update_entry_next = {
        bp_update_tag,
        bp_update_counter_next,
        bp_update_target_r
    };

    assign bp_request_index = request_pc[BP_INDEX_WIDTH+1:2];
    assign bp_lookup_update_collision = bp_update_valid_r && request_fire &&
                                        (bp_update_index == bp_request_index);

    // Only validity state is reset. The query table and update shadow are
    // written together so back-to-back updates observe the newest counter.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bp_valid_lookup <= '0;
            bp_valid_update <= '0;
        end else if (bp_update_valid_r) begin
            bp_valid_lookup[bp_update_index] <= 1'b1;
            bp_valid_update[bp_update_index] <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin : bp_lookup_ram
        if (rst_n && bp_update_valid_r) begin
            bp_lookup_mem[bp_update_index] <= bp_update_entry_next;
        end

        if (!rst_n) begin
            bp_q_valid <= 1'b0;
            bp_q_entry <= '0;
        end else if (request_fire) begin
            if (bp_lookup_update_collision) begin
                bp_q_valid <= 1'b1;
                bp_q_entry <= bp_update_entry_next;
            end else begin
                bp_q_valid <= bp_valid_lookup[bp_request_index];
                bp_q_entry <= bp_lookup_mem[bp_request_index];
            end
        end else if (redirect_now) begin
            bp_q_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin : bp_update_shadow
        if (rst_n && bp_update_valid_r) begin
            bp_update_mem[bp_update_index] <= bp_update_entry_next;
        end
    end

    assign fs_exc_bus = {`EXC_WIDTH{1'b0}};

endmodule
