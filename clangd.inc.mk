# sibuild: clangd integration.
#
# Journals every compile command into an sqlite database - $(BUILD_DIR)/compile_commands.db
# exports a compile_commands.json # (https://clang.llvm.org/docs/JSONCompilationDatabase.html)
# plus an include_path file for editors.
ifeq "$(origin clangd_inc_mk)" "undefined"
clangd_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/stats.inc.mk

COMPILE_DB := $(BUILD_DIR)/compile_commands.db
COMPILE_COMMANDS_JSON := $(BUILD_DIR)/compile_commands.json

# Replace single quotes with double so a command embeds cleanly in SQL.
# Must be '=' (recursive), not ':=' (immediate): $(1) is substituted at each $(call), not once now.
replace_quotes = $(subst ',",$(1))

# Override run_cmd to journal commands into build database. Keeps signature same as the base:
#	$(call run_cmd,$(1)=tag, $(2)=shown path, $(3)=command)
define run_cmd
	$(call log,$(1),$(2))
	@$(MKDIR) $(dir $@)
	@$(3) || { printf '[FAILED] %s\n' "$(3)" >&2; exit 1; }
	@$(SQLITE) $(COMPILE_DB) "INSERT INTO build_compile_commands (build_ts, directory, file, output, command) VALUES ('$(START_TIME)', '$(CURDIR)', '$(abspath $<)', '$(abspath $@)', '$(call replace_quotes,$(3))');"
endef

# compile_commands.db sqlite database. Schema is created during configure so tables exist before
# run_cmd journals the first command. `build_compile_commands` journals every command (a
# general-purpose build journal); the `compile_commands` view narrows it to TUs (translation units);
# the latest .o-producing command per source for compile_commands.json.
configure:: $(COMPILE_DB)
$(COMPILE_DB): | $(BUILD_DIR)
	$(call log,SQL,$@)
	@$(SQLITE) $(COMPILE_DB) "CREATE TABLE IF NOT EXISTS build_compile_commands (id INTEGER PRIMARY KEY, build_ts INT, directory TEXT, file TEXT, output TEXT, command TEXT);"
	@$(SQLITE) $(COMPILE_DB) "CREATE VIEW IF NOT EXISTS compile_commands AS SELECT a.* FROM build_compile_commands a JOIN (SELECT file, MAX(build_ts) AS max_timestamp FROM build_compile_commands WHERE output LIKE '%.o' GROUP BY file) b ON a.file = b.file AND a.build_ts = b.max_timestamp WHERE a.output LIKE '%.o';"

$(COMPILE_COMMANDS_JSON): $(COMPILE_DB)
	$(call log,JSON,$@)
	@$(SQLITE) -readonly -json $< "SELECT command,directory,file,output FROM compile_commands;" > $@

post_build:: $(COMPILE_COMMANDS_JSON)

# clangd-config: optionally write a minimal .clangd at the project root:
#   CompilationDatabase - point clangd at BUILD_DIR to support custom BUILD_DIR as clangd already finds ./ and ./build.
#   QueryDriver         - the resolved $(CC)/$(CXX) paths, so clangd discovers the
#                         toolchain's system headers and target without guessing.
# Everything else is the developer's, and belongs in their own .clangd or ~/.config/clangd/config.yaml.
# Run: make clangd-config
.PHONY: clangd-config
clangd-config:
	$(call log,GEN,$(PROJ_DIR)/.clangd)
	@{ \
	  printf 'CompileFlags:\n'; \
	  printf '  CompilationDatabase: %s\n' '$(call rel,$(BUILD_DIR))'; \
	  drivers=$$({ command -v $(CC); command -v $(CXX); } 2>/dev/null | sort -u | paste -sd, -); \
	  if [ -n "$$drivers" ]; then printf '  QueryDriver: [%s]\n' "$$drivers"; fi; \
	} > $(PROJ_DIR)/.clangd

# include_path file - Tell editors where to look for headers (one comma-separated line of dirs).
INCLUDE_PATH_FILE := $(BUILD_DIR)/include_path
$(INCLUDE_PATH_FILE):
	$(call log,INC,$@)
	@realpath . | tr '\n' ',' > $@
	@echo "$(INC_DIRS) $(INC)" | sed -e 's/-I//g' | xargs realpath | sort -u -r | tr '\n' ',' >> $@

endif # ifeq "$(origin clangd_inc_mk)" "undefined"
