module tb_cpu_top;
    // 加载内存文件
/*# 定义【标准整数运算指令集】数组 - RV32I 基础指令全集
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
# 定义【特殊系统指令集】数组 - 包含特权指令/系统调用指令
MI_INSTS=(csr scall sbreak ma_fetch)*/
//乘法指令
// UM_INSTS=(mul mulh mulhu mulhsu div divu rem remu)
localparam MEM_ADDR = "F:\\riscv-cpu-refactored\\hex\\riscv-tests\\rv32-p-riscv.hex";

    logic clk;
    logic rst_n;
    logic [31:0] imem_rdata;
    logic [31:0] imem_addr;
    logic imem_en;
    logic [31:0] dmem_rdata;
    logic [31:0] dmem_addr;
    logic [3:0] dmem_wen;
    logic dmem_en;
    logic [31:0] dmem_wdata;
    logic [31:0] debug_wb_pc;
    logic [4:0] debug_wb_rf_addr;
    logic [31:0] debug_wb_rf_data;
    logic debug_wb_rf_wen;
    logic debug_wb_fpu_rf_wen;
    logic [31:0] debug_data;

    cpu_top cpu_top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata(imem_rdata),
        .imem_addr(imem_addr),
        .imem_en(imem_en),
        .dmem_rdata(dmem_rdata),
        .dmem_addr(dmem_addr),
        .dmem_wen(dmem_wen),
        .dmem_en(dmem_en),
        .dmem_wdata(dmem_wdata),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_addr(debug_wb_rf_addr),
        .debug_wb_rf_data(debug_wb_rf_data),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_fpu_rf_wen(debug_wb_fpu_rf_wen),
        .debug_data(debug_data)
    );

    initial begin
        clk = 1;
        forever #5 clk = ~clk; // 100MHz时钟
    end
    initial begin
        rst_n = 0;
        #20 rst_n = 1; // 20ns后释放复位
    end

    //imem与dmem设计与实例化
    logic [31:0] imem [0:5095]; // 5KB指令存储器
    logic [31:0] dmem [0:5095]; // 5KB数据存储器
    initial begin
        //加载测试指令到imem
        $readmemh(MEM_ADDR, imem);
        $readmemh(MEM_ADDR, dmem); 
    end

    //连接imem和dmem
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            imem_rdata <= 32'b0;
        end else begin
            if (imem_en) begin
                imem_rdata <= imem[imem_addr[23:2]]; // 以字为单位访问
            end
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dmem_rdata <= 32'b0;
        end else begin
            if (dmem_en) begin
                if (dmem_wen != 4'b0000) begin
                    // 写操作，根据wen信号选择写入的字节
                    if (dmem_wen[0]) dmem[dmem_addr[23:2]][7:0] <= dmem_wdata[7:0];
                    if (dmem_wen[1]) dmem[dmem_addr[23:2]][15:8] <= dmem_wdata[15:8];
                    if (dmem_wen[2]) dmem[dmem_addr[23:2]][23:16] <= dmem_wdata[23:16];
                    if (dmem_wen[3]) dmem[dmem_addr[23:2]][31:24] <= dmem_wdata[31:24];
                end
                dmem_rdata <= dmem[dmem_addr[23:2]];
            end else begin
                dmem_rdata <= dmem_rdata; // 保持原值
            end
        end
    end

    //监视信号变化
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            $display("Time: %0t, Reset asserted", $time);
        end else begin
            $display("Time: %0t", $time);
            $display("debug_inst_pc: %h", (imem_addr - 4));
            $display("debug_wb_pc: %h", debug_wb_pc);
            $display("debug_wb_rf_wen: %b", debug_wb_rf_wen);
            $display("debug_wb_rf_wnum: %h", debug_wb_rf_addr);
            $display("debug_wb_rf_data: %h", debug_wb_rf_data);
            $display("debug_data: %h", debug_data);
            $display("debug_wb_fpu_rf_wen: %b", debug_wb_fpu_rf_wen);
            $display("--------------------------------------------------");
        end
    end
    initial begin
        #50000;
        $display("Simulation timeout");
        $finish;
    end

    always_ff @ (posedge clk) begin
        if (rst_n) begin
            if (debug_wb_pc == 32'h80000044) begin
                    $display("---------------------------------------------");
                    $display("Time: %0t", $time);
                    $display("Simulation finished.");
                    $display("----------------------------------------------");
                if (debug_data == 32'h00000001) begin
                    $display("Test passed.");
                end else begin
                    $display("Test failed. Expected 1 in x10, got %08h", debug_data);
                end
                $display("----------------------------------------------");
                $stop;
            end
        end
    end

endmodule