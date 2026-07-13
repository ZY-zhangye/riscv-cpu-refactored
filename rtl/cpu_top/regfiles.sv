`include "defines.svh"
module regfiles (
    input logic clk,
    input logic rst_n,
    // Two architectural write ports.  If both target the same nonzero
    // register, write1 (the younger lane) has explicit priority.
    input logic write0_wen,
    input logic [4:0] write0_waddr,
    input logic [31:0] write0_wdata,
    input logic write1_wen,
    input logic [4:0] write1_waddr,
    input logic [31:0] write1_wdata,
    // Legacy combinational read ports retained while the old backend is
    // serialized.  A3 dual ALU bundles use the synchronous four-read ports.
    input logic [4:0] regfile_raddr1,
    output logic [31:0] regfile_rdata1,
    input logic [4:0] regfile_raddr2,
    output logic [31:0] regfile_rdata2,
    input logic sync_ren,
    input logic [4:0] sync_raddr0,
    input logic [4:0] sync_raddr1,
    input logic [4:0] sync_raddr2,
    input logic [4:0] sync_raddr3,
    output logic [31:0] sync_rdata0,
    output logic [31:0] sync_rdata1,
    output logic [31:0] sync_rdata2,
    output logic [31:0] sync_rdata3
    `ifdef DEBUG_EN
    ,
    //debug接口
    output logic [31:0] debug_data
    `endif
);

    logic [31:0] regfile [31:0];
    task clean_regfile;
        integer i;
        for (i = 0; i < 32; i++) begin
            regfile[i] = 32'b0;
        end
    endtask
    function automatic logic [31:0] read_with_write_bypass(
        input logic [4:0] read_addr
    );
        begin
            if (read_addr == 0) begin
                read_with_write_bypass = 32'b0;
            end else if (write1_wen && (write1_waddr == read_addr) &&
                         (write1_waddr != 0)) begin
                read_with_write_bypass = write1_wdata;
            end else if (write0_wen && (write0_waddr == read_addr) &&
                         (write0_waddr != 0)) begin
                read_with_write_bypass = write0_wdata;
            end else begin
                read_with_write_bypass = regfile[read_addr];
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clean_regfile();
            sync_rdata0 <= 32'b0;
            sync_rdata1 <= 32'b0;
            sync_rdata2 <= 32'b0;
            sync_rdata3 <= 32'b0;
        end else begin
            if (write0_wen && (write0_waddr != 0)) begin
                regfile[write0_waddr] <= write0_wdata;
            end
            if (write1_wen && (write1_waddr != 0)) begin
                regfile[write1_waddr] <= write1_wdata;
            end
            regfile[0] <= 32'b0;

            if (sync_ren) begin
                sync_rdata0 <= read_with_write_bypass(sync_raddr0);
                sync_rdata1 <= read_with_write_bypass(sync_raddr1);
                sync_rdata2 <= read_with_write_bypass(sync_raddr2);
                sync_rdata3 <= read_with_write_bypass(sync_raddr3);
            end
        end
    end

    assign regfile_rdata1 = (regfile_raddr1 != 5'b0) ? regfile[regfile_raddr1] : 32'b0;
    assign regfile_rdata2 = (regfile_raddr2 != 5'b0) ? regfile[regfile_raddr2] : 32'b0;
    `ifdef DEBUG_EN
    assign debug_data = regfile[3];
    `endif


endmodule
