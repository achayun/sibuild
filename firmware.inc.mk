# sibuild: cross-compilation (firmware) scaffolding.
#
# Set up a cross compile toolchain (from CROSS_COMPILE) and adds the firmware
# artifact pipeline: an .elf and derivatives.
# Also prefills common firmware flags: LTO, dead-code elimination, and a flash/RAM usage report.
#
# Policy like: -std, optimization level, startup files and the arch flags are the project's choice.
#   CROSS_COMPILE - the cross toolchain path and prefix. For example:
#                   On PATH:    riscv64-unknown-elf-
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
# Use LTO aware AR for .a files
AR      := $(CROSS_COMPILE)gcc-ar

include $(SIBUILD_DIR)/ccxx.inc.mk

# Firmware defaults LTO plus unreachable code elimination keep images small,
# and the linker reports flash/RAM usage.
# Override per target (e.g. CPPFLAGS += -fno-lto for debugging).
CPPFLAGS += -flto -ffunction-sections -fdata-sections
LDFLAGS  += -flto -Wl,--gc-sections -Wl,--print-memory-usage

# Reproducible LTO build. GCC only
# -frandom-seed - a stable seed for the private symbol names (foo.lto_priv.<seed>) and the
#     .gnu.lto_* section names, in place of the one GCC derives from the clock and the pid.
#     Without it an LTO build differs from itself run to run.
# LLVM is deterministic without it.
gcc_random_seed = $(if $(CC_IS_CLANG),,-frandom-seed=$(call rel,$@))

CPPFLAGS += $(gcc_random_seed)
LDFLAGS  += $(gcc_random_seed)

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

# Linker scripts templated through C preprocessor Lets a .ld.in #include headers and use macros
$(BUILD_DIR)/%.ld: $(PROJ_DIR)/%.ld.in
	$(call build_cmd,LD-CPP,$@,$(CC) $(CPPFLAGS) -E -P -x c -o $@ $<)

# Links with $(LINK) - the C compiler by default; set LINK := $(CXX) for C++
$(BUILD_DIR)/%.elf: $$(LIBS)
	$(call build_cmd,LD,$@,$(LINK) $(LDFLAGS) $(INC) -o $@ $(filter-out %.a,$^) -Xlinker -Map=$@.map $(call group_libs,$(filter %.a,$^) $(SYS_LIBS_LDFLAGS)))

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(call build_cmd,BIN,$@,$(OBJCOPY) -O binary $< $@)

$(BUILD_DIR)/%.dis: $(BUILD_DIR)/%.elf
	$(call build_cmd,DIS,$@,$(OD) -DCSsx --visualize-jumps $< > $@)

# Intel HEX — the standard firmware/flashing format
$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	$(call build_cmd,HEX,$@,$(OBJCOPY) -O ihex $< $@)

endif # ifeq "$(origin firmware_inc_mk)" "undefined"
