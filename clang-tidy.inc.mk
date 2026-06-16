# sibuild: clang-tidy linting driven by compile_commands.json.
#
# include this Makefile for an optional clang-tidy linting step. Linting is slow,
# memory intensive, and needs run-clang-tidy installed.
ifeq "$(origin clang_tidy_inc_mk)" "undefined"
clang_tidy_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/clangd.inc.mk

CLANG_TIDY         ?= clang-tidy
RUN_CLANG_TIDY     ?= run-clang-tidy
CLANG_TIDY_CONFIG  ?= $(PROJ_DIR)/.clang-tidy
# Only lint first-party headers by default; override per project as needed.
TIDY_HEADER_FILTER ?= ^($(abspath $(PROJ_DIR))/)?(src|include|tests)/

.PHONY: clang-tidy clang-tidy-verify clang-tidy-tools

# Early fail with a friendly message if tools aren't installed
clang-tidy-tools:
	@command -v $(CLANG_TIDY) >/dev/null 2>&1 || { \
		echo "sibuild: '$(CLANG_TIDY)' not found — install LLVM clang-tools-extra." >&2; exit 1; }
	@command -v $(RUN_CLANG_TIDY) >/dev/null 2>&1 || { \
		echo "sibuild: '$(RUN_CLANG_TIDY)' not found — install LLVM clang-tools-extra." >&2; exit 1; }

clang-tidy-verify: clang-tidy-tools
	@$(CLANG_TIDY) --config-file="$(CLANG_TIDY_CONFIG)" --verify-config

clang-tidy: clang-tidy-verify $(COMPILE_COMMANDS_JSON)
	@$(RUN_CLANG_TIDY) \
		-quiet \
		-p "$(BUILD_DIR)" \
		-config-file="$(CLANG_TIDY_CONFIG)" \
		-header-filter='$(TIDY_HEADER_FILTER)'

post_build:: clang-tidy

endif # ifeq "$(origin clang_tidy_inc_mk)" "undefined"
