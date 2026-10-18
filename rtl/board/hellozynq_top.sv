`timescale 1ns / 1ps
`include "defines.svh"

// HelloZynq's verified common interface: 50 MHz PL oscillator and Bank 34 UART.
// The -2 part used by the build is a tutorial candidate, not a readback of the
// fitted device's speed/temperature grade. Keep the CPU and peripheral RTL intact.
module hellozynq_top #(
    parameter integer CPU_HZ = 50000000,
    parameter INST_INIT_FILE = "inst.mem",
    parameter DATA_INIT_FILE = "data.mem",
    parameter integer MMCM_DIVCLK = 1,
    parameter real MMCM_MULT = 20.0,
    parameter real MMCM_OUT_DIV = 20.0,
    parameter integer RESET_HOLD_CYCLES = 1024
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [1:0] led
);
    wire board_clk;
    wire cpu_clk_unbuffered;
    wire cpu_clk;
    wire feedback_unbuffered;
    wire feedback;
    wire mmcm_locked;

    IBUF u_board_clock_input (.I(clk), .O(board_clk));
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.0),
        .DIVCLK_DIVIDE(MMCM_DIVCLK),
        .CLKFBOUT_MULT_F(MMCM_MULT),
        .CLKOUT0_DIVIDE_F(MMCM_OUT_DIV),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(board_clk),
        .CLKFBIN(feedback),
        .RST(~rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(feedback_unbuffered),
        .CLKOUT0(cpu_clk_unbuffered),
        .LOCKED(mmcm_locked),
        .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );
    BUFG u_feedback_buffer (.I(feedback_unbuffered), .O(feedback));
    BUFG u_cpu_clock_buffer (.I(cpu_clk_unbuffered), .O(cpu_clk));

    // Assert immediately on the external button or loss of lock. Configuration
    // initial values also hold the CPU in reset before the first clock edge.
    wire asynchronous_reset_n = rst_n & mmcm_locked;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [2:0] release_pipe = 3'b000;
    localparam integer RESET_COUNT_WIDTH = (RESET_HOLD_CYCLES < 2) ? 1 :
                                           $clog2(RESET_HOLD_CYCLES + 1);
    reg [RESET_COUNT_WIDTH-1:0] reset_count = '0;
    reg cpu_reset_n = 1'b0;
    always @(posedge cpu_clk or negedge asynchronous_reset_n) begin
        if (!asynchronous_reset_n) begin
            release_pipe <= 3'b000;
            reset_count <= '0;
            cpu_reset_n <= 1'b0;
        end else begin
            release_pipe <= {release_pipe[1:0], 1'b1};
            if (!release_pipe[2]) begin
                reset_count <= '0;
                cpu_reset_n <= 1'b0;
            end else if (RESET_HOLD_CYCLES == 0) begin
                cpu_reset_n <= 1'b1;
            end else if (reset_count < RESET_HOLD_CYCLES) begin
                reset_count <= reset_count + 1'b1;
                cpu_reset_n <= 1'b0;
            end else begin
                cpu_reset_n <= 1'b1;
            end
        end
    end

    wire [31:0] soc_led;
    my_cpu #(
        .BOARD_MEMORY(1),
        .INST_INIT_FILE(INST_INIT_FILE),
        .DATA_INIT_FILE(DATA_INIT_FILE)
    ) u_soc (
        .clk(cpu_clk),
        .rst_n(cpu_reset_n),
        // Firmware selects the UART's divider driven by the exact CPU_HZ.
        .clk_uart(1'b0),
        .uart_rx(uart_rx),
        .external_interrupts(32'b0),
        .uart_tx(uart_tx),
        .led(soc_led),
        .plic_irq()
`ifdef DEBUG_EN
        ,
        .debug_inst_pc(),
        .debug_wb_pc(),
        .debug_wb_rf_addr(),
        .debug_wb_rf_data(),
        .debug_wb_rf_wen(),
        .debug_wb_fpu_rf_wen(),
        .debug_data()
`endif
    );
    assign led = soc_led[1:0];
endmodule
