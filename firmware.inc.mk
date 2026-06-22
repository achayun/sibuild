# sibuild: cross-compilation (firmware) scaffolding.
#
# Set up a cross compile toolchain (from CROSS_COMPILE) and adds the firmware
# artifact pipeline: an .elf and derivatives.
# Also prefills common firmware flags: LTO, dead-code elimination, and a flash/RAM usage report.
#
# Policy like: -std, optimization level, startup files and the arch flags are the project's choice.
#   CROSS_COMPILE - the cross toolchain prefix.
#                   On PATH:    riscv64-unknown-elf-   (tools found via PATH)
#                   Off PATH:   /opt/riscv/bin/riscv64-unknown-elf-
ifeq "$(origin firmware_inc_mk)" "undefined"
firmware_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif

CC      := $(CROSS_COMPILE)gcc
GCC     := $(CROSS_COMPILE)gcc
CXX     := $(CROSS_COMPILE)g++
LD      := $(CROSS_COMPILE)ld
RE      := $(CROSS_COMPILE)readelf
OBJCOPY := $(CROSS_COMPILE)objcopy
OD      := $(CROSS_COMPILE)objdump
AR      := $(CROSS_COMPILE)gcc-ar

include $(SIBUILD_DIR)/ccxx.inc.mk

# Firmware defaults, works across very different targets (e.g. RISC-V rv64 and AVR atmega):
# LTO plus unreachable code elimination keep images small, and the linker reports flash/RAM usage.
# Override in the project (e.g. CPPFLAGS += -fno-lto for debugging).
# AR is gcc-ar (above) intentionally so archives of LTO objects link correctly.
CPPFLAGS += -flto -ffunction-sections -fdata-sections
LDFLAGS  += -flto -Wl,--gc-sections -Wl,--print-memory-usage

# Project arch flags (e.g. -march, -mcpu) are best scoped to the
# targets they apply to rather than appended globally.
# Bind to specific target or use`%`-pattern to scope a whole family:
#   $(BUILD_DIR)/foo_%.elf: CPPFLAGS += $(FOO_ARCH_FLAGS)
#   $(BUILD_DIR)/foo_%.elf: LDFLAGS  += -T $(FOO_LINKER_SCRIPT)

# Implicit firmware rules:
# Note: this file must be included *before* declaring targets:
# ```
#   include $(SIBUILD_DIR)/firmware.inc.mk
#   ...
#   $(BUILD_DIR)/foo.elf: $(call src_to_obj,$(FW_SRC))
# ```
# Why? Make expands $(BUILD_DIR) and $(call src_to_obj,...) at *parse* time, this is NOT
# about rule order: Make reads every rule before building.

# Links with $(LINK) - the C compiler by default; set LINK := $(CXX) for C++
$(BUILD_DIR)/%.elf: $$(LIBS)
	$(call run_cmd,LD,$@,$(LINK) $(LDFLAGS) $(INC) -o $@ $(filter-out %.a,$^) -Xlinker -Map=$@.map $(call group_libs,$(filter %.a,$^) $(SYS_LIBS_LDFLAGS)))

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(call run_cmd,BIN,$@,$(OBJCOPY) -O binary $< $@)

$(BUILD_DIR)/%.dis: $(BUILD_DIR)/%.elf
	$(call run_cmd,DIS,$@,$(OD) -DCSsx --visualize-jumps $< > $@)

# Intel HEX — the standard firmware/flashing format
$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	$(call run_cmd,HEX,$@,$(OBJCOPY) -O ihex $< $@)

endif # ifeq "$(origin firmware_inc_mk)" "undefined"
