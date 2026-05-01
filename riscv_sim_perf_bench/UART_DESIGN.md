# UART 模块硬件设计参考

本文档说明了 `benchmark.c` 中 UART 驱动对硬件的期望，以及如何在你的 SoC 中实现一个兼容的 UART 模块。

## 1. 地址映射与寄存器布局

### 基地址与偏移

```
UART 基地址：0x80010000
```

| 偏移 | 地址         | 寄存器名 | 读/写 | 功能 |
|------|------------|---------|------|------|
| 0x0  | 0x80010000 | DATA    | R/W  | 收发缓冲区 |
| 0x4  | 0x80010004 | STATUS  | R    | 状态标志 |
| 0x8  | 0x80010008 | CTRL    | R/W  | 控制与中断 |
| 0xC  | 0x8001000C | BAUD    | W    | 波特率分频 |

---

## 2. 寄存器详细定义

### 2.1 DATA 寄存器 (0x0)

**访问**：读/写，通常与 FIFO 或简单缓冲区关联

**写操作**：
```c
*((volatile uint32_t *)0x80010000) = data;  // data[7:0] = 待发送字节
```
- 将 8 位数据推入**发送 FIFO**（或写入发送缓冲区）
- 硬件在发送缓冲区非空时启动串行移位，逐位输出到 `tx` 线
- bit[31:8] 通常被忽略

**读操作**：
```c
uint8_t data = *((volatile uint32_t *)0x80010000) & 0xFF;  // 读接收缓冲区
```
- 从**接收 FIFO**（或接收缓冲区）弹出最新字节
- 硬件在接收到 8 bit 数据后，自动将其入队
- bit[31:8] 通常为 0 或不定

---

### 2.2 STATUS 寄存器 (0x4)

**访问**：只读（或只读-清除）

**位定义**：

```c
#define STATUS_TX_EMPTY   (1 << 0)   // bit[0]
#define STATUS_RX_READY   (1 << 1)   // bit[1]
#define STATUS_TX_FULL    (1 << 2)   // bit[2]
#define STATUS_RX_FULL    (1 << 3)   // bit[3]
#define STATUS_TX_INT     (1 << 4)   // bit[4]
#define STATUS_RX_INT     (1 << 5)   // bit[5]
```

| 位 | 名称 | 含义 | 何时置 1 | 何时清 0 |
|----|------|------|---------|---------|
| 0  | TX_EMPTY | 发送缓冲区与移位寄存器都空 | 上次发送完毕 | 写入新数据到 DATA |
| 1  | RX_READY | 接收缓冲区非空，有数据可读 | 接收完 8 bit 数据 | 读取 DATA（弹出一字节） |
| 2  | TX_FULL  | 发送 FIFO 已满 | FIFO 满 | 硬件开始发送，FIFO 有空间 |
| 3  | RX_FULL  | 接收 FIFO 已满 | FIFO 满且新数据来临 | 读取 DATA |
| 4  | TX_INT   | 发送中断待处理 | TX_EMPTY 置 1 且 TX_INT_EN=1 | 写 CTRL[3]=1 或读取 DATA |
| 5  | RX_INT   | 接收中断待处理 | RX_READY 置 1 且 RX_INT_EN=1 | 写 CTRL[4]=1 或写 DATA |

**典型用法**：
```c
// 忙轮询发送：等待缓冲区空
while ((STATUS & TX_EMPTY_MASK) == 0);
*DATA = byte;

// 忙轮询接收：等待数据到达
while ((STATUS & RX_READY_MASK) == 0);
byte = *DATA;
```

---

### 2.3 CTRL 寄存器 (0x8)

**访问**：读/写

**位定义**：

```c
#define CTRL_EN           (1 << 0)   // bit[0]
#define CTRL_TX_INT_EN    (1 << 1)   // bit[1]
#define CTRL_RX_INT_EN    (1 << 2)   // bit[2]
#define CTRL_TX_INT_CLR   (1 << 3)   // bit[3], 写 1 清中断
#define CTRL_RX_INT_CLR   (1 << 4)   // bit[4], 写 1 清中断
```

