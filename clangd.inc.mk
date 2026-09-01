# sibuild: clangd integration.
#
# Journals every build command into an sqlite database - $(BUILD_DIR)/compile_commands.db
# exports a compile_commands.json # (https://clang.llvm.org/docs/JSONCompilationDatabase.html)
# plus an include_path file for editors.
ifeq "$(origin clangd_inc_mk)" "undefined"
clangd_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/stats.inc.mk

COMPILE_COMMANDS_DB := $(BUILD_DIR)/compile_commands.db
COMPILE_COMMANDS_JSON := $(BUILD_DIR)/compile_commands.json

BUILD_HOSTNAME := $(shell hostname)
# Replace single quotes with double so a command embeds cleanly in SQL.
replace_quotes = $(subst ',",$(1))

# Override build_cmd to journal commands into build database:
#	$(call build_cmd,$(1)=tag, $(2)=shown path, $(3)=command)
define build_cmd
	$(call log,$(1),$(2))
	@$(MKDIR) $(dir $@)
	@$(3); status=$$?; \
	$(SQLITE) $(COMPILE_COMMANDS_DB) "INSERT INTO build_commands (build_ts, directory, file, output, command, pid, host, exit_code) VALUES ('$(START_TIME)', '$(CURDIR)', '$(abspath $<)', '$(abspath $@)', '$(call replace_quotes,$(3))', $$$$, '$(BUILD_HOSTNAME)', $$status);"; \
	if [ $$status -ne 0 ]; then printf '[FAILED] %s\n' "$(3)" >&2; exit $$status; fi
endef

# compile_commands.db sqlite database. Schema is created during configure before
# build_cmd journals the first command. `build_commands` journals every build command
# `compile_commands` view selects only latest .o TUs (translation units) for compile_commands.json
configure:: $(COMPILE_COMMANDS_DB)
$(COMPILE_COMMANDS_DB): | $(BUILD_DIR)
	$(call log,SQL,$@)
	@$(SQLITE) $(COMPILE_COMMANDS_DB) "CREATE TABLE IF NOT EXISTS build_commands (id INTEGER PRIMARY KEY, build_ts INT, directory TEXT, file TEXT, output TEXT, command TEXT, pid INT, host TEXT, exit_code INT);"
	@$(SQLITE) $(COMPILE_COMMANDS_DB) "CREATE VIEW IF NOT EXISTS compile_commands AS SELECT a.* FROM build_commands a JOIN (SELECT file, MAX(build_ts) AS max_timestamp FROM build_commands WHERE output LIKE '%.o' GROUP BY file) b ON a.file = b.file AND a.build_ts = b.max_timestamp WHERE a.output LIKE '%.o';"

$(COMPILE_COMMANDS_JSON): $(COMPILE_COMMANDS_DB)
	$(call log,JSON,$@)
	@$(SQLITE) -readonly -json $< "SELECT command,directory,file,output FROM compile_commands;" > $@

post_build:: $(COMPILE_COMMANDS_JSON)

# dot-clangd: generate a scaffold .clangd at the project root:
#   CompilationDatabase - point clangd at BUILD_DIR (clangd already finds ./ and ./build).
#   QueryDriver         - resolved $(CC)/$(CXX) paths
# Run: make dot-clangd
.PHONY: dot-clangd
dot-clangd:
	$(call log,GEN,$(PROJ_DIR)/.clangd)
	@{ \
	  printf 'CompileFlags:\n'; \
	  printf '  CompilationDatabase: %s\n' '$(call rel,$(BUILD_DIR))'; \
	  drivers=$$({ command -v $(CC); command -v $(CXX); } 2>/dev/null | sort -u | paste -sd, -); \
	  if [ -n "$$drivers" ]; then printf '  QueryDriver: [%s]\n' "$$drivers"; fi; \
	} > $(PROJ_DIR)/.clangd

endif # ifeq "$(origin clangd_inc_mk)" "undefined"
