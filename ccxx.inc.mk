# sibuild: C/C++ tool definitions, default flags and implicit build rules. Platform agnostic.
ifeq "$(origin ccxx_inc_mk)" "undefined"
ccxx_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/build.inc.mk

# Global variable lists a project appends to:
# * INC_DIRS - Include directories, converted to -I<entry>
# * LIBS     - Libraries (.a files) linked into every final target
# * SYS_LIBS - External library names (e.g. 'm'), converted to -lm
# * CPPFLAGS - C pre-processor flags. Passed to both C and C++ targets
# * CFLAGS   - Flags passed to C targets only
# * CXXFLAGS - Flags passed to C++ targets only
# * ASMFLAGS - Flags passed to assembly (.S) targets
# * LDFLAGS  - Flags passed to the linker
#
# *Note*: Prefer target-specific and pattern-specific variable values over changing the global variables.
# A global `CFLAGS += ...` applies the flag to EVERY object in the build.
# This behavior should be reserved for genuine project-wide policy (e.g. -std, -O2).
# A flag that should effect a single target belongs on that target, as a target-specific value:
#   $(BUILD_DIR)/app.out: CPPFLAGS += -DCONFIG_DIR='"..."'   # this target and its objects only
# Make applies the value to the target and everything it depends on (the rules below read these
# variables when compiling each object),
# A `%`-pattern scopes a whole family the same way:
#   $(BUILD_DIR)/test_%.out: CPPFLAGS += -DTESTING
# Caveat: every source compiles to ONE object under BUILD_DIR, so a source shared by two targets
# that want different per-target flags is compiled once, with whichever target is reached first.
LIBS     ?=
INC_DIRS ?=
SYS_LIBS ?=
CPPFLAGS ?=
CFLAGS   ?=
CXXFLAGS ?=
ASMFLAGS ?=
LDFLAGS  ?=

# Default tools. 'cc'/'c++' resolve to the system compiler (clang on macOS, gcc on Linux).
# Pinned here: --no-builtin-variables suppresses Make's defaults at recipe-expansion time,
# but plain ?= skip the assignment (a recipe would then see an empty CC). Conditional assign
# allows override by cross-toolchain file, or a command-line 'make CC=...
ifneq ($(filter default undefined,$(origin CC)),)
CC := cc
endif
ifneq ($(filter default undefined,$(origin CXX)),)
CXX := c++
endif
ifneq ($(filter default undefined,$(origin AR)),)
# Use plain ar by default. For an LTO aware archive, override (e.g. gcc-ar, llvm-ar).
AR := ar
endif

# Use compiler driver to link (not ld). Defaults to the C compiler; set to $(CXX) for C++ targets
LINK ?= $(CC)

# Get the compiler version from banner, uses lazy evaluation to allow cross compile setup
CC_VERSION = $(shell $(CC) --version)
CC_IS_CLANG = $(findstring clang,$(CC_VERSION))

# Warning set. Shared C/C++ warnings go in CPPFLAGS.
# Why not exported? The per-phase sub-makes re-parse this Makefile, exporting
# variable would double it across the recursive build.
CPPFLAGS += -Warray-bounds -Wall -Wextra -Wshadow -Wunused -Werror=return-type -Wimplicit-fallthrough -Wwrite-strings -Wno-comment -Wno-address-of-packed-member -Wno-missing-braces -Wmissing-declarations
CFLAGS   += -Werror=implicit-function-declaration -Wstrict-prototypes -Wmissing-prototypes
CFLAGS += $(if $(CC_IS_CLANG), -Wzero-length-array, -Wzero-length-bounds)

# Accept modern C conventions by default: fixed-width integers (uint8_t ...),
# size_t/NULL and bool. All three are freestanding headers that compilers provide
# even for bare-metal toolchains with no libc, so this works for firmware too.
# (Note: stdint.h, not the hosted inttypes.h, to stay freestanding-safe.)
CFLAGS += -include stdint.h -include stddef.h -include stdbool.h

# Include dirs may be project-relative or absolute (see at_proj).
INC = $(addprefix -I,$(sort $(call at_proj,$(INC_DIRS))))

# Header dependencies (see http://make.paulandlesley.org/autodep.html)
CPPFLAGS += -MMD -MP
-include $(shell [ -d $(BUILD_DIR) ] && find $(BUILD_DIR) -type 'f' -name '*.d')

