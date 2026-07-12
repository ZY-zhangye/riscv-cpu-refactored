# MEM 异常控制路径打拍检查点

## 路径定位

175 MHz quick synth 的最差路径均从：

```text
u_mem_stage0/es_ms_bus_r_reg[90]/C
```

bit 90 对应 `ES_MS` 打包中的 `load_inst[0]`，即 `is_store`，不是除法数据位。它在 MEM 中参与未对齐 store 异常判断，随后经 `exception_code[5]` 扇出到 IF/RAS、issue queue CE 和全局 allowin/flush 控制。

## RTL 修改

文件：`rtl/cpu_top/mem_stage.sv`

- 在 EX→MEM packet 进入 MEM 时，预先计算并锁存 `exception_iam/lam/sam`；
- 普通 MEM 寄存器和 skid buffer 分别携带三个位，保证反压期间异常年龄和数据一致；
- MEM 后级只使用 `exception_*_r`，不再从 `es_ms_bus_r` 的 `load_inst` 位重新解码；
- 异常仍在原有 MEM 周期生效，没有增加 trap 延迟，也没有改变 oldest-first、commit_kill 或 `mepc/mtval` 语义。

## 验证

- RTL 编译：Errors 0、Warnings 0；
- `tb_mul_special`：通过；
- `tb_mem_commit`：通过；
- `tb_multi_issue_l2`：通过；
- `tb_multi_issue_l3`：通过，29 cycles、34 instret。

## 外部综合检查

重新综合后重点确认：

1. `es_ms_bus_r_reg[90] -> ras_spec_count/queue* CE` 路径是否退出前 20；
2. 新路径是否变为 `mem_stage/exception_*_r/Q -> exception_code/flush`；
3. `exception_*_r` 的 D 端只连接局部 EX→MEM 输入，不再把 MEM payload 位直接扇出到全局控制；
4. store/load misaligned、lane1 exception 和 `mret` 的功能回归无变化。
