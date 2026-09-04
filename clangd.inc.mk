# sibuild: clangd integration.
#
# Exports a compile_commands.json (https://clang.llvm.org/docs/JSONCompilationDatabase.html)
# from the build journal $(BUILD_DIR)/build.db (see builddb.inc.mk).
ifeq "$(origin clangd_inc_mk)" "undefined"
clangd_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/builddb.inc.mk

COMPILE_COMMANDS_JSON := $(BUILD_DIR)/compile_commands.json

# `compile_commands` view: select the latest command per TU (translation unit), i.e. only .o outputs
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE VIEW compile_commands AS SELECT a.* FROM build_commands a JOIN (SELECT file, MAX(build_ts) AS max_timestamp FROM build_commands WHERE output LIKE '%.o' GROUP BY file) b ON a.file = b.file AND a.build_ts = b.max_timestamp WHERE a.output LIKE '%.o';

$(COMPILE_COMMANDS_JSON):
	$(call log,JSON,$@)
	@$(SQLITE) -readonly -json $(BUILD_DB) "SELECT command,directory,file,output FROM compile_commands;" > $@

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