| 位 | 名称 | 功能 | 初值建议 |
|----|------|------|---------|
| 0  | EN | 1 = UART 模块使能，0 = 关闭 | 1 |
| 1  | TX_INT_EN | 1 = 当 TX_EMPTY 置 1 时触发中断 | 1 |
| 2  | RX_INT_EN | 1 = 当 RX_READY 置 1 时触发中断 | 1 |
| 3  | TX_INT_CLR | 写 1 清除 STATUS[4] (TX_INT) | 0 |
| 4  | RX_INT_CLR | 写 1 清除 STATUS[5] (RX_INT) | 0 |
| [31:5] | 保留 | 不使用 | 0 |

**中断清除机制**（两种方式选一种）：
1. **自动清除**：读/写 DATA 时自动清除对应中断标志
2. **手动清除**：写 CTRL[3] 或 CTRL[4] 明确清除

**典型初化值**：
```c
*CTRL = 0x15;  // 0b10101 = CTRL[2:0] = 0b101 = RX_INT_EN + TX_INT_EN + EN
```

---

### 2.4 BAUD 寄存器 (0xC)

**访问**：写只 (W)

**用途**：设置波特率

**计算方法**：
```
DIV = CLK_FREQ_HZ / 期望波特率

例如：
  CLK = 50 MHz = 50,000,000 Hz
  期望波特率 = 115,200 bps
  DIV = 50,000,000 / 115,200 ≈ 434 (0x1B2)
```

**写入**：
```c
*BAUD = 434;   // 16 位分频值
```

**硬件内部实现**：
- 用 DIV 值分频 CLK 得到**采样时钟**（接收）与**波特率时钟**（发送）
- 接收侧：通常在波特率时钟的中点采样（过采样：DIV / 16）
- 发送侧：在波特率时钟边界切换串行位

---

## 3. 工作流程示例

### 3.1 初始化

```c
// 1. 设置波特率
*BAUD = 434;               // DIV = CLK_FREQ / 115200

// 2. 使能模块并启用中断
*CTRL = 0x15;              // EN | TX_INT_EN | RX_INT_EN
```

### 3.2 发送单字节（忙轮询）

```c
// 等待发送缓冲区空
while ((*STATUS & TX_EMPTY_MASK) == 0) {
    // 忙等待
}

// 写入待发送数据
*DATA = 0x41;              // 发送 'A'

// 硬件自动：
// 1. 将数据入队
// 2. 启动移位输出 (start bit + 8 data bits + stop bit)
// 3. 当移位寄存器空时，置 STATUS[TX_EMPTY] = 1
```

### 3.3 接收单字节（忙轮询）

```c
// 等待接收缓冲区有数据
while ((*STATUS & RX_READY_MASK) == 0) {
    // 忙等待
}

// 读取接收到的字节
uint8_t c = (uint8_t)(*DATA & 0xFF);

// 硬件自动：
// 1. 从接收 FIFO 弹出字节
// 2. 若 FIFO 还有数据，STATUS[RX_READY] 保持 1
// 3. 若 FIFO 为空，STATUS[RX_READY] = 0
```

### 3.4 中断驱动收发（选项）

```c
// 发送中断处理
void uart_tx_isr(void) {
    if (STATUS & TX_INT_FLAG) {
        if (tx_buffer_has_data()) {
            *DATA = tx_buffer_pop();
        }
        // 硬件自动清除或软件写 CTRL[3] = 1 清除
    }
}

// 接收中断处理
void uart_rx_isr(void) {
    if (STATUS & RX_INT_FLAG) {
        uint8_t c = (uint8_t)(*DATA & 0xFF);
        rx_buffer_push(c);
        // 硬件自动清除或软件写 CTRL[4] = 1 清除
    }
}
```

---

## 4. RTL 实现要点

### 4.1 最小实现（无 FIFO，单字节缓冲）

