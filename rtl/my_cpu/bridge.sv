`include "my_cpu_defines.svh"

module bridge (
    input  logic        clk,
    input  logic        rst_n,

    // CPU data memory side
    input  logic        cpu_dmem_en,
    input  logic [31:0] cpu_dmem_addr,
    input  logic [3:0]  cpu_dmem_wen,
    input  logic [31:0] cpu_dmem_wdata,
    output logic [31:0] cpu_dmem_rdata,

    // data RAM side
    output logic        ram_en,
    output logic [31:0] ram_addr,
    output logic [3:0]  ram_wen,
    output logic [31:0] ram_wdata,
    input  logic [31:0] ram_rdata,

    // IO side
    output logic        io_sel,
    output logic        io_re,
    output logic [3:0]  io_wen,
    output logic [31:0] io_addr,
    output logic [31:0] io_wdata,
    input  logic [31:0] io_rdata,

    // PLIC side
    output logic        plic_sel,
    output logic        plic_re,
    output logic        plic_we,
    output logic [31:0] plic_addr,
    output logic [31:0] plic_wdata,
    input  logic [31:0] plic_rdata
);

    localparam logic [1:0] TARGET_NONE = 2'd0;
    localparam logic [1:0] TARGET_RAM  = 2'd1;
    localparam logic [1:0] TARGET_IO   = 2'd2;
    localparam logic [1:0] TARGET_PLIC = 2'd3;
    localparam logic [31:0] UART_BASE  = `MY_CPU_UART_BASE_ADDR;
    localparam logic [31:0] TIMER_BASE = `MY_CPU_TIMER_BASE_ADDR;
    localparam logic [31:0] LEDS_BASE  = `MY_CPU_LEDS_BASE_ADDR;

    logic cpu_write;
    logic cpu_read;
    logic ram_sel;
    logic io_region_sel;
    logic plic_region_sel;
    logic [1:0] read_target_r;
    logic [31:0] ram_rdata_r;

    assign cpu_write = cpu_dmem_en && (cpu_dmem_wen != 4'b0000);
    assign cpu_read = cpu_dmem_en && (cpu_dmem_wen == 4'b0000);

    assign ram_sel = cpu_dmem_en &&
                     ((cpu_dmem_addr[31:28] == 4'h6) ||
                      (cpu_dmem_addr[31:16] == 16'h8000) ||
                      ((cpu_dmem_addr >= 32'h8010_0000) &&
                       (cpu_dmem_addr <= 32'h8013_FFFF)));

    assign io_region_sel = cpu_dmem_en &&
                           ((cpu_dmem_addr[31:16] == UART_BASE[31:16]) ||
                            (cpu_dmem_addr[31:16] == TIMER_BASE[31:16]) ||
                            (cpu_dmem_addr[31:16] == LEDS_BASE[31:16]));

    assign plic_region_sel = cpu_dmem_en &&
                             (cpu_dmem_addr >= `PLIC_PRIORITY_BASE_ADDR) &&
                             (cpu_dmem_addr <= (`PLIC_IN_SERVICE_BASE_ADDR + 32'd4));

    assign ram_en = ram_sel;
    assign ram_addr = cpu_dmem_addr;
    assign ram_wen = (ram_sel && cpu_write) ? cpu_dmem_wen : 4'b0000;
    assign ram_wdata = cpu_dmem_wdata;

    assign io_sel = io_region_sel;
    assign io_re = io_region_sel && cpu_read;
    assign io_wen = (io_region_sel && cpu_write) ? cpu_dmem_wen : 4'b0000;
    assign io_addr = cpu_dmem_addr;
    assign io_wdata = cpu_dmem_wdata;

    assign plic_sel = plic_region_sel;
    assign plic_re = plic_region_sel && cpu_read;
    assign plic_we = plic_region_sel && cpu_write;
    assign plic_addr = cpu_dmem_addr;
    assign plic_wdata = cpu_dmem_wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_target_r <= TARGET_NONE;
            ram_rdata_r <= 32'd0;
        end else if (cpu_dmem_en) begin
            ram_rdata_r <= ram_rdata;
            unique case (1'b1)
                ram_sel:         read_target_r <= TARGET_RAM;
                io_region_sel:   read_target_r <= TARGET_IO;
                plic_region_sel: read_target_r <= TARGET_PLIC;
                default:         read_target_r <= TARGET_NONE;
            endcase
        end else begin
            read_target_r <= TARGET_NONE;
        end
    end

    always_comb begin
        unique case (read_target_r)
            TARGET_RAM:  cpu_dmem_rdata = ram_rdata_r;
            TARGET_IO:   cpu_dmem_rdata = io_rdata;
            TARGET_PLIC: cpu_dmem_rdata = plic_rdata;
            default:     cpu_dmem_rdata = 32'd0;
        endcase
    end

endmodule
