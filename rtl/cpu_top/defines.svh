`ifndef __DEFINES_SVH__
`define __DEFINES_SVH__

// This file contains all the defines used in the CPU design. It is included in all the files in the design.
//定义位宽
`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define MTVAL_WIDTH 32
`define FS_DS_WIDTH (32+32)
`define EXC_WIDTH (7+32)

`define ALU_PACKET_WIDTH 10
`define FPU_PACKET_WIDTH (32+32+26+3+2+2+2)
`define MUL_PACKET_WIDTH (4+1+1)
`define MEM_PACKET_WIDTH (32+5+1)
`define CSR_PACKET_WIDTH (32+32+12+3+1+1+1)
`define CTRL_PACKET_WIDTH (32+3+6+5+3)
`define BR_JMP_PACKET_WIDTH (32+6+2)
`define SRC_PACKET_WIDTH (32+32+2+2)
`define DS_ES_WIDTH (`ALU_PACKET_WIDTH + `FPU_PACKET_WIDTH + `MUL_PACKET_WIDTH + `MEM_PACKET_WIDTH + `CSR_PACKET_WIDTH + `CTRL_PACKET_WIDTH + `BR_JMP_PACKET_WIDTH + `SRC_PACKET_WIDTH)

`define ES_MS_WIDTH (32+32+6+1+1+3+1+12+32)
`define ALU_OP_ADD 10'b10_0000_0000
`define ALU_OP_SUB 10'b01_0000_0000
`define ALU_OP_AND 10'b00_1000_0000
`define ALU_OP_OR  10'b00_0100_0000
`define ALU_OP_XOR 10'b00_0010_0000
`define ALU_OP_SLL 10'b00_0001_0000
`define ALU_OP_SRL 10'b00_0000_1000
`define ALU_OP_SRA 10'b00_0000_0100
`define ALU_OP_SLT 10'b00_0000_0010
`define ALU_OP_SLTU 10'b00_0000_0001
`define EXE_EXC_BUS (33+`EXC_WIDTH)

`define MS_WS_WIDTH (32+32+5+1+1)
`define LB 6'b10_0000
`define LH 6'b01_0000
`define LW 6'b00_1000
`define LBU 6'b00_0100
`define LHU 6'b00_0010
`define SW 6'b00_1001
`define SH 6'b01_0001
`define SB 6'b10_0001
`define EXC_NONE 7'b000_0000
`define EXC_IAM 7'b010_0000
`define EXC_LAM 7'b010_0100
`define EXC_SAM 7'b010_0110

`define CSR_MSTATUS 12'h300
`define CSR_MISA 12'h301
`define CSR_MTVEC 12'h305
`define CSR_MEPC 12'h341
`define CSR_MCAUSE 12'h342
`define CSR_MHARTID 12'hF14
`define CSR_MIE 12'h304
`define CSR_MIP 12'h344
`define CSR_MTVAL 12'h343
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID 12'hF12
`define CSR_MIMPID 12'hF13
`define CSR_MSCRATCH 12'h340

//debug端口开启与否，注释掉为关闭
`define DEBUG_EN 1'b1



`define NOP_INST 32'h0000_0013
`define MUL_MULTICYCLE_ENABLE 1'b0   //是否采用多周期乘法运算，1为多周期，0为单周期
`define MULTICYCLE_ENABLE 1'b0   //是否采用多周期运算（如除法），1为多周期，0为单周期


//定义地址信息
`define PC_START 32'h0000_0000

`endif