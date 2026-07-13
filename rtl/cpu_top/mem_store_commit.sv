module mem_store_commit (
    input  logic        resident_valid,
    input  logic        commit_ready,
    input  logic        resident_kill,
    input  logic        resident_exception,
    input  logic        is_store,
    input  logic [31:0] address,
    input  logic [31:0] write_data,
    input  logic [3:0]  write_enable,
    output logic        commit_valid,
    output logic [31:0] commit_address,
    output logic [31:0] commit_write_data,
    output logic [3:0]  commit_write_enable
);

    assign commit_valid = resident_valid && commit_ready &&
                          !resident_kill && !resident_exception &&
                          is_store && (write_enable != 4'b0000);
    assign commit_address = address;
    assign commit_write_data = write_data;
    assign commit_write_enable = commit_valid ? write_enable : 4'b0000;

`ifndef SYNTHESIS
    always_comb begin
        if (commit_valid &&
            (!resident_valid || !commit_ready || resident_kill ||
             resident_exception || !is_store)) begin
            $fatal(1, "invalid Store escaped the MEM commit gate");
        end
    end
`endif

endmodule
