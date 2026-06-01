`include "defines.svh"

//==============================================================================
// 模块名: icache
// 说明  : 直接映射、阻塞式指令 Cache。
//
// IF 侧协议:
//   if_ready=1 且 if_en=1 时接收一个取指请求 if_addr。
//   cache 数据体采用同步读 RAM 模板，请求被接收后一拍返回 if_valid/if_rdata。
//
// IROM 侧协议:
//   miss 时向后端 IROM 发起一条 cache line 读取请求。IROM 返回整行数据后，
//   本模块先写入 cache，再在后一拍对 IF 返回，不做同拍旁路。
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

    localparam ICACHE_NUM_LINES       = `ICACHE_SIZE / `ICACHE_LINE_SIZE;
    localparam ICACHE_INDEX_BITS      = $clog2(ICACHE_NUM_LINES);
    localparam ICACHE_OFFSET_BITS     = $clog2(`ICACHE_LINE_SIZE);
    localparam ICACHE_TAG_BITS        = 32 - ICACHE_INDEX_BITS - ICACHE_OFFSET_BITS;
    localparam ICACHE_WORDS_PER_LINE  = `ICACHE_LINE_SIZE / 4;
    localparam ICACHE_WORD_INDEX_BITS = $clog2(ICACHE_WORDS_PER_LINE);
    localparam ICACHE_LINE_BITS       = `ICACHE_LINE_SIZE * 8;

    logic cache_valid [ICACHE_NUM_LINES-1:0];
    logic [ICACHE_TAG_BITS-1:0] cache_tag [ICACHE_NUM_LINES-1:0];

    // data RAM 不在 reset 时清零，只通过 valid 位判定内容是否可用。
    // 这种同步读、整行写的模板更容易被 FPGA 综合器推断为 BRAM。
    (* ram_style = "block" *)
    logic [ICACHE_LINE_BITS-1:0] cache_data [ICACHE_NUM_LINES-1:0];

    logic req_valid;
    logic [31:0] req_addr;
    logic miss_wait;
    logic [ICACHE_LINE_BITS-1:0] data_line_r;

    logic [ICACHE_INDEX_BITS-1:0] if_index;
    logic [ICACHE_INDEX_BITS-1:0] req_index;
    logic [ICACHE_TAG_BITS-1:0] req_tag;
    logic [ICACHE_WORD_INDEX_BITS-1:0] req_word_index;
    logic req_hit;
    logic resp_valid;
    logic req_miss;

    assign if_index = if_addr[ICACHE_OFFSET_BITS + ICACHE_INDEX_BITS - 1
                             : ICACHE_OFFSET_BITS];
    assign req_word_index = req_addr[ICACHE_OFFSET_BITS-1:2];
    assign req_index = req_addr[ICACHE_OFFSET_BITS + ICACHE_INDEX_BITS - 1
                               : ICACHE_OFFSET_BITS];
    assign req_tag = req_addr[31:ICACHE_OFFSET_BITS + ICACHE_INDEX_BITS];

    assign req_hit = cache_valid[req_index] && (cache_tag[req_index] == req_tag);
    assign resp_valid = req_valid && req_hit && !miss_wait;
    assign req_miss = req_valid && !req_hit && !miss_wait;

    assign if_valid = resp_valid;
    assign if_rdata = resp_valid ? data_line_r[req_word_index*32 +: 32] : 32'b0;
    assign if_ready = !miss_wait && (!req_valid || resp_valid);

    assign imem_en = req_miss;
    assign imem_addr = req_miss ? {req_addr[31:ICACHE_OFFSET_BITS],
                                   {ICACHE_OFFSET_BITS{1'b0}}} : 32'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            req_valid <= 1'b0;
            req_addr <= 32'b0;
            miss_wait <= 1'b0;
            data_line_r <= '0;
            for (i = 0; i < ICACHE_NUM_LINES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_tag[i] <= '0;
            end
        end else begin
            if (miss_wait) begin
                cache_data[req_index] <= imem_rdata;
                data_line_r <= imem_rdata;
                cache_valid[req_index] <= 1'b1;
                cache_tag[req_index] <= req_tag;
                miss_wait <= 1'b0;
            end else if (req_miss) begin
                miss_wait <= 1'b1;
            end

            if (resp_valid) begin
                req_valid <= 1'b0;
            end

            if (if_en && if_ready) begin
                req_valid <= 1'b1;
                req_addr <= if_addr;
                data_line_r <= cache_data[if_index];
            end
        end
    end

endmodule
