`include "my_cpu_defines.svh"

module UART (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clk_uart,
    input  logic [15:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic        re,
    output logic [31:0] rdata,
    output logic        tx,
    input  logic        rx,
    output logic        tx_int,
    output logic        rx_int
);

    localparam logic [3:0] FIFO_DEPTH = 4'd8;

    localparam logic [1:0] TX_IDLE  = 2'd0;
    localparam logic [1:0] TX_START = 2'd1;
    localparam logic [1:0] TX_DATA  = 2'd2;
    localparam logic [1:0] TX_STOP  = 2'd3;

    localparam logic [1:0] RX_IDLE  = 2'd0;
    localparam logic [1:0] RX_START = 2'd1;
    localparam logic [1:0] RX_DATA  = 2'd2;
    localparam logic [1:0] RX_STOP  = 2'd3;

    logic [31:0] uart_data;
    logic [31:0] uart_status;
    logic [31:0] uart_ctrl;
    logic [31:0] uart_baud;

    logic tx_empty;
    logic rx_ready;
    logic tx_full;
    logic rx_full;
    logic parity_error;
    logic overflow_error;

    logic rx_int_en;
    logic tx_int_en;
    logic uart_en;
    logic uart_rst;
    logic boundary_on;

    logic [31:0] baud_cnt;
    logic [31:0] rx_baud_cnt;
    logic baud_tick;
    logic rx_baud_tick;

    logic clk_uart_sync0;
    logic clk_uart_sync1;
    logic clk_uart_sync2;
    logic rx_sync0;
    logic rx_sync1;
    logic rx_sync2;

    logic [7:0] tx_buffer [0:7];
    logic [7:0] rx_buffer [0:7];
    logic [2:0] tx_head;
    logic [2:0] tx_tail;
    logic [2:0] rx_head;
    logic [2:0] rx_tail;
    logic [3:0] tx_count;
    logic [3:0] rx_count;

    logic [1:0] tx_state;
    logic [1:0] rx_state;
    logic [2:0] tx_bit_idx;
    logic [2:0] rx_bit_idx;
    logic [7:0] tx_shift;
    logic [7:0] rx_shift;

    logic clk_uart_tick;
    logic tx_tick;
    logic rx_tick;
    logic rx_falling;

    logic write_data_req;
    logic write_status_req;
    logic write_ctrl_req;
    logic write_baud_req;
    logic read_data_req;
    logic soft_reset_req;
    logic tx_push;
    logic tx_pop;
    logic rx_pop;
    logic rx_push;

    assign parity_error = 1'b0;
    assign {boundary_on, uart_rst, uart_en, tx_int_en, rx_int_en} = uart_ctrl[4:0];
    assign uart_status = {24'b0, rx_int, tx_int, overflow_error, parity_error,
                          rx_full, tx_full, rx_ready, tx_empty};

    assign baud_tick = boundary_on && uart_en && (baud_cnt >= uart_baud);
    assign rx_baud_tick = boundary_on && uart_en && (rx_baud_cnt >= uart_baud);
    assign clk_uart_tick = clk_uart_sync1 && !clk_uart_sync2;
    assign tx_tick = boundary_on ? baud_tick : (clk_uart_tick && uart_en);
    assign rx_tick = boundary_on ? rx_baud_tick : (clk_uart_tick && uart_en);
    assign rx_falling = rx_sync2 && !rx_sync1;

    assign write_data_req = we && (addr == `UART_RT_DATA);
    assign write_status_req = we && (addr == `UART_RT_STATUS);
    assign write_ctrl_req = we && (addr == `UART_RT_CTRL);
    assign write_baud_req = we && (addr == `UART_RT_BAUD);
    assign read_data_req = re && (addr == `UART_RT_DATA);
    assign soft_reset_req = write_ctrl_req && wdata[3];

    assign tx_push = uart_en && write_data_req && (tx_count < FIFO_DEPTH);
    assign tx_pop = uart_en && tx_tick && (tx_state == TX_IDLE) && (tx_count != 0);
    assign rx_pop = uart_en && read_data_req && (rx_count != 0);
    assign rx_push = uart_en && rx_tick && (rx_state == RX_STOP) && rx_sync1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 32'd0;
            clk_uart_sync0 <= 1'b0;
            clk_uart_sync1 <= 1'b0;
            clk_uart_sync2 <= 1'b0;
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            clk_uart_sync0 <= clk_uart;
            clk_uart_sync1 <= clk_uart_sync0;
            clk_uart_sync2 <= clk_uart_sync1;

            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
            rx_sync2 <= rx_sync1;

            if (!uart_en || !boundary_on || soft_reset_req) begin
                baud_cnt <= 32'd0;
            end else if (baud_cnt >= uart_baud) begin
                baud_cnt <= 32'd0;
            end else begin
                baud_cnt <= baud_cnt + 32'd1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_baud_cnt <= 32'd0;
        end else if (!uart_en || !boundary_on || soft_reset_req) begin
            rx_baud_cnt <= 32'd0;
        end else if ((rx_state == RX_IDLE) && rx_falling) begin
            rx_baud_cnt <= (uart_baud >> 1);
        end else if (rx_state == RX_IDLE) begin
            rx_baud_cnt <= 32'd0;
        end else if (rx_baud_cnt >= uart_baud) begin
            rx_baud_cnt <= 32'd0;
        end else begin
            rx_baud_cnt <= rx_baud_cnt + 32'd1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_data <= 32'd0;
            uart_ctrl <= 32'd0;
            uart_baud <= 32'd868;
            rdata <= 32'd0;
            tx <= 1'b1;
            tx_int <= 1'b0;
            rx_int <= 1'b0;
            tx_empty <= 1'b1;
            rx_ready <= 1'b0;
            tx_full <= 1'b0;
            rx_full <= 1'b0;
            overflow_error <= 1'b0;
            tx_head <= 3'd0;
            tx_tail <= 3'd0;
            rx_head <= 3'd0;
            rx_tail <= 3'd0;
            tx_count <= 4'd0;
            rx_count <= 4'd0;
            tx_state <= TX_IDLE;
            rx_state <= RX_IDLE;
            tx_bit_idx <= 3'd0;
            rx_bit_idx <= 3'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
        end else begin
            if (re) begin
                unique case (addr)
                    `UART_RT_DATA: begin
                        if (rx_count != 0) begin
                            rdata <= {24'd0, rx_buffer[rx_head]};
                        end else begin
                            rdata <= 32'd0;
                        end
                    end
                    `UART_RT_STATUS: rdata <= uart_status;
                    `UART_RT_CTRL:   rdata <= uart_ctrl;
                    `UART_RT_BAUD:   rdata <= uart_baud;
                    default:         rdata <= 32'd0;
                endcase
            end

            if (write_ctrl_req) begin
                uart_ctrl <= {wdata[31:4], 1'b0, wdata[2:0]};
            end

            if (write_baud_req) begin
                uart_baud <= wdata;
            end

            if (write_status_req && wdata[5]) begin
                overflow_error <= 1'b0;
            end

            if (soft_reset_req) begin
                uart_data <= 32'd0;
                rdata <= 32'd0;
                tx <= 1'b1;
                overflow_error <= 1'b0;
                tx_head <= 3'd0;
                tx_tail <= 3'd0;
                rx_head <= 3'd0;
                rx_tail <= 3'd0;
                tx_count <= 4'd0;
                rx_count <= 4'd0;
                tx_state <= TX_IDLE;
                rx_state <= RX_IDLE;
                tx_bit_idx <= 3'd0;
                rx_bit_idx <= 3'd0;
                tx_shift <= 8'd0;
                rx_shift <= 8'd0;
            end else begin
                if (write_data_req) begin
                    uart_data <= {24'd0, wdata[7:0]};
                    if (!tx_push) begin
                        overflow_error <= overflow_error | uart_en;
                    end
                end

                if (tx_push) begin
                    tx_buffer[tx_tail] <= wdata[7:0];
                    tx_tail <= tx_tail + 3'd1;
                end

                if (tx_pop) begin
                    tx_shift <= tx_buffer[tx_head];
                    tx_head <= tx_head + 3'd1;
                end

                unique case ({tx_push, tx_pop})
                    2'b10: tx_count <= tx_count + 4'd1;
                    2'b01: tx_count <= tx_count - 4'd1;
                    default: tx_count <= tx_count;
                endcase

                unique case (tx_state)
                    TX_IDLE: begin
                        tx <= 1'b1;
                        if (tx_pop) begin
                            tx_state <= TX_START;
                            tx_bit_idx <= 3'd0;
                            tx <= 1'b0;
                        end
                    end
                    TX_START: begin
                        if (tx_tick) begin
                            tx_state <= TX_DATA;
                            tx_bit_idx <= 3'd0;
                            tx <= tx_shift[0];
                        end
                    end
                    TX_DATA: begin
                        if (tx_tick) begin
                            if (tx_bit_idx == 3'd7) begin
                                tx_state <= TX_STOP;
                                tx <= 1'b1;
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 3'd1;
                                tx <= tx_shift[tx_bit_idx + 3'd1];
                            end
                        end
                    end
                    TX_STOP: begin
                        if (tx_tick) begin
                            tx_state <= TX_IDLE;
                            tx <= 1'b1;
                        end
                    end
                    default: begin
                        tx_state <= TX_IDLE;
                        tx <= 1'b1;
                    end
                endcase

                if (rx_pop) begin
                    uart_data <= {24'd0, rx_buffer[rx_head]};
                    rx_head <= rx_head + 3'd1;
                end else if (read_data_req) begin
                    uart_data <= 32'd0;
                end

                if (rx_push && (rx_count < FIFO_DEPTH)) begin
                    rx_buffer[rx_tail] <= rx_shift;
                    rx_tail <= rx_tail + 3'd1;
                end else if (rx_push) begin
                    overflow_error <= 1'b1;
                end

                unique case ({rx_push && (rx_count < FIFO_DEPTH), rx_pop})
                    2'b10: rx_count <= rx_count + 4'd1;
                    2'b01: rx_count <= rx_count - 4'd1;
                    default: rx_count <= rx_count;
                endcase

                unique case (rx_state)
                    RX_IDLE: begin
                        if (rx_falling && uart_en) begin
                            rx_state <= RX_START;
                        end
                    end
                    RX_START: begin
                        if (rx_tick) begin
                            if (!rx_sync1) begin
                                rx_state <= RX_DATA;
                                rx_bit_idx <= 3'd0;
                            end else begin
                                rx_state <= RX_IDLE;
                            end
                        end
                    end
                    RX_DATA: begin
                        if (rx_tick) begin
                            rx_shift[rx_bit_idx] <= rx_sync1;
                            if (rx_bit_idx == 3'd7) begin
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 3'd1;
                            end
                        end
                    end
                    RX_STOP: begin
                        if (rx_tick) begin
                            rx_state <= RX_IDLE;
                        end
                    end
                    default: rx_state <= RX_IDLE;
                endcase
            end

            tx_empty <= (tx_count == 0) && (tx_state == TX_IDLE);
            rx_ready <= (rx_count != 0);
            tx_full <= (tx_count == FIFO_DEPTH);
            rx_full <= (rx_count == FIFO_DEPTH);
            tx_int <= tx_int_en && ((tx_count == 0) && (tx_state == TX_IDLE));
            rx_int <= rx_int_en && (rx_count != 0);
        end
    end

endmodule
