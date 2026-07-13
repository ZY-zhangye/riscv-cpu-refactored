module ex_resident_control (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        resident_valid,
    input  logic        resident_kill,
    input  logic        slot_replace,
    input  logic        unit_ready,
    input  logic        unit_busy,
    input  logic        unit_done,
    input  logic [31:0] unit_result,
    output logic        unit_start,
    output logic        resident_ready,
    output logic [31:0] resident_result,
    output logic        resident_killed,
    output logic        resident_started,
    output logic        resident_completed
);

    logic killed_r;
    logic started_r;
    logic completed_r;
    logic [31:0] result_r;

    assign resident_killed = resident_kill || killed_r;
    assign unit_start = resident_valid && unit_ready && !resident_killed &&
                        !started_r && !completed_r;
    assign resident_ready = !resident_valid || resident_killed ||
                            completed_r || unit_done;
    assign resident_result = unit_done ? unit_result : result_r;
    assign resident_started = started_r;
    assign resident_completed = completed_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            killed_r <= 1'b0;
            started_r <= 1'b0;
            completed_r <= 1'b0;
            result_r <= 32'b0;
        end else if (slot_replace) begin
            killed_r <= 1'b0;
            started_r <= 1'b0;
            completed_r <= 1'b0;
            result_r <= 32'b0;
        end else begin
            if (resident_kill) begin
                killed_r <= 1'b1;
            end
            if (unit_start) begin
                started_r <= 1'b1;
            end
            if (unit_done && resident_valid && !resident_killed) begin
                completed_r <= 1'b1;
                result_r <= unit_result;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && unit_start && unit_busy) begin
            $fatal(1, "EX resident attempted to start a busy execution unit");
        end
        if (rst_n && unit_done && resident_valid &&
            !resident_killed && !started_r && !unit_start) begin
            $fatal(1, "execution unit completed without a resident start");
        end
    end
`endif

endmodule
