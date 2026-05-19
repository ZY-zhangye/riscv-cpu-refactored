`include "my_cpu_defines.svh"
module PLIC (
    input logic clk,
    input logic rst_n,
    // 外设中断输入
    input logic [`PLIC_NUM_INTERRUPTS-1:0] peripheral_interrupts,
    // CPU接口
    output logic plic_irq, // PLIC发出的中断请求信号
    // bridge路由的读写端口信号
    input logic plic_sel, // 选择信号，表示当前访问的是PLIC
    input logic plic_we,  // 写使能信号
    input logic plic_re,  // 读使能信号
    input logic [31:0] plic_addr, // 地址信号
    input logic [31:0] plic_wdata, // 写数据
    output logic [31:0] plic_rdata // 读数据
);


    // PLIC内部寄存器定义
    logic [`PRIORITY_WIDTH-1:0] priority_regs [`PLIC_NUM_INTERRUPTS-1:0]; // 优先级寄存器
    logic [`PLIC_NUM_INTERRUPTS-1:0] pending_regs; // 待处理寄存器
    logic [`PLIC_NUM_INTERRUPTS-1:0] enable_regs; // 使能寄存器
    logic [`PRIORITY_WIDTH-1:0] threshold_reg; // 阈值寄存器
    logic [`PLIC_NUM_INTERRUPTS-1:0] in_service_regs; // 处理中寄存器

    logic [`PRIORITY_WIDTH-1:0] claim_priority;
    logic [`ID_WIDTH-1:0] claim_id;
    logic claim_valid;

    // 处理中的中断、阈值和优先级比较拆成独立组合逻辑
    always_comb begin
        integer i;
        claim_priority = '0;
        claim_id = '0;
        claim_valid = 1'b0;

        for (i = 1; i < `PLIC_NUM_INTERRUPTS; i++) begin
            if (pending_regs[i] && enable_regs[i] && !in_service_regs[i]) begin
                if ((priority_regs[i] > threshold_reg) &&
                    (priority_regs[i] > claim_priority)) begin
                    claim_priority = priority_regs[i];
                    claim_id = i[`ID_WIDTH-1:0];
                    claim_valid = 1'b1;
                end
            end
        end

        plic_irq = claim_valid;
    end

    // PLIC寄存器读写逻辑
    function automatic logic [31:0] read_reg(input logic [31:0] addr);
        automatic int unsigned idx;
        begin
            if ((addr >= `PLIC_PRIORITY_BASE_ADDR) &&
                (addr < (`PLIC_PRIORITY_BASE_ADDR + (`PLIC_NUM_INTERRUPTS * 4)))) begin
                idx = (addr - `PLIC_PRIORITY_BASE_ADDR) >> 2;
                read_reg = {{(32-`PRIORITY_WIDTH){1'b0}}, priority_regs[idx]};
            end else begin
                case (addr)
                    `PLIC_PENDING_BASE_ADDR:     read_reg = {{(32-`PLIC_NUM_INTERRUPTS){1'b0}}, pending_regs};
                    `PLIC_ENABLE_BASE_ADDR:      read_reg = {{(32-`PLIC_NUM_INTERRUPTS){1'b0}}, enable_regs};
                    `PLIC_THRESHOLD_BASE_ADDR:   read_reg = {{(32-`PRIORITY_WIDTH){1'b0}}, threshold_reg};
                    `PLIC_IN_SERVICE_BASE_ADDR:  read_reg = in_service_regs;
                    default:                     read_reg = 32'hDEAD_BEEF; // 无效地址返回特定值
                endcase
            end
        end
    endfunction

    task automatic write_reg(input logic [31:0] addr, input logic [31:0] data);
        automatic int unsigned idx;
        begin
            if ((addr >= `PLIC_PRIORITY_BASE_ADDR) &&
                (addr < (`PLIC_PRIORITY_BASE_ADDR + (`PLIC_NUM_INTERRUPTS * 4)))) begin
                idx = (addr - `PLIC_PRIORITY_BASE_ADDR) >> 2;
                if (idx != 0) begin
                    priority_regs[idx] <= data[`PRIORITY_WIDTH-1:0];
                end
            end else begin
                case (addr)
                    `PLIC_ENABLE_BASE_ADDR:     enable_regs <= {data[`PLIC_NUM_INTERRUPTS-1:1], 1'b0};
                    `PLIC_THRESHOLD_BASE_ADDR:  threshold_reg <= data[`PRIORITY_WIDTH-1:0];
                    default:                    ;
                endcase
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        logic [`PLIC_NUM_INTERRUPTS-1:0] pending_next;
        logic [`PLIC_NUM_INTERRUPTS-1:0] in_service_next;
        logic [`PLIC_NUM_INTERRUPTS-1:0] claim_mask;
        logic [`PLIC_NUM_INTERRUPTS-1:0] release_mask;

        if (!rst_n) begin
            for (i = 0; i < `PLIC_NUM_INTERRUPTS; i++) begin
                priority_regs[i] <= '0;
            end
            pending_regs <= '0;
            enable_regs <= '0;
            threshold_reg <= '0;
            in_service_regs <= 32'd0;
            plic_rdata <= 32'd0;
        end else begin
            pending_next = pending_regs | (peripheral_interrupts & ~in_service_regs);
            in_service_next = in_service_regs;
            claim_mask = '0;
            release_mask = '0;

            if (plic_sel && plic_re) begin
                if (plic_addr == `PLIC_CLAIM_BASE_ADDR) begin
                    if (claim_valid) begin
                        plic_rdata <= claim_id;
                        claim_mask[claim_id] = 1'b1;
                    end else begin
                        plic_rdata <= 32'd0;
                    end
                end else begin
                    plic_rdata <= read_reg(plic_addr);
                end
            end

            if (plic_sel && plic_we) begin
                if (plic_addr == `PLIC_CLAIM_BASE_ADDR) begin
                    if ((plic_wdata[`ID_WIDTH-1:0] != '0) &&
                        (plic_wdata[`ID_WIDTH-1:0] < `PLIC_NUM_INTERRUPTS) &&
                        in_service_regs[plic_wdata[`ID_WIDTH-1:0]]) begin
                        release_mask[plic_wdata[`ID_WIDTH-1:0]] = 1'b1;
                    end
                end else begin
                    write_reg(plic_addr, plic_wdata);
                end
            end

            pending_next = pending_next & ~claim_mask;
            pending_next[0] = 1'b0;
            in_service_next = (in_service_next | claim_mask) & ~release_mask;
            in_service_next[0] = 1'b0;

            pending_regs <= pending_next;
            in_service_regs <= in_service_next;
        end
    end




endmodule
