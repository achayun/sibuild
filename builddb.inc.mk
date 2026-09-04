# sibuild: build commands journal in sqlite3
ifeq "$(origin builddb_inc_mk)" "undefined"
builddb_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/build.inc.mk

# sqlite3 with a busy wait protection for parallel (-j) build
# preventing "database is locked" error.
SQLITE ?= sqlite3 -cmd ".timeout 10000"

BUILD_DB := $(BUILD_DIR)/build.db

BUILD_HOSTNAME := $(shell hostname)

# Escape both for SQL ' and shell special characters $`" to record the command verbatim
cmd_esc = $(subst $$,\$$,$(subst `,\`,$(subst ",\",$(subst ','',$(1)))))

# Build command wrapper extension -- log successful commands into the journal
build_cmd += $(SQLITE) $(BUILD_DB) "INSERT INTO build_commands (build_ts, kind, directory, file, output, command, pid, host) VALUES ('$(START_TIME)', '$(strip $(1))', '$(CURDIR)', '$(abspath $<)', '$(abspath $@)', '$(call cmd_esc,$(3))', $$$$, '$(BUILD_HOSTNAME)');";

# The primary key is build_time - START_TIME from build.inc.mk
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE TABLE IF NOT EXISTS build_commands (id INTEGER PRIMARY KEY, build_ts INT, kind TEXT, directory TEXT, file TEXT, output TEXT, command TEXT, pid INT, host TEXT);
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE INDEX IF NOT EXISTS build_commands_by_build ON build_commands (build_ts);

# `builds` table identifies a full build run against git status
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE TABLE IF NOT EXISTS builds (build_ts INT PRIMARY KEY, proj_dir TEXT, build_dir TEXT, src_head TEXT, src_branch TEXT, src_dirty INT, host TEXT);

# Recursively expanded on purpose: these run git, and they are referenced only
# from the build-db-schema recipe, so they cost three processes per build rather
# than three per makefile parse (the phases re-parse it once each).
db_src_head   = $(shell git -C $(PROJ_DIR) rev-parse --short HEAD 2>/dev/null)
db_src_branch = $(shell git -C $(PROJ_DIR) rev-parse --abbrev-ref HEAD 2>/dev/null)
db_src_dirty  = $(shell git -C $(PROJ_DIR) status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Create the database schema. Extend by adding to the target-specific variable e.g.
# $(BUILD_DB): BUILD_DB_SCHEMA += ...
$(BUILD_DB): | $(BUILD_DIR)
	$(call log,SQL,$@)
	@$(SQLITE) $(BUILD_DB) "$(BUILD_DB_SCHEMA)"

# Register every build start in the database
.PHONY: builddb-build-start
builddb-build-start: $(BUILD_DB)
	@$(SQLITE) $(BUILD_DB) "INSERT OR IGNORE INTO builds (build_ts, proj_dir, build_dir, src_head, src_branch, src_dirty, host) VALUES ('$(START_TIME)', '$(PROJ_DIR)', '$(BUILD_DIR)', '$(db_src_head)', '$(db_src_branch)', '$(db_src_dirty)', '$(BUILD_HOSTNAME)');"

configure:: $(BUILD_DB) builddb-build-start

endif # ifeq "$(origin builddb_inc_mk)" "undefined"
