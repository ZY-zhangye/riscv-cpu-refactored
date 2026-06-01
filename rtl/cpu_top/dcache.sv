`include "defines.svh"

//==============================================================================
// 模块名: dcache
// 说明  : 直接映射、阻塞式数据 Cache。
//
// CPU 侧协议:
//   cpu_req_ready=1 且 cpu_req_valid=1 时接收一条访存请求。
//   cache 数据体采用同步读 RAM 模板，命中 load 在请求后一拍返回。
//
// 后端协议:
//   miss 时由本模块连续读取 4 个 word 组成 16B line。
//   store 采用 write-through：命中时更新 cache，同时写到后端。
//   MMIO/PLIC 等非 cacheable 区域不进入 cache，走注册化直通路径。
//==============================================================================
module dcache (
    input  logic        clk,
    input  logic        rst_n,

    // CPU/MEM阶段接口
    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [3:0]  cpu_req_wen,
    output logic        cpu_resp_valid,
    output logic [31:0] cpu_resp_rdata,

    // 后端数据总线接口
    input  logic [31:0] mem_rdata,
    output logic [31:0] mem_addr,
    output logic [3:0]  mem_wen,
    output logic        mem_en,
    output logic [31:0] mem_wdata
);

    localparam DCACHE_NUM_LINES       = `DCACHE_SIZE / `DCACHE_LINE_SIZE;
    localparam DCACHE_INDEX_BITS      = $clog2(DCACHE_NUM_LINES);
    localparam DCACHE_OFFSET_BITS     = $clog2(`DCACHE_LINE_SIZE);
    localparam DCACHE_TAG_BITS        = 32 - DCACHE_INDEX_BITS - DCACHE_OFFSET_BITS;
    localparam DCACHE_WORDS_PER_LINE  = `DCACHE_LINE_SIZE / 4;
    localparam DCACHE_WORD_INDEX_BITS = $clog2(DCACHE_WORDS_PER_LINE);
    localparam DCACHE_LINE_BITS       = `DCACHE_LINE_SIZE * 8;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOOKUP,
        ST_MISS_ISSUE,
        ST_MISS_WAIT,
        ST_MISS_FILL,
        ST_STORE_ISSUE,
        ST_STORE_RESP,
        ST_BYPASS_ISSUE,
        ST_BYPASS_WAIT,
        ST_BYPASS_RESP
    } state_t;

    state_t state;

    logic cache_valid [DCACHE_NUM_LINES-1:0];
    logic [DCACHE_TAG_BITS-1:0] cache_tag [DCACHE_NUM_LINES-1:0];

    // data RAM 不在 reset 时清零，只通过 valid 位判断内容是否有效。
    // 同步读、整行写的结构更贴近 FPGA BRAM 推断模板。
    (* ram_style = "block" *)
    logic [DCACHE_LINE_BITS-1:0] cache_data [DCACHE_NUM_LINES-1:0];

    logic req_valid;
    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0] req_wen;
    logic bypass_rdata;
    logic [31:0] bypass_data;
    logic [DCACHE_WORD_INDEX_BITS-1:0] fill_word_index;
    logic [31:0] fill_data [DCACHE_WORDS_PER_LINE-1:0];
    logic [DCACHE_LINE_BITS-1:0] data_line_r;
    logic [DCACHE_LINE_BITS-1:0] fill_line;
    logic [DCACHE_LINE_BITS-1:0] store_line;

    logic [DCACHE_INDEX_BITS-1:0] cpu_req_index;
    logic [DCACHE_INDEX_BITS-1:0] req_index;
    logic [DCACHE_TAG_BITS-1:0] req_tag;
    logic [DCACHE_WORD_INDEX_BITS-1:0] req_word_index;
    logic req_write;
    logic req_cacheable;
    logic req_hit;
    logic [31:0] line_base_addr;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_data,
        input logic [31:0] new_data,
        input logic [3:0]  wstrb
    );
        begin
            apply_wstrb = old_data;
            if (wstrb[0]) begin
                apply_wstrb[7:0] = new_data[7:0];
            end
            if (wstrb[1]) begin
                apply_wstrb[15:8] = new_data[15:8];
            end
            if (wstrb[2]) begin
                apply_wstrb[23:16] = new_data[23:16];
            end
            if (wstrb[3]) begin
                apply_wstrb[31:24] = new_data[31:24];
            end
        end
    endfunction

    function automatic logic is_cacheable_addr(input logic [31:0] addr);
        begin
            is_cacheable_addr = (addr[31:28] == 4'h6) ||
                                (addr[31:16] == 16'h8000) ||
                                ((addr >= 32'h8010_0000) &&
                                 (addr <= 32'h8013_FFFF));
        end
    endfunction

    assign cpu_req_index = cpu_req_addr[DCACHE_OFFSET_BITS + DCACHE_INDEX_BITS - 1
                                       : DCACHE_OFFSET_BITS];
    assign req_word_index = req_addr[DCACHE_OFFSET_BITS-1:2];
    assign req_index = req_addr[DCACHE_OFFSET_BITS + DCACHE_INDEX_BITS - 1
                               : DCACHE_OFFSET_BITS];
    assign req_tag = req_addr[31:DCACHE_OFFSET_BITS + DCACHE_INDEX_BITS];
    assign req_write = req_wen != 4'b0000;
    assign req_cacheable = is_cacheable_addr(req_addr);
    assign req_hit = req_cacheable && cache_valid[req_index] &&
                     (cache_tag[req_index] == req_tag);
    assign line_base_addr = {req_addr[31:DCACHE_OFFSET_BITS],
                             {DCACHE_OFFSET_BITS{1'b0}}};

    always_comb begin
        integer k;

        fill_line = '0;
        for (k = 0; k < DCACHE_WORDS_PER_LINE; k = k + 1) begin
            fill_line[k*32 +: 32] = fill_data[k];
        end

        store_line = data_line_r;
        store_line[req_word_index*32 +: 32] =
            apply_wstrb(data_line_r[req_word_index*32 +: 32],
                        req_wdata,
                        req_wen);
    end

    assign cpu_req_ready = (state == ST_IDLE);
    assign cpu_resp_valid = ((state == ST_LOOKUP) && req_valid && !req_write &&
                             req_cacheable && req_hit) ||
                            (state == ST_STORE_RESP) ||
                            (state == ST_BYPASS_RESP);
    assign cpu_resp_rdata = ((state == ST_LOOKUP) && req_valid && !req_write &&
                             req_cacheable && req_hit) ?
                            data_line_r[req_word_index*32 +: 32] :
                            bypass_data;

    always_comb begin
        mem_en = 1'b0;
        mem_addr = 32'b0;
        mem_wen = 4'b0000;
        mem_wdata = 32'b0;

        unique case (state)
            ST_MISS_ISSUE: begin
                mem_en = 1'b1;
                mem_addr = line_base_addr + {fill_word_index, 2'b00};
            end

            ST_STORE_ISSUE: begin
                mem_en = 1'b1;
                mem_addr = req_addr;
                mem_wen = req_wen;
                mem_wdata = req_wdata;
            end

            ST_BYPASS_ISSUE: begin
                mem_en = 1'b1;
                mem_addr = req_addr;
                mem_wen = req_wen;
                mem_wdata = req_wdata;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        integer i;
        integer j;
        if (!rst_n) begin
            state <= ST_IDLE;
            req_valid <= 1'b0;
            req_addr <= 32'b0;
            req_wdata <= 32'b0;
            req_wen <= 4'b0000;
            bypass_rdata <= 1'b0;
            bypass_data <= 32'b0;
            fill_word_index <= '0;
            data_line_r <= '0;
            for (i = 0; i < DCACHE_NUM_LINES; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_tag[i] <= '0;
            end
            for (j = 0; j < DCACHE_WORDS_PER_LINE; j = j + 1) begin
                fill_data[j] <= 32'b0;
            end
        end else begin
            unique case (state)
                ST_IDLE: begin
                    if (cpu_req_valid) begin
                        req_valid <= 1'b1;
                        req_addr <= cpu_req_addr;
                        req_wdata <= cpu_req_wdata;
                        req_wen <= cpu_req_wen;
                        data_line_r <= cache_data[cpu_req_index];
                        state <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    if (req_write) begin
                        if (req_hit) begin
                            cache_data[req_index] <= store_line;
                            data_line_r <= store_line;
                        end
                        state <= req_cacheable ? ST_STORE_ISSUE : ST_BYPASS_ISSUE;
                    end else if (req_cacheable && req_hit) begin
                        state <= ST_IDLE;
                        req_valid <= 1'b0;
                    end else if (req_cacheable) begin
                        fill_word_index <= '0;
                        state <= ST_MISS_ISSUE;
                    end else begin
                        state <= ST_BYPASS_ISSUE;
                    end
                end

                ST_MISS_ISSUE: begin
                    state <= ST_MISS_WAIT;
                end

                ST_MISS_WAIT: begin
                    fill_data[fill_word_index] <= mem_rdata;
                    if (fill_word_index == DCACHE_WORDS_PER_LINE - 1) begin
                        state <= ST_MISS_FILL;
                    end else begin
                        fill_word_index <= fill_word_index + 1'b1;
                        state <= ST_MISS_ISSUE;
                    end
                end

                ST_MISS_FILL: begin
                    cache_data[req_index] <= fill_line;
                    data_line_r <= fill_line;
                    cache_valid[req_index] <= 1'b1;
                    cache_tag[req_index] <= req_tag;
                    state <= ST_LOOKUP;
                end

                ST_STORE_ISSUE: begin
                    state <= ST_STORE_RESP;
                end

                ST_STORE_RESP: begin
                    state <= ST_IDLE;
                    req_valid <= 1'b0;
                    bypass_data <= 32'b0;
                end

                ST_BYPASS_ISSUE: begin
                    bypass_rdata <= !req_write;
                    state <= ST_BYPASS_WAIT;
                end

                ST_BYPASS_WAIT: begin
                    bypass_data <= bypass_rdata ? mem_rdata : 32'b0;
                    state <= ST_BYPASS_RESP;
                end

                ST_BYPASS_RESP: begin
                    state <= ST_IDLE;
                    req_valid <= 1'b0;
                end

                default: begin
                    state <= ST_IDLE;
                    req_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
