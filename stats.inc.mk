# sibuild: per-phase build timing, journaled into an sqlite database.
#
# Uses $(BUILD_DIR)/build.db, for per-build per-phase timestamps.
ifeq "$(origin stats_inc_mk)" "undefined"
stats_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/build.inc.mk

BUILD_DB := $(BUILD_DIR)/build.db

# sqlite invocation with a busy timeout, so parallel (-j) jobs writing the
# journal wait for the lock instead of failing with "database is locked".
SQLITE ?= sqlite3 -cmd ".timeout 10000"

configure:: $(BUILD_DB)

# Record the wall-clock time a phase reached, relative to START_TIME.
define mark_time
	@$(SQLITE) $(BUILD_DB) "INSERT INTO build_timestamps (build_ts, target, target_ts) VALUES ('$(START_TIME)', '$@', '$(shell date +%s)');"
endef

# Create build.db with the timing schema.
# build_time_sec derives each phase's duration as the delta to the previous phase.
$(BUILD_DB): | $(BUILD_DIR)
	$(call log,SQL,$@)
	@$(SQLITE) $(BUILD_DB) "CREATE TABLE IF NOT EXISTS build_timestamps (id INTEGER PRIMARY KEY, build_ts INT, target TEXT, target_ts INT);"
	@$(SQLITE) $(BUILD_DB) "CREATE VIEW IF NOT EXISTS build_time_sec AS \
		WITH deltas AS ( \
			SELECT build_timestamps.id AS id, build_timestamps.build_ts AS build_ts, build_timestamps.target AS target, build_timestamps.target_ts AS target_ts, jt_previous.target_ts AS previous_ts \
			FROM build_timestamps \
			LEFT JOIN build_timestamps jt_previous on build_timestamps.id = jt_previous.id + 1 and build_timestamps.build_ts = jt_previous.build_ts \
		) \
		SELECT build_ts, target, (target_ts - COALESCE(previous_ts,build_ts)) as delta_sec FROM deltas;"

# Stamp lifecycle PHASES.
build::
	$(call mark_time)
configure::
	$(call mark_time)
generate_sources::
	$(call mark_time)
collect_objects::
	$(call mark_time)
targets::
	$(call mark_time)
post_build::
	$(call mark_time)

# Print a per-phase timing report for the most recent build.
.PHONY: build-report
build-report: $(BUILD_DB)
	@$(SQLITE) $(BUILD_DB) "SELECT printf('%-18s %4d s', target, delta_sec) FROM build_time_sec WHERE build_ts = (SELECT MAX(build_ts) FROM build_timestamps);"

endif # ifeq "$(origin stats_inc_mk)" "undefined"
