RISCV_GCC ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY ?= riscv64-unknown-elf-objcopy
RISCV_OBJDUMP ?= riscv64-unknown-elf-objdump
DEPTH ?= 1024

TARGET := sim_perf_bench
BUILD_DIR := build
OUT_DIR := out

SRC_C := benchmark.c
SRC_S := startup.S
ELF := $(BUILD_DIR)/$(TARGET).elf
DUMP := $(OUT_DIR)/$(TARGET).dump
INST_BIN := $(BUILD_DIR)/inst.bin
DATA_BIN := $(BUILD_DIR)/data.bin
INST_HEX := $(OUT_DIR)/inst.hex
DATA_HEX := $(OUT_DIR)/data.hex
INST_COE := $(OUT_DIR)/inst.coe
DATA_COE := $(OUT_DIR)/data.coe

CFLAGS := -O2 -Wall -Wextra -ffunction-sections -fdata-sections \
		  -march=rv32i_zicsr -mabi=ilp32 -nostartfiles
LDFLAGS := -Wl,-Tlinker.ld,--gc-sections

.PHONY: all clean

all: $(ELF) $(DUMP) $(INST_HEX) $(DATA_HEX) $(INST_COE) $(DATA_COE)

$(BUILD_DIR) $(OUT_DIR):
	mkdir -p $@

$(ELF): $(SRC_C) $(SRC_S) linker.ld | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) $(SRC_C) $(SRC_S) $(LDFLAGS) -o $@

$(DUMP): $(ELF) | $(OUT_DIR)
	$(RISCV_OBJDUMP) -D $< > $@

$(INST_BIN): $(ELF) | $(BUILD_DIR)
	$(RISCV_OBJCOPY) --only-section=.text -O binary $< $@

$(DATA_BIN): $(ELF) | $(BUILD_DIR)
	$(RISCV_OBJCOPY) --only-section=.data --only-section=.rodata --only-section=.bss -O binary $< $@

# 纯 HEX：每行一个 32-bit word（8位十六进制），按小端字节重排后输出
$(INST_HEX): $(INST_BIN) | $(OUT_DIR)
	if [ ! -s $< ]; then \
		awk 'BEGIN{for(i=0;i<$(DEPTH);i++) print "00000000";}' > $@; \
	else \
		xxd -p -c 4 $< | awk 'length($$0)==8{print toupper(substr($$0,7,2) substr($$0,5,2) substr($$0,3,2) substr($$0,1,2))}' | \
		awk 'BEGIN{n=0} {print; n++} END{for(i=n;i<$(DEPTH);i++) print "00000000";}' > $@; \
	fi

$(DATA_HEX): $(DATA_BIN) | $(OUT_DIR)
	if [ ! -s $< ]; then \
		awk 'BEGIN{for(i=0;i<$(DEPTH);i++) print "00000000";}' > $@; \
	else \
		xxd -p -c 4 $< | awk 'length($$0)==8{print toupper(substr($$0,7,2) substr($$0,5,2) substr($$0,3,2) substr($$0,1,2))}' | \
		awk 'BEGIN{n=0} {print; n++} END{for(i=n;i<$(DEPTH);i++) print "00000000";}' > $@; \
	fi

# COE：与 HEX 一一对应，便于 FPGA/仿真初始化加载
$(INST_COE): $(INST_HEX) | $(OUT_DIR)
	awk 'BEGIN{print "memory_initialization_radix=16;"; print "memory_initialization_vector=";} \
	{ if (NR < $(DEPTH)) printf "%s,\n", $$1; else printf "%s;\n", $$1; }' $< > $@

$(DATA_COE): $(DATA_HEX) | $(OUT_DIR)
	awk 'BEGIN{print "memory_initialization_radix=16;"; print "memory_initialization_vector=";} \
	{ if (NR < $(DEPTH)) printf "%s,\n", $$1; else printf "%s;\n", $$1; }' $< > $@

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)
