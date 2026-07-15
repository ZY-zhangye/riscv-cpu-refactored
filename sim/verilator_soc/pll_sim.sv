`timescale 1ps / 1ps

module pll (
    input  logic clk_in1_p,
    input  logic clk_in1_n,
    output logic clk_out1,
    output logic clk_out2,
    output logic locked
);

    integer lock_edges;
    integer cpu_half_index;

    initial begin
        clk_out1 = 1'b0;
        clk_out2 = 1'b0;
        locked = 1'b0;
        lock_edges = 0;
        cpu_half_index = 0;
    end

    // Board PLL outputs: 50 MHz peripheral/counter clock.
    always begin
        #10000;
        clk_out1 = ~clk_out1;
    end

    // 175 MHz CPU clock. Six 2857 ps half-cycles plus one 2858 ps
    // half-cycle average exactly 20 ns over seven half-cycles.
    always begin
        if (cpu_half_index == 6) begin
            #2858;
            cpu_half_index = 0;
        end else begin
            #2857;
            cpu_half_index = cpu_half_index + 1;
        end
        clk_out2 = ~clk_out2;
    end

    always @(posedge clk_in1_p) begin
        #1;
        if (clk_in1_n !== 1'b0) begin
            $fatal(1, "differential input clocks are not complementary");
        end
        if (!locked) begin
            if (lock_edges == 15) begin
                locked <= 1'b1;
            end else begin
                lock_edges <= lock_edges + 1;
            end
        end
    end

endmodule
