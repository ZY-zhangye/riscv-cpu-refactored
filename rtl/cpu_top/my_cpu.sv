`include "defines.svh"

module my_cpu (
    input  logic clk,
    input  logic clk_cnt,
    input  logic rst_n,
    output logic [31:0] led,
    input  logic [7:0] key,
    input  logic [63:0] sw,
    output logic [39:0] seg
    `ifdef DEBUG_INTERFACE_ENABLE
    ,
    output logic [31:0] debug_inst_pc,
    output logic [31:0] debug_wb_pc,
    output logic debug_wb_rf_wen,
    output logic [4:0] debug_wb_rf_wnum,
    output logic [31:0] debug_wb_rf_wdata,
    output logic [31:0] debug_data
    `endif
);

    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic imem_en;

    logic [31:0] cpu_dmem_rdata;
    logic [31:0] ram_rdata;
    logic [31:0] uart_rdata;
    logic [31:0] mmio_rdata;
    logic [31:0] dmem_addr;
    logic [3:0] dmem_wen;
    logic dmem_en;
    logic [31:0] dmem_wdata;

    logic ram_sel;
    logic bench_ram_sel;
    logic official_dram_sel;
    logic uart_sel;
    logic led_sel;
    logic seg_sel;
    logic sw_low_sel;
    logic sw_high_sel;
    logic key_sel;
    logic cnt_sel;
    logic ram_we;
    logic uart_we;
    logic uart_re;

    logic [31:0] cnt_reg;
    localparam logic [31:0] UART_BASE = `UART_BASE_ADDR;

    `ifdef DEBUG_EN
    logic [31:0] cpu_debug_wb_pc;
    logic [4:0] cpu_debug_wb_rf_addr;
    logic [31:0] cpu_debug_wb_rf_data;
    logic cpu_debug_wb_rf_wen;
    logic [31:0] cpu_debug_data;
    `endif

    assign bench_ram_sel = dmem_en && (dmem_addr[31:28] == 4'h6);
    assign official_dram_sel = dmem_en && (dmem_addr >= 32'h8010_0000) && (dmem_addr <= 32'h8013_FFFF);
    assign ram_sel = bench_ram_sel || official_dram_sel;
    assign uart_sel = dmem_en && (dmem_addr[31:4] == UART_BASE[31:4]);
    assign led_sel = dmem_en && (dmem_addr == `LED_ADDR);
    assign seg_sel = dmem_en && (dmem_addr == `SEG_ADDR);
    assign sw_low_sel = dmem_en && (dmem_addr == `SW_LOW_ADDR);
    assign sw_high_sel = dmem_en && (dmem_addr == `SW_HIGH_ADDR);
    assign key_sel = dmem_en && (dmem_addr == `KEY_ADDR);
    assign cnt_sel = dmem_en && (dmem_addr == `CNT_ADDR);
    assign ram_we = ram_sel && (dmem_wen != 4'b0000);
    assign uart_we = uart_sel && (dmem_wen != 4'b0000);
    assign uart_re = uart_sel && (dmem_wen == 4'b0000);

    cpu_top u_cpu_top (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(cpu_dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(cpu_debug_wb_pc),
        .debug_wb_rf_addr(cpu_debug_wb_rf_addr),
        .debug_wb_rf_data(cpu_debug_wb_rf_data),
        .debug_wb_rf_wen(cpu_debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(),
        .debug_data(cpu_debug_data)
        `endif
    );

    simple_inst_ram u_inst_ram (
        .clk(clk),
        .addr(imem_addr),
        .en(imem_en),
        .rdata(imem_rdata)
    );

    simple_data_ram u_data_ram (
        .clk(clk),
        .addr(dmem_addr),
        .wen(ram_we ? dmem_wen : 4'b0000),
        .wdata(dmem_wdata),
        .rdata(ram_rdata)
    );

    uart_minimal u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .addr(dmem_addr),
        .wdata(dmem_wdata),
        .wen(uart_we),
        .ren(uart_re),
        .rdata(uart_rdata),
        .rx_pin(1'b1),
        .tx_pin()
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 32'b0;
            seg <= 40'b0;
            cnt_reg <= 32'b0;
        end else begin
            cnt_reg <= cnt_reg + 32'b1;
            if (led_sel && dmem_wen != 4'b0000) begin
                led <= dmem_wdata;
            end
            if (seg_sel && dmem_wen != 4'b0000) begin
                seg <= {8'b0, dmem_wdata};
            end
        end
    end

    always_comb begin
        unique case (1'b1)
            uart_sel: mmio_rdata = uart_rdata;
            led_sel: mmio_rdata = led;
            seg_sel: mmio_rdata = {24'b0, seg[7:0]};
            sw_low_sel: mmio_rdata = sw[31:0];
            sw_high_sel: mmio_rdata = sw[63:32];
            key_sel: mmio_rdata = {24'b0, key};
            cnt_sel: mmio_rdata = cnt_reg;
            default: mmio_rdata = 32'b0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_dmem_rdata <= 32'b0;
        end else if (dmem_en) begin
            cpu_dmem_rdata <= ram_sel ? ram_rdata : mmio_rdata;
        end
    end

    `ifdef DEBUG_INTERFACE_ENABLE
    assign debug_inst_pc = imem_addr;
    assign debug_wb_pc = cpu_debug_wb_pc;
    assign debug_wb_rf_wen = cpu_debug_wb_rf_wen;
    assign debug_wb_rf_wnum = cpu_debug_wb_rf_addr;
    assign debug_wb_rf_wdata = cpu_debug_wb_rf_data;
    assign debug_data = cpu_debug_data;
    `endif

    // clk_cnt is kept for board-level compatibility.
    logic unused_clk_cnt;
    assign unused_clk_cnt = clk_cnt;

endmodule

module simple_inst_ram (
    input  logic clk,
    input  logic [31:0] addr,
    input  logic en,
    output logic [31:0] rdata
);
    logic [31:0] mem [0:1023];

    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr[11:2]];
        end
    end
endmodule

module simple_data_ram (
    input  logic clk,
    input  logic [31:0] addr,
    input  logic [3:0] wen,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    logic [31:0] mem [0:1023];

    assign rdata = mem[addr[11:2]];

    always_ff @(posedge clk) begin
        if (wen[0]) begin
            mem[addr[11:2]][7:0] <= wdata[7:0];
        end
        if (wen[1]) begin
            mem[addr[11:2]][15:8] <= wdata[15:8];
        end
        if (wen[2]) begin
            mem[addr[11:2]][23:16] <= wdata[23:16];
        end
        if (wen[3]) begin
            mem[addr[11:2]][31:24] <= wdata[31:24];
        end
    end
endmodule

module uart_minimal (
    input  logic clk,
    input  logic rst_n,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic wen,
    input  logic ren,
    output logic [31:0] rdata,
    input  logic rx_pin,
    output logic tx_pin
);
    logic [4:0] ctrl;
    logic [15:0] baud_div;
    logic [15:0] baud_cnt;
    logic [9:0] tx_shift;
    logic [3:0] tx_bit_cnt;
    logic [7:0] rx_data;
    logic tx_busy;
    logic tx_empty;
    logic rx_ready;
    logic tx_int;
    logic rx_int;
    logic baud_tick;
    logic tx_valid;
    logic [7:0] tx_data;

    assign baud_tick = (baud_cnt == 16'b0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl <= 5'b0_0001;
            baud_div <= 16'd434;
            baud_cnt <= 16'd434;
            tx_shift <= 10'h3ff;
            tx_bit_cnt <= 4'b0;
            rx_data <= 8'b0;
            tx_busy <= 1'b0;
            tx_empty <= 1'b1;
            rx_ready <= 1'b0;
            tx_int <= 1'b0;
            rx_int <= 1'b0;
            tx_pin <= 1'b1;
            tx_valid <= 1'b0;
            tx_data <= 8'b0;
        end else begin
            tx_valid <= 1'b0;
            if (baud_cnt == 16'b0) begin
                baud_cnt <= (baud_div == 16'b0) ? 16'd1 : baud_div;
            end else begin
                baud_cnt <= baud_cnt - 16'b1;
            end

            if (tx_busy && baud_tick) begin
                tx_pin <= tx_shift[0];
                tx_shift <= {1'b1, tx_shift[9:1]};
                if (tx_bit_cnt == 4'd9) begin
                    tx_busy <= 1'b0;
                    tx_empty <= 1'b1;
                    tx_bit_cnt <= 4'b0;
                    tx_int <= ctrl[1];
                end else begin
                    tx_bit_cnt <= tx_bit_cnt + 4'b1;
                end
            end

            if (wen) begin
                unique case (addr[3:2])
                    2'b00: begin
                        if (ctrl[0] && tx_empty) begin
                            tx_valid <= 1'b1;
                            tx_data <= wdata[7:0];
                            `ifdef PERF_BENCH
                            tx_pin <= 1'b1;
                            tx_busy <= 1'b0;
                            tx_empty <= 1'b1;
                            tx_int <= ctrl[1];
                            `else
                            tx_shift <= {1'b1, wdata[7:0], 1'b0};
                            tx_bit_cnt <= 4'b0;
                            tx_busy <= 1'b1;
                            tx_empty <= 1'b0;
                            tx_int <= 1'b0;
                            `endif
                        end
                    end
                    2'b10: begin
                        ctrl <= wdata[4:0] & 5'b0_0111;
                        if (wdata[3]) begin
                            tx_int <= 1'b0;
                        end
                        if (wdata[4]) begin
                            rx_int <= 1'b0;
                        end
                    end
                    2'b11: begin
                        baud_div <= wdata[15:0];
                    end
                    default: begin
                    end
                endcase
            end

            if (ren && addr[3:2] == 2'b00) begin
                rx_ready <= 1'b0;
                rx_int <= 1'b0;
            end
        end
    end

    always_comb begin
        unique case (addr[3:2])
            2'b00: rdata = {24'b0, rx_data};
            2'b01: rdata = {26'b0, rx_int, tx_int, 1'b0, 1'b0, !tx_empty, rx_ready, tx_empty};
            2'b10: rdata = {27'b0, ctrl};
            2'b11: rdata = {16'b0, baud_div};
            default: rdata = 32'b0;
        endcase
    end

    logic unused_rx_pin;
    assign unused_rx_pin = rx_pin;
endmodule
