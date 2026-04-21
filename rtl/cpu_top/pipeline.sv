module pipeline (
    input logic clk,
    input logic rst_n,
    output logic [31:0] dmem_addr,
    output logic [3:0] dmem_wen,
    output logic dmem_en,
    output logic [31:0] dmem_wdata,
    input [31:0] dmem_rdata,
    input logic [31:0] dmem_addr_o,
    input logic [3:0] dmem_wen_o,
    input logic dmem_en_o,
    input logic [31:0] dmem_wdata_o,
    output logic [31:0] dmem_rdata_o,
    output logic stall_mem,
    output logic stall_exe
);

    logic [1:0] a;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a<= 0;
            dmem_addr <= 0;
            dmem_wen <= 0;
            dmem_en <= 0;
            dmem_wdata <= 0;
            dmem_rdata_o <= 0;
            stall_mem <= 0;
            stall_exe <= 0;
        end else begin
            case (a)
                2'b00: begin
                    if (dmem_en_o) begin
                        dmem_addr <= dmem_addr_o;
                        dmem_wen <= dmem_wen_o;
                        dmem_en <= dmem_en_o;
                        dmem_wdata <= dmem_wdata_o;
                        stall_mem <= 0;
                        stall_exe <= 1;
                        a <= 2'b01;
                    end else begin
                        stall_mem <= 0;
                        stall_exe <= 0;
                    end
                end
                2'b01: begin
                    dmem_addr <= dmem_addr_o;
                    dmem_wen <= dmem_wen_o;
                    dmem_en <= dmem_en_o;
                    dmem_wdata <= dmem_wdata_o;
                    stall_mem <= 1;
                    stall_exe <= 0;
                    a <= 2'b10;
                end
                2'b10: begin
                    dmem_addr <= dmem_addr_o;
                    dmem_wen <= dmem_wen_o;
                    dmem_en <= dmem_en_o;
                    dmem_wdata <= dmem_wdata_o;
                    dmem_rdata_o <= dmem_rdata;
                    stall_mem <= 0;
                    stall_exe <= 0;
                    a <= 2'b00;
                end
            endcase
        end
    end



endmodule