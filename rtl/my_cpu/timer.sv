`include "my_cpu_defines.svh"

module timer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic        re,
    output logic [31:0] rdata,
    output logic        timer_int
);

    logic [31:0] timer_load;
    logic [31:0] timer_value;
    logic [31:0] timer_ctrl;
    logic [31:0] timer_intclr;
    logic [31:0] timer_prescaler;
    logic [31:0] prescaler_count;
    logic periodic_wait_intclr;

    logic timer_enable;
    logic timer_int_enable;
    logic timer_mode;
    logic timer_reload;
    logic timer_prescaler_enable;
    logic prescaler_pulse;
    logic timer_step;
    logic intclr_req;

    assign timer_enable = timer_ctrl[0];
    assign timer_int_enable = timer_ctrl[1];
    assign timer_mode = timer_ctrl[2];              // 0: one-shot, 1: periodic
    assign timer_reload = timer_ctrl[3];            // periodic模式下有效
    assign timer_prescaler_enable = timer_ctrl[4];  // 0: no prescaler, 1: use prescaler
    assign prescaler_pulse = !timer_prescaler_enable || (prescaler_count >= timer_prescaler);
    assign timer_step = timer_enable && prescaler_pulse && !periodic_wait_intclr;
    assign intclr_req = we && (addr == `TIMER_INTCLR) && wdata[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescaler_count <= 32'd0;
        end else if (!timer_enable || !timer_prescaler_enable ||
                     (we && ((addr == `TIMER_CTRL) || (addr == `TIMER_PRESCALER)))) begin
            prescaler_count <= 32'd0;
        end else if (prescaler_count >= timer_prescaler) begin
            prescaler_count <= 32'd0;
        end else begin
            prescaler_count <= prescaler_count + 32'd1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_load <= 32'd0;
            timer_value <= 32'd0;
            timer_ctrl <= 32'd0;
            timer_intclr <= 32'd0;
            timer_prescaler <= 32'd0;
            periodic_wait_intclr <= 1'b0;
            timer_int <= 1'b0;
            rdata <= 32'd0;
        end else begin
            if (re) begin
                unique case (addr)
                    `TIMER_LOAD:      rdata <= timer_load;
                    `TIMER_VALUE:     rdata <= timer_value;
                    `TIMER_CTRL:      rdata <= timer_ctrl;
                    `TIMER_INTCLR:    rdata <= timer_intclr;
                    `TIMER_PRESCALER: rdata <= timer_prescaler;
                    default:          rdata <= 32'd0;
                endcase
            end

            if (we) begin
                unique case (addr)
                    `TIMER_LOAD: begin
                        timer_load <= wdata;
                        timer_value <= wdata;
                        periodic_wait_intclr <= 1'b0;
                    end
                    `TIMER_CTRL: begin
                        timer_ctrl <= wdata;
                        timer_int <= 1'b0;
                        periodic_wait_intclr <= 1'b0;
                    end
                    `TIMER_INTCLR: begin
                        timer_intclr <= wdata;
                        if (wdata[0]) begin
                            timer_int <= 1'b0;
                            if (timer_mode && timer_reload && periodic_wait_intclr) begin
                                timer_value <= timer_load;
                                periodic_wait_intclr <= 1'b0;
                            end
                        end
                    end
                    `TIMER_PRESCALER: begin
                        timer_prescaler <= wdata;
                    end
                    default: begin
                    end
                endcase
            end else if (timer_step) begin
                if (timer_value > 32'd1) begin
                    timer_value <= timer_value - 32'd1;
                end else if (timer_value == 32'd1) begin
                    if (timer_int_enable) begin
                        timer_int <= 1'b1;
                    end

                    if (timer_mode && timer_reload) begin
                        if (timer_int_enable) begin
                            timer_value <= 32'd0;
                            periodic_wait_intclr <= 1'b1;
                        end else begin
                            timer_value <= timer_load;
                        end
                    end else begin
                        timer_value <= 32'd0;
                    end
                end
            end

            if (intclr_req && !(timer_mode && timer_reload && periodic_wait_intclr)) begin
                timer_int <= 1'b0;
            end
        end
    end

endmodule
