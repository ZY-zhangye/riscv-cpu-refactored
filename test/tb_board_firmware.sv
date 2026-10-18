`timescale 1ns/1ps
`include "defines.svh"

// Run the real board ELF images against the same synchronous BRAM/SoC path.
// UART is decoded electrically rather than peeking at transmit FIFO writes.
module tb_board_firmware;
    parameter INST_FILE = "build/hello_zynq/firmware/smoke/inst.mem";
    parameter DATA_FILE = "build/hello_zynq/firmware/smoke/data.mem";
    parameter PASS_TEXT = "SMOKE_PASS";
    parameter integer MAX_CYCLES = 20000000;
    parameter integer BIT_CYCLES = 434;
    logic clk = 0;
    always #10 clk = ~clk;
    logic rst_n = 0;
    wire tx;
    wire [31:0] led;
    wire irq;
    integer cycles = 0;
    string uart_line = "";
    logic passed = 0;
    my_cpu #(
        .BOARD_MEMORY(1'b1), .INST_INIT_FILE(INST_FILE), .DATA_INIT_FILE(DATA_FILE)
    ) soc (
        .clk(clk), .rst_n(rst_n), .clk_uart(1'b0), .uart_rx(1'b1),
        .external_interrupts(32'b0), .uart_tx(tx), .led(led), .plic_irq(irq)
    );

    initial begin
        repeat (16) @(negedge clk);
        rst_n = 1;
    end
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles >= MAX_CYCLES)
            $fatal(1, "FIRMWARE_TIMEOUT cycles=%0d led=%h pc=%h last_line=%s",
                   cycles, led, soc.imem_addr, uart_line);
    end
    function automatic bit contains(input string value, needle);
        for (int i=0; i+needle.len()<=value.len(); i++)
            if (value.substr(i, i+needle.len()-1) == needle) return 1;
        return 0;
    endfunction
    initial begin : decode_uart
        logic [7:0] byte_value;
        wait(rst_n);
        forever begin
            @(negedge tx);
            repeat (BIT_CYCLES / 2) @(posedge clk);
            #1;
            if (tx !== 0) $fatal(1, "UART start bit was not low");
            for (int bit_index=0; bit_index<8; bit_index++) begin
                repeat (BIT_CYCLES) @(posedge clk);
                #1;
                byte_value[bit_index] = tx;
            end
            repeat (BIT_CYCLES) @(posedge clk);
            #1;
            if (tx !== 1) $fatal(1, "UART stop bit was not high");
            if (byte_value == 10) begin
                $display("UART: %s", uart_line);
                if (contains(uart_line, "SMOKE_FAIL") || contains(uart_line, "status=FAIL"))
                    $fatal(1, "Firmware reported failure: %s", uart_line);
                if (contains(uart_line, PASS_TEXT)) begin
                    $display("BOARD_FIRMWARE_PASS cycles=%0d led=%h marker=%s", cycles, led, PASS_TEXT);
                    passed = 1;
                    $finish;
                end
                uart_line = "";
            end else if (byte_value != 13) begin
                uart_line = {uart_line, byte_value};
            end
        end
    end
endmodule
