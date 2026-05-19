`include "my_cpu_defines.svh"

module IO (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clk_uart,

    input  logic        io_sel,
    input  logic        io_re,
    input  logic [3:0]  io_wen,
    input  logic [31:0] io_addr,
    input  logic [31:0] io_wdata,
    output logic [31:0] io_rdata,

    input  logic        uart_rx,
    output logic        uart_tx,
    output logic [31:0] led,
    output logic [`PLIC_NUM_INTERRUPTS-1:0] peripheral_interrupts
);

    localparam logic [1:0] IO_TARGET_NONE  = 2'd0;
    localparam logic [1:0] IO_TARGET_UART  = 2'd1;
    localparam logic [1:0] IO_TARGET_TIMER = 2'd2;
    localparam logic [1:0] IO_TARGET_LED   = 2'd3;
    localparam logic [31:0] UART_BASE  = `MY_CPU_UART_BASE_ADDR;
    localparam logic [31:0] TIMER_BASE = `MY_CPU_TIMER_BASE_ADDR;
    localparam logic [31:0] LEDS_BASE  = `MY_CPU_LEDS_BASE_ADDR;

    logic io_we;
    logic uart_sel;
    logic timer_sel;
    logic led_sel;
    logic uart_re;
    logic uart_we;
    logic timer_re;
    logic timer_we;
    logic [31:0] uart_rdata;
    logic [31:0] timer_rdata;
    logic uart_tx_int;
    logic uart_rx_int;
    logic timer_int;
    logic [1:0] read_target_r;

    assign io_we = io_wen != 4'b0000;
    assign uart_sel = io_sel && (io_addr[31:16] == UART_BASE[31:16]);
    assign timer_sel = io_sel && (io_addr[31:16] == TIMER_BASE[31:16]);
    assign led_sel = io_sel && (io_addr[31:16] == LEDS_BASE[31:16]);

    assign uart_re = uart_sel && io_re;
    assign uart_we = uart_sel && io_we;
    assign timer_re = timer_sel && io_re;
    assign timer_we = timer_sel && io_we;

    UART u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .addr(io_addr[15:0]),
        .wdata(io_wdata),
        .we(uart_we),
        .re(uart_re),
        .rdata(uart_rdata),
        .tx(uart_tx),
        .rx(uart_rx),
        .tx_int(uart_tx_int),
        .rx_int(uart_rx_int)
    );

    timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .addr(io_addr[15:0]),
        .wdata(io_wdata),
        .we(timer_we),
        .re(timer_re),
        .rdata(timer_rdata),
        .timer_int(timer_int)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 32'd0;
            read_target_r <= IO_TARGET_NONE;
        end else begin
            if (led_sel && io_we) begin
                if (io_wen[0]) begin
                    led[7:0] <= io_wdata[7:0];
                end
                if (io_wen[1]) begin
                    led[15:8] <= io_wdata[15:8];
                end
                if (io_wen[2]) begin
                    led[23:16] <= io_wdata[23:16];
                end
                if (io_wen[3]) begin
                    led[31:24] <= io_wdata[31:24];
                end
            end

            if (io_sel && io_re) begin
                unique case (1'b1)
                    uart_sel:  read_target_r <= IO_TARGET_UART;
                    timer_sel: read_target_r <= IO_TARGET_TIMER;
                    led_sel:   read_target_r <= IO_TARGET_LED;
                    default:   read_target_r <= IO_TARGET_NONE;
                endcase
            end else begin
                read_target_r <= IO_TARGET_NONE;
            end
        end
    end

    always_comb begin
        unique case (read_target_r)
            IO_TARGET_UART:  io_rdata = uart_rdata;
            IO_TARGET_TIMER: io_rdata = timer_rdata;
            IO_TARGET_LED:   io_rdata = led;
            default:         io_rdata = 32'd0;
        endcase
    end

    always_comb begin
        peripheral_interrupts = '0;
        peripheral_interrupts[`MY_CPU_TIMER_INT_ID] = timer_int;
        peripheral_interrupts[`MY_CPU_UART_RX_INT_ID] = uart_rx_int;
        peripheral_interrupts[`MY_CPU_UART_TX_INT_ID] = uart_tx_int;
    end

endmodule
