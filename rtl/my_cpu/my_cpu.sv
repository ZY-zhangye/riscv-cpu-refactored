`include "defines.svh"
`include "my_cpu_defines.svh"

module my_cpu #(
    parameter bit BOARD_MEMORY = 1'b0,
    parameter INST_INIT_FILE = "",
    parameter DATA_INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clk_uart,
    input  logic        uart_rx,
    input  logic [`PLIC_NUM_INTERRUPTS-1:0] external_interrupts,
    output logic        uart_tx,
    output logic [31:0] led,
    output logic        plic_irq
    `ifdef DEBUG_EN
    ,
    output logic [31:0] debug_inst_pc,
    output logic [31:0] debug_wb_pc,
    output logic [4:0]  debug_wb_rf_addr,
    output logic [31:0] debug_wb_rf_data,
    output logic        debug_wb_rf_wen,
    output logic        debug_wb_fpu_rf_wen,
    output logic [31:0] debug_data
    `endif
);

    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic        imem_en;

    logic [31:0] cpu_dmem_rdata;
    logic [31:0] cpu_dmem_addr;
    logic [3:0]  cpu_dmem_wen;
    logic        cpu_dmem_en;
    logic [31:0] cpu_dmem_wdata;

    logic        ram_en;
    logic [31:0] ram_addr;
    logic [3:0]  ram_wen;
    logic [31:0] ram_wdata;
    logic [31:0] ram_rdata;

    logic        io_sel;
    logic        io_re;
    logic [3:0]  io_wen;
    logic [31:0] io_addr;
    logic [31:0] io_wdata;
    logic [31:0] io_rdata;

    logic        plic_sel;
    logic        plic_re;
    logic        plic_we;
    logic [31:0] plic_addr;
    logic [31:0] plic_wdata;
    logic [31:0] plic_rdata;

    logic [`PLIC_NUM_INTERRUPTS-1:0] io_interrupts;
    logic [`PLIC_NUM_INTERRUPTS-1:0] plic_interrupts;

    assign plic_interrupts = external_interrupts | io_interrupts;

    cpu_top u_cpu_top (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(cpu_dmem_rdata),
        .dmem_addr(cpu_dmem_addr),
        .dmem_wen(cpu_dmem_wen),
        .dmem_en(cpu_dmem_en),
        .dmem_wdata(cpu_dmem_wdata),
        .plic_irq(plic_irq)
        `ifdef DEBUG_EN
        ,
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_data(debug_data)
        `endif
    );

    `ifdef DEBUG_EN
    assign debug_inst_pc = imem_addr;
    `endif

    soc_inst_ram #(
        .INIT_FILE(INST_INIT_FILE)
    ) u_inst_ram (
        .clk(clk),
        .addr(imem_addr),
        .en(imem_en),
        .rdata(imem_rdata)
    );

    soc_data_ram #(
        .SYNCHRONOUS_READ(BOARD_MEMORY),
        .INIT_FILE(DATA_INIT_FILE)
    ) u_data_ram (
        .clk(clk),
        .addr(ram_addr),
        .en(ram_en),
        .wen(ram_wen),
        .wdata(ram_wdata),
        .rdata(ram_rdata)
    );

    bridge #(
        .RAM_SYNCHRONOUS_READ(BOARD_MEMORY)
    ) u_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_dmem_en(cpu_dmem_en),
        .cpu_dmem_addr(cpu_dmem_addr),
        .cpu_dmem_wen(cpu_dmem_wen),
        .cpu_dmem_wdata(cpu_dmem_wdata),
        .cpu_dmem_rdata(cpu_dmem_rdata),
        .ram_en(ram_en),
        .ram_addr(ram_addr),
        .ram_wen(ram_wen),
        .ram_wdata(ram_wdata),
        .ram_rdata(ram_rdata),
        .io_sel(io_sel),
        .io_re(io_re),
        .io_wen(io_wen),
        .io_addr(io_addr),
        .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .plic_sel(plic_sel),
        .plic_re(plic_re),
        .plic_we(plic_we),
        .plic_addr(plic_addr),
        .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
    );

    IO u_io (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .io_sel(io_sel),
        .io_re(io_re),
        .io_wen(io_wen),
        .io_addr(io_addr),
        .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .peripheral_interrupts(io_interrupts)
    );

    PLIC u_plic (
        .clk(clk),
        .rst_n(rst_n),
        .peripheral_interrupts(plic_interrupts),
        .plic_irq(plic_irq),
        .plic_sel(plic_sel),
        .plic_we(plic_we),
        .plic_re(plic_re),
        .plic_addr(plic_addr),
        .plic_wdata(plic_wdata),
        .plic_rdata(plic_rdata)
    );

endmodule

module soc_inst_ram #(
    parameter int WORDS = 4096,
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        en,
    output logic [31:0] rdata
);
    localparam int INDEX_WIDTH = $clog2(WORDS);
    (* ram_style = "block" *)
    logic [31:0] mem [0:WORDS-1] /* verilator public_flat_rw */;

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr[INDEX_WIDTH+1:2]];
        end
    end
endmodule

module soc_data_ram #(
    parameter int WORDS = 65536,
    parameter bit SYNCHRONOUS_READ = 1'b0,
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        en,
    input  logic [3:0]  wen,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    localparam int INDEX_WIDTH = $clog2(WORDS);
    // Board builds use a synchronous, byte-write-enabled BRAM. The default
    // asynchronous model preserves the existing instruction regression timing.
    (* ram_style = SYNCHRONOUS_READ ? "block" : "distributed" *)
    logic [31:0] mem [0:WORDS-1] /* verilator public_flat_rw */;

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    generate
        if (SYNCHRONOUS_READ) begin : g_sync_read
            always_ff @(posedge clk) begin
                if (en) rdata <= mem[addr[INDEX_WIDTH+1:2]];
            end
        end else begin : g_async_read
            assign rdata = en ? mem[addr[INDEX_WIDTH+1:2]] : 32'd0;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (en) begin
            if (wen[0]) begin
                mem[addr[INDEX_WIDTH+1:2]][7:0] <= wdata[7:0];
            end
            if (wen[1]) begin
                mem[addr[INDEX_WIDTH+1:2]][15:8] <= wdata[15:8];
            end
            if (wen[2]) begin
                mem[addr[INDEX_WIDTH+1:2]][23:16] <= wdata[23:16];
            end
            if (wen[3]) begin
                mem[addr[INDEX_WIDTH+1:2]][31:24] <= wdata[31:24];
            end
        end
    end
endmodule