# Group sorted libraries together to remove duplicates.
# For GNU ld: whole-archive + a link group resolves circular dependencies
# clangd does not require such flags
GNU_LD_GROUP = -Wl,--whole-archive -Wl,--start-group $(1) -Wl,--end-group -Wl,--no-whole-archive

group_libs = $(if $(CC_IS_CLANG),\
	$(sort $(1)),\
	$(call GNU_LD_GROUP,$(sort $(1))))

# Shorthand to map source files to their object files in BUILD_DIR.
# Objects are compiled to BUILD_DIR path mirroring the source path relative to PROJ_DIR.
# The .o suffix is appended (rather than rewritten) so that:
#   a. The structure preserves the original path for anchored pattern matching targets.
#   b. Two files with the same name (e.g. start.S, start.c) or in different folders can coexist.
define src_to_obj
$(call to_build_target,.o,$(1))
endef

# Add '-l' to all system library dependencies, removing duplicates.
SYS_LIBS_LDFLAGS += $(addprefix -l, $(sort $(SYS_LIBS)))


# Reproducible build: -ffile-prefix-map rewrites the $(PROJ_DIR) prefix to `.` so __FILE__,
# and anything else derived from the source path is relative.
CPPFLAGS += -ffile-prefix-map=$(PROJ_DIR)=.

# LIBS (and any per-target library prerequisites) are linked into final targets by the rules below.
# A project appends to LIBS *after* including this file, so link rules use secondary expansion ($$)
# to read LIBS at build time rather than parse time. This is non-obvious. To understand see:
# https://www.tack.ch/gnu/make-3.82/make_20.html (invisible unless a filename literally needs a '$')
.SECONDEXPANSION:

# Libraries listed in LIBS build before any final target.
collect_objects:: $$(LIBS)

# Implicit object rules. The folder structure under BUILD_DIR mirrors the source
# tree so identically named files never collide and pattern matching stays simple.
$(BUILD_DIR)/%.c.o: $(PROJ_DIR)/%.c
	$(call build_cmd,CC,$<,$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) -c -o $@ $<)

$(BUILD_DIR)/%.cpp.o: $(PROJ_DIR)/%.cpp
	$(call build_cmd,CXX,$<,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(INC) -c -o $@ $<)

$(BUILD_DIR)/%.S.o: $(PROJ_DIR)/%.S
	$(call build_cmd,AS,$<,$(CC) $(CPPFLAGS) $(ASMFLAGS) $(INC) -c -o $@ $<)

# Generated sources (e.g. code-generation) reside in BUILD_DIR
# They compile with the same rules mirroring the rules above with a BUILD_DIR prefix.
# The duplicity is annoying but allows for clear artifact organization in BUILD_DIR.
$(BUILD_DIR)/%.c.o: $(BUILD_DIR)/%.c
	$(call build_cmd,CC,$<,$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) -c -o $@ $<)

$(BUILD_DIR)/%.cpp.o: $(BUILD_DIR)/%.cpp
	$(call build_cmd,CXX,$<,$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(INC) -c -o $@ $<)

$(BUILD_DIR)/%.S.o: $(BUILD_DIR)/%.S
	$(call build_cmd,AS,$<,$(CC) $(CPPFLAGS) $(ASMFLAGS) $(INC) -c -o $@ $<)

# Libraries (static archives). Targets adds an empty rule listing the object like:
#   $(BUILD_DIR)/libfoo.a: $(call src_to_obj,$(FOO_SRC))
#
# rm is mandatory since `ar r` replaces or adds but never removes old entries.
$(BUILD_DIR)/%.a:
	$(call build_cmd,AR,$@,rm -f -- $@ && $(AR) rcs $@ $^)

# Host executable targets. The .out suffix scopes this pattern to executables, so it never overlaps
# any similar %.o / %.a rules. Every .out depends on LIBS, so a recipe only adds its own objects and
# any target-specific libraries:
#   $(BUILD_DIR)/app.out: $(call src_to_obj,$(APP_SRC))
$(BUILD_DIR)/%.out: $$(LIBS)
	$(call build_cmd,LD,$@,$(LINK) $(LDFLAGS) $(INC) -o $@ $(filter-out %.a,$^) $(call group_libs,$(filter %.a,$^) $(SYS_LIBS_LDFLAGS)))

endif # ifeq "$(origin ccxx_inc_mk)" "undefined"
