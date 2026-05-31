`include "defines.svh"

//==============================================================================
// 模块名: icache
// 说明  : 直接映射、阻塞式指令 Cache。
//
// IF 侧协议:
//   if_ready=1 且 if_en=1 时接收一个取指请求 if_addr。
//   命中请求不会组合返回，而是在请求被接收后的下一个周期拉高 if_valid，
//   同时输出 if_rdata。这样 IF 看到的时序就是“本周期发地址、下周期收数据”，
//   与一拍同步指令存储器保持一致。
//
// IROM 侧协议:
//   miss 时向后端 IROM 发起一条 cache line 读取请求。IROM 下一拍返回整行数据后，
//   本模块先把该行写入 cache，不在同一个周期旁路返回给 IF，避免重新引入
//   IROM -> IF 的长组合路径。
//==============================================================================
module icache (
    input logic clk,
    input logic rst_n,
    // 指令存储器接口
    input  logic [`ICACHE_LINE_SIZE*8-1:0] imem_rdata,
    output logic [31:0]                   imem_addr,
    output logic                          imem_en,
    // IF阶段接口
    input  logic        if_en,
    output logic        if_ready,
    input  logic [31:0] if_addr,
    output logic [31:0] if_rdata,
    output logic        if_valid
);

    // Cache 容量参数由 defines.svh 给出。当前配置为 1024B cache，
    // 16B cache line，即 64 行、每行 4 条 32-bit 指令。
    localparam ICACHE_NUM_LINES       = `ICACHE_SIZE / `ICACHE_LINE_SIZE;
    localparam ICACHE_INDEX_BITS      = $clog2(ICACHE_NUM_LINES);
    localparam ICACHE_OFFSET_BITS     = $clog2(`ICACHE_LINE_SIZE);
    localparam ICACHE_TAG_BITS        = 32 - ICACHE_INDEX_BITS - ICACHE_OFFSET_BITS;
    localparam ICACHE_WORDS_PER_LINE  = `ICACHE_LINE_SIZE / 4;
    localparam ICACHE_WORD_INDEX_BITS = $clog2(ICACHE_WORDS_PER_LINE);

    // 直接映射 cache 存储体:
    //   cache_valid[index] 标识该行是否有效；
    //   cache_tag[index] 保存地址高位 tag；
    //   cache_data[index][word] 保存 line 内对应 word。
    logic cache_valid [ICACHE_NUM_LINES-1:0];
    logic [ICACHE_TAG_BITS-1:0] cache_tag [ICACHE_NUM_LINES-1:0];
    logic [31:0] cache_data [ICACHE_NUM_LINES-1:0][ICACHE_WORDS_PER_LINE-1:0];

    // 当前已经被 cache 接收、正在等待命中判断或 miss 填充的 IF 请求。
    // 本 cache 只保留一个 outstanding 请求，因此 miss 时会阻塞后续请求。
    logic req_valid;
    logic [31:0] req_addr;
    logic miss_wait;

    logic [ICACHE_INDEX_BITS-1:0] req_index;
    logic [ICACHE_TAG_BITS-1:0] req_tag;
    logic [ICACHE_WORD_INDEX_BITS-1:0] req_word_index;
    logic req_hit;
    logic resp_valid;
    logic req_miss;

    // 请求地址拆分:
    //   byte offset 固定忽略，取指始终按 32-bit 对齐；
    //   word index 选择 cache line 内第几条指令；
    //   index 选择直接映射 cache 的行；
    //   tag 用于判断该行是否就是目标地址对应的 line。
    assign req_word_index = req_addr[ICACHE_OFFSET_BITS-1:2];
    assign req_index = req_addr[ICACHE_OFFSET_BITS + ICACHE_INDEX_BITS - 1
                               : ICACHE_OFFSET_BITS];
    assign req_tag = req_addr[31:ICACHE_OFFSET_BITS + ICACHE_INDEX_BITS];

    // 命中时只对已经锁存的 req_addr 返回响应。if_addr 的当前组合变化
    // 不会直接影响 if_rdata，保证 IF/Cache 之间是一拍响应协议。
    assign req_hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);
    assign resp_valid = req_valid && req_hit && !miss_wait;
    assign req_miss = req_valid && !req_hit && !miss_wait;

    // IF 侧 ready/valid:
    //   没有 outstanding 请求时可以接收新请求；
    //   命中响应周期也可以同时接收下一条请求，从而实现连续命中每周期一条。
    assign if_valid = resp_valid;
    assign if_rdata = resp_valid ? cache_data[req_index][req_word_index] : 32'b0;
    assign if_ready = !miss_wait && (!req_valid || resp_valid);

    // IROM 侧只在 miss 检测周期发起一次 line 读取。
    // miss_wait 周期等待 IROM 返回并写入 cache，不继续拉高 imem_en。
    assign imem_en = req_miss;
    assign imem_addr = req_miss ? {req_addr[31:ICACHE_OFFSET_BITS],
                                   {ICACHE_OFFSET_BITS{1'b0}}} : 32'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        integer j;
        if (!rst_n) begin
            req_valid <= 1'b0;
            req_addr <= 32'b0;
            miss_wait <= 1'b0;
            for (i = 0; i < ICACHE_NUM_LINES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_tag[i] <= '0;
                for (j = 0; j < ICACHE_WORDS_PER_LINE; j = j + 1) begin
                    cache_data[i][j] <= 32'b0;
                end
            end
        end else begin
            if (miss_wait) begin
                // IROM 返回数据后一拍写入 cache line。此处刻意不旁路给 IF，
                // 下一周期 req_hit 才会成立并通过 if_valid 返回。
                for (j = 0; j < ICACHE_WORDS_PER_LINE; j = j + 1) begin
                    cache_data[req_index][j] <= imem_rdata[j*32 +: 32];
                end
                cache_valid[req_index] <= 1'b1;
                cache_tag[req_index] <= req_tag;
                miss_wait <= 1'b0;
            end else if (req_miss) begin
                // miss 请求已经送出到 IROM，等待下一拍返回整行数据。
                miss_wait <= 1'b1;
            end

            if (resp_valid) begin
                req_valid <= 1'b0;
            end

            if (if_en && if_ready) begin
                // 接收 IF 新请求。若本周期同时 resp_valid，则旧请求完成、
                // 新请求接替 req_addr，实现一拍取指流水。
                req_valid <= 1'b1;
                req_addr <= if_addr;
            end
        end
    end

endmodule
