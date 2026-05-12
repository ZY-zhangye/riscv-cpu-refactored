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

`endif // _MY_CPU_DEFINES_SVH