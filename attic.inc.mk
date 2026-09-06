# sibuild: archive build artifacts in a Git repository in BUILD_DIR.
ifeq "$(origin attic_inc_mk)" "undefined"
attic_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/builddb.inc.mk

BUILD_ATTIC_DIR     ?= $(BUILD_DIR)
BUILD_ATTIC_GIT_DIR := $(BUILD_ATTIC_DIR)/.attic.git
BUILD_ATTIC_GIT     = git --git-dir=$(BUILD_ATTIC_GIT_DIR) --work-tree=$(BUILD_ATTIC_DIR)

# Ignore anything not explicitly added
BUILD_ATTIC_IGNORE ?= '*'

# Initialize the attic
$(BUILD_ATTIC_GIT_DIR): | $(BUILD_ATTIC_DIR)
	$(call log,ATTIC-INIT,$@)
	@$(BUILD_ATTIC_GIT) init -q
	@$(BUILD_ATTIC_GIT) config user.name "attic"
	@$(BUILD_ATTIC_GIT) config user.email "attic@localhost"
	@$(BUILD_ATTIC_GIT) config core.autocrlf false
	@$(BUILD_ATTIC_GIT) config advice.addEmptyPathspec false
	@printf '%s\n' $(BUILD_ATTIC_IGNORE) > $(BUILD_ATTIC_GIT_DIR)/info/exclude

# build_db_outputs: selects the outputs of build.
# $(call build_db_outputs,<BUILD_TS>) - use START_TIME for latest build.
build_db_outputs = $(SQLITE) -readonly $(BUILD_DB) "SELECT DISTINCT output FROM build_commands WHERE build_ts = '$(strip $(1))' AND exit_code = 0 ORDER BY output;"

# Stage and commit all changed outputs from build.db if any outputs actually changed
# attic-store failures are considered non-fatal. git calls are prefixed with `-`.
# Limitation: Currently only outputs inside the attic (BUILD_DIR) can be added.
# If this becomes a problem it's worth exploring setting --work-tree based on artifact dir
attic-store: $(BUILD_DB)
	-@$(call build_db_outputs,$(START_TIME)) | grep -q . || exit 0; \
	  $(call build_db_outputs,$(START_TIME)) \
	  | while IFS= read -r out; do \
		  [ -e "$$out" ] && printf '%s\0' "$$out"; \
	    done \
	  | $(BUILD_ATTIC_GIT) add -f --pathspec-from-file=- --pathspec-file-nul --
	-@$(BUILD_ATTIC_GIT) diff --cached --quiet || { \
	    n=$$($(BUILD_ATTIC_GIT) diff --cached --name-only | wc -l | tr -d ' '); \
	    $(BUILD_ATTIC_GIT) commit -q -m '$(START_TIME)' && \
	    printf '  %-4s %s\n' 'ATTIC' \
	        "$$($(BUILD_ATTIC_GIT) rev-parse --short HEAD) ($$n changed)"; \
	}

.PHONY: attic-store
post_build:: attic-store

endif # ifeq "$(origin attic_inc_mk)" "undefined"