```verilog
// Pseudo-code
module uart_minimal (
    input  clk, rst_n,
    input  [31:0] addr, din,
    output [31:0] dout,
    input  we,
    
    input  rx_pin,
    output tx_pin
);

    // 发送缓冲区与移位寄存器
    reg [7:0] tx_data_reg;
    reg [9:0] tx_shift;          // start + 8 bits + stop
    reg tx_busy;
    reg tx_empty = 1;
    
    // 接收缓冲区与移位寄存器
    reg [7:0] rx_data_reg;
    reg [9:0] rx_shift;
    reg rx_busy;
    reg rx_ready = 0;
    
    // 控制寄存器
    reg [5:0] ctrl;              // CTRL 寄存器
    
    // 波特率时钟分频计数
    reg [15:0] baud_div;         // 分频值
    reg [15:0] baud_cnt;         // 分频计数
    wire baud_tick = (baud_cnt == 0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_empty <= 1;
            rx_ready <= 0;
            ctrl <= 0;
        end else begin
            // 波特率时钟
            if (baud_cnt == 0)
                baud_cnt <= baud_div;
            else
                baud_cnt <= baud_cnt - 1;
            
            // 发送 FSM
            if (!tx_busy && tx_empty) begin
                tx_pin <= 1;  // idle
            end else if (tx_busy && baud_tick) begin
                {tx_pin, tx_shift} <= {1'b1, tx_shift[9:1]};
                if (tx_shift == 10'h3FF) begin  // 一帧发完
                    tx_busy <= 0;
                    tx_empty <= 1;
                end
            end
            
            // 接收 FSM（类似）...
            
            // 寄存器写入
            if (we) begin
                case (addr[3:2])
                    2'h0: begin  // DATA
                        tx_data_reg <= din[7:0];
                        tx_shift <= {1'b1, din[7:0], 1'b0};  // stop + data + start
                        tx_busy <= 1;
                        tx_empty <= 0;
                    end
                    2'h2: baud_div <= din[15:0];  // BAUD
                    2'h3: ctrl <= din[5:0];       // CTRL
                endcase
            end
        end
    end
    
    // 寄存器读出
    always @(*) begin
        case (addr[3:2])
            2'h0: dout = {24'h0, rx_data_reg};  // DATA
            2'h1: dout = {26'h0, rx_ready, rx_full, tx_full, 1'b0, rx_ready, tx_empty};  // STATUS
            2'h2: dout = {26'h0, ctrl};          // CTRL
            2'h3: dout = 32'h0;                  // BAUD (write-only)
        endcase
    end
    
endmodule
```

### 4.2 改进点（含 FIFO）

- 添加收发 FIFO（例如 16 字节），提高吞吐
- 添加溢出、奇偶校验等状态标志
- 支持 8-bit、9-bit、甚至可变字长配置
- 可配置停止位、流控等

---

## 5. 与 benchmark.c 的对应关系

| C 代码 | UART 硬件动作 |
|-------|-------------|
| `uart_init(115200)` | 写 BAUD、CTRL，初化波特率与使能 |
| `uart_send(c)` 等待 | 轮询 STATUS[0] (TX_EMPTY) 到 1 |
| `uart_send(c)` 发送 | 写 DATA，硬件启动串行发送 |
| `uart_receive()` 等待 | 轮询 STATUS[1] (RX_READY) 到 1 |
| `uart_receive()` 接收 | 读 DATA，硬件弹出 FIFO |
| `mmio_read(STATUS)` | 实时反映 TX_EMPTY、RX_READY 等 |

---

## 6. 对标 benchmark.c 的适配清单

- [x] 地址 0x80010000 ~ 0x8001000C 四个寄存器
- [x] STATUS[0] = TX_EMPTY（发送缓冲区空）
- [x] STATUS[1] = RX_READY（接收缓冲区非空）
- [x] CTRL[0] = EN（模块使能）
- [x] CTRL[1:2] = TX_INT_EN / RX_INT_EN（中断使能）
- [x] BAUD 分频配置
- [x] DATA 收发缓冲区读写
- [x] 串行线：`rx_pin`、`tx_pin`

---

## 7. 仿真/验证建议

1. **单元测试**：先验证寄存器读写，再验证串行收发
2. **波形观察**：观察 `tx_pin`、`rx_pin`、`baud_cnt` 等信号
3. **性能指标**：
   - 发送一字节耗时：约 (1 + 8 + 1) * DIV / CLK ≈ 870ns @115200 bps
   - 接收延迟：从 RX pin 变化到 RX_READY=1 的延迟
4. **集成测试**：接上 benchmark.c，观察 UART 输出是否符合预期

---

## 附录：地址映射修改

若你的 SoC 映射不同，只需修改 `benchmark.c` 里的：

```c
#define UART_BASE_ADDR   0x80010000u  // 改成你的 UART 基地址
#define CLK_FREQ_HZ      50000000u     // 改成你的系统时钟
```

相应的硬件寄存器布局应保持上述表格一致，以确保驱动兼容。
