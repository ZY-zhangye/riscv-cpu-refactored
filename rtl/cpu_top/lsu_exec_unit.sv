module lsu_exec_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        kill,
    input  logic        response_valid,
    input  logic [31:0] response_data,
    input  logic [31:0] base,
    input  logic [31:0] store_data,
    input  logic [31:0] immediate,
    input  logic [4:0]  mem_op,
    input  logic        is_store,
    output logic        busy,
    output logic        done,
    output logic        load_request_valid,
    output logic [31:0] address,
    output logic [31:0] write_data,
    output logic [3:0]  write_enable,
    output logic [5:0]  load_metadata,
    output logic [31:0] load_response_data,
    output logic        misaligned
);

    logic [31:0] address_live;
    logic [31:0] write_data_live;
    logic [3:0] write_enable_live;
    logic [5:0] load_metadata_live;
    logic misaligned_live;
    logic inst_lb;
    logic inst_lh;
    logic inst_lw;
    logic inst_lbu;
    logic inst_lhu;
    logic inst_sb;
    logic inst_sh;
    logic inst_sw;

    logic [31:0] address_r;
    logic [31:0] write_data_r;
    logic [3:0] write_enable_r;
    logic [5:0] load_metadata_r;
    logic [31:0] response_data_r;
    logic misaligned_r;
    logic load_active_r;
    logic done_r;

    assign inst_lb  = mem_op[4] && !is_store;
    assign inst_lh  = mem_op[3] && !is_store;
    assign inst_lw  = mem_op[2] && !is_store;
    assign inst_lbu = mem_op[1] && !is_store;
    assign inst_lhu = mem_op[0] && !is_store;
    assign inst_sb  = mem_op[4] && is_store;
    assign inst_sh  = mem_op[3] && is_store;
    assign inst_sw  = mem_op[2] && is_store;

    assign address_live = base + immediate;
    assign write_data_live = inst_sb ? {4{store_data[7:0]}} :
                             inst_sh ? {2{store_data[15:0]}} :
                                       store_data;

    always_comb begin
        write_enable_live = 4'b0000;
        if (is_store) begin
            if (inst_sb) begin
                write_enable_live = 4'b0001 << address_live[1:0];
            end else if (inst_sh) begin
                write_enable_live = address_live[1] ? 4'b1100 : 4'b0011;
            end else if (inst_sw) begin
                write_enable_live = 4'b1111;
            end
        end
    end

    assign load_metadata_live = {
        inst_lb || inst_sb,
        inst_lh || inst_sh,
        inst_lw || inst_sw,
        inst_lbu,
        inst_lhu,
        is_store
    };

    assign misaligned_live = (inst_lw || inst_sw) ? (address_live[1:0] != 2'b00) :
                             (inst_lh || inst_lhu || inst_sh) ? address_live[0] :
                             1'b0;

    assign load_request_valid = start && !kill && !is_store &&
                                (|mem_op) && !misaligned_live;
    assign address = start ? address_live : address_r;
    assign write_data = start ? write_data_live : write_data_r;
    assign write_enable = kill ? 4'b0000 :
                          (start ? write_enable_live : write_enable_r);
    assign load_metadata = start ? load_metadata_live : load_metadata_r;
    assign load_response_data = response_data_r;
    assign misaligned = start ? misaligned_live : misaligned_r;
    assign done = done_r && !kill;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            address_r <= 32'b0;
            write_data_r <= 32'b0;
            write_enable_r <= 4'b0;
            load_metadata_r <= 6'b0;
            response_data_r <= 32'b0;
            misaligned_r <= 1'b0;
            load_active_r <= 1'b0;
            busy <= 1'b0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (kill) begin
                load_active_r <= 1'b0;
                busy <= 1'b0;
            end else if (start && !busy) begin
                address_r <= address_live;
                write_data_r <= write_data_live;
                write_enable_r <= write_enable_live;
                load_metadata_r <= load_metadata_live;
                misaligned_r <= misaligned_live;
                if (is_store || misaligned_live || !(|mem_op)) begin
                    load_active_r <= 1'b0;
                    busy <= 1'b0;
                    done_r <= 1'b1;
                end else begin
                    load_active_r <= 1'b1;
                    busy <= 1'b1;
                end
            end else if (busy && load_active_r && response_valid) begin
                response_data_r <= response_data;
                load_active_r <= 1'b0;
                busy <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && start && busy) begin
            $fatal(1, "LSU received a duplicate start while busy");
        end
        if (rst_n && load_request_valid &&
            (kill || is_store || misaligned_live)) begin
            $fatal(1, "invalid LSU load request escaped E0 checks");
        end
    end
`endif

endmodule
