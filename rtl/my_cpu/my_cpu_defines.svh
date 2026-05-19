`ifndef _MY_CPU_DEFINES_SVH
`define _MY_CPU_DEFINES_SVH

// 定义SOC级封装使用的宏和参数
// 定义PLIC相关的参数
`define PLIC_NUM_INTERRUPTS 32 // PLIC支持的最大中断数
`define PLIC_PRIORITY_BASE_ADDR 32'h8030_0000 // PLIC优先级寄存器基地址
`define PLIC_PENDING_BASE_ADDR 32'h8030_1000 // PLIC待处理寄存器基地址
`define PLIC_ENABLE_BASE_ADDR 32'h8030_2000 // PLIC使能寄存器基地址
`define PLIC_THRESHOLD_BASE_ADDR 32'h8030_4000 // PLIC阈值寄存器基地址
`define PLIC_CLAIM_BASE_ADDR 32'h8030_4004 // PLIC请求寄存器基地址
`define PLIC_IN_SERVICE_BASE_ADDR 32'h8030_5000 // PLIC处理中寄存器基地址
`define ID_WIDTH 5 // 中断ID宽度，支持最多32个中断
`define PRIORITY_WIDTH 3 // 优先级宽度，支持8级优先级

// PLIC中断号定义，0号中断保留不用
`define MY_CPU_TIMER_INT_ID   1
`define MY_CPU_UART_RX_INT_ID 2
`define MY_CPU_UART_TX_INT_ID 3

// UART寄存器地址以及相关含义
// 使用MY_CPU_前缀避免和rtl/cpu_top/defines.svh中的UART_BASE_ADDR重名
`define MY_CPU_UART_BASE_ADDR 32'h8001_0000
`define UART_RT_DATA   16'h0000 // UART数据寄存器地址
`define UART_RT_STATUS 16'h0004 // UART状态寄存器地址
`define UART_RT_CTRL   16'h0008 // UART控制寄存器地址
`define UART_RT_BAUD   16'h000C // UART波特率寄存器地址

// 定时器寄存器地址以及相关含义
`define MY_CPU_TIMER_BASE_ADDR 32'h8002_0000
`define TIMER_LOAD      16'h0000 // 定时器装载寄存器地址
`define TIMER_VALUE     16'h0004 // 定时器当前值寄存器地址，只读
`define TIMER_CTRL      16'h0008 // 定时器控制寄存器地址
`define TIMER_INTCLR    16'h000C // 定时器中断清除寄存器地址，写1清除中断
`define TIMER_PRESCALER 16'h0010 // 定时器预分频寄存器地址

// 其它简单MMIO基地址
`define MY_CPU_LEDS_BASE_ADDR 32'h8003_0000

`endif // _MY_CPU_DEFINES_SVH
