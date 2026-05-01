`timescale 1ns/1ps
`include "../rtl/cpu_top/defines.svh"
module tb_uart_benchmark;
    localparam integer CLK_PERIOD_NS = 20;     // 50MHz
    localparam integer UART_BAUD_DIV = 434;    // 50MHz / 115200

    reg clk;
    reg clk_cnt;
    reg rst_n;
    wire [31:0] led;
    wire [39:0] seg;

`ifdef DEBUG_INTERFACE_ENABLE
    wire [31:0] debug_inst_pc;
    wire [31:0] debug_wb_pc;
    wire        debug_wb_rf_wen;
    wire [4:0]  debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata;
    wire [31:0] debug_data;
`endif

    my_cpu u_my_cpu(
        .clk(clk),
        .clk_cnt(clk_cnt),
        .rst_n(rst_n),
`ifdef DEBUG_INTERFACE_ENABLE
        .debug_inst_pc(debug_inst_pc),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),
        .debug_data(debug_data),
`endif
        .led(led),
        .key(8'h00),
        .sw(64'h0),
        .seg(seg)
    );

    // 直接从my_cpu内部UART模块抓取TX串口线
    wire uart_tx = u_my_cpu.u_uart.tx_pin;
    wire uart_tx_valid = u_my_cpu.u_uart.tx_valid;
    wire [7:0] uart_tx_data = u_my_cpu.u_uart.tx_data;

    initial begin
        clk = 1'b0;
        clk_cnt = 1'b0;
        rst_n = 1'b0;

        // 覆盖默认riscv-tests镜像，加载benchmark镜像
        $readmemh("riscv_sim_perf_bench/out/inst.hex", u_my_cpu.u_inst_ram.mem);
        $readmemh("riscv_sim_perf_bench/out/data.hex", u_my_cpu.u_data_ram.mem);

        #200;
        rst_n = 1'b1;
    end

    always #(CLK_PERIOD_NS/2) clk = ~clk;
    always #(CLK_PERIOD_NS/2) clk_cnt = ~clk_cnt;

    // UART输出监视器
    integer sample_cnt;
    integer bit_idx;
    reg receiving;
    reg [7:0] rx_byte;
    reg [39:0] tail;

    initial begin
        sample_cnt = 0;
        bit_idx = 0;
        receiving = 1'b0;
        rx_byte = 8'h00;
        tail = 40'h0;

        $display("[TB] UART benchmark simulation started.");
        $display("[TB] Waiting UART output...");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_cnt <= 0;
            bit_idx <= 0;
            receiving <= 1'b0;
            rx_byte <= 8'h00;
            tail <= 40'h0;
        end else begin
            if (uart_tx_valid) begin
                rx_byte <= uart_tx_data;
                tail <= {tail[31:0], uart_tx_data};
                $write("%c", uart_tx_data);

                // 检测字符串 "Done." 结束标记
                if ({tail[31:0], uart_tx_data} == 40'h446F6E652E) begin
                    $display("\n[TB] Detected benchmark end marker: Done.");
                    #100000;
                    $finish;
                end
            end
        end
    end

    /*initial begin
        // 20ms超时，避免仿真挂死
        #20_000_000;
        $display("\n[TB] Timeout: benchmark did not finish in expected time.");
`ifdef DEBUG_INTERFACE_ENABLE
        $display("[TB] debug_inst_pc=%08h debug_wb_pc=%08h", debug_inst_pc, debug_wb_pc);
`endif
        $finish;
    end*/


endmodule
