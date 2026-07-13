module lsu_exec_unit (
    input  logic        start,
    input  logic        kill,
    input  logic [31:0] base,
    input  logic [31:0] store_data,
    input  logic [31:0] immediate,
    input  logic [4:0]  mem_op,
    input  logic        is_store,
    output logic        busy,
    output logic        done,
    output logic        request_valid,
    output logic [31:0] address,
    output logic [31:0] write_data,
    output logic [3:0]  write_enable,
    output logic [5:0]  load_metadata
);

    logic inst_lb;
    logic inst_lh;
    logic inst_lw;
    logic inst_lbu;
    logic inst_lhu;
    logic inst_sb;
    logic inst_sh;
    logic inst_sw;

    assign inst_lb  = mem_op[4] && !is_store;
    assign inst_lh  = mem_op[3] && !is_store;
    assign inst_lw  = mem_op[2] && !is_store;
    assign inst_lbu = mem_op[1] && !is_store;
    assign inst_lhu = mem_op[0] && !is_store;
    assign inst_sb  = mem_op[4] && is_store;
    assign inst_sh  = mem_op[3] && is_store;
    assign inst_sw  = mem_op[2] && is_store;

    assign busy = 1'b0;
    assign done = start && !kill;
    assign request_valid = done && (|mem_op);
    assign address = base + immediate;
    assign write_data = inst_sb ? {4{store_data[7:0]}} :
                        inst_sh ? {2{store_data[15:0]}} :
                                  store_data;

    always_comb begin
        write_enable = 4'b0000;
        if (request_valid && is_store) begin
            if (inst_sb) begin
                write_enable = 4'b0001 << address[1:0];
            end else if (inst_sh) begin
                write_enable = address[1] ? 4'b1100 : 4'b0011;
            end else if (inst_sw) begin
                write_enable = 4'b1111;
            end
        end
    end

    assign load_metadata = {
        inst_lb || inst_sb,
        inst_lh || inst_sh,
        inst_lw || inst_sw,
        inst_lbu,
        inst_lhu,
        is_store
    };

endmodule
