# sibuild: per-phase build timing, on top of the build journal.
#
# Adds one table to $(BUILD_DIR)/build.db (see builddb.inc.mk) holding a
# timestamp per build per phase, and `make build-report` to read it back.
ifeq "$(origin stats_inc_mk)" "undefined"
stats_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif

include $(SIBUILD_DIR)/builddb.inc.mk

# Record the wall-clock time a phase reached, relative to START_TIME.
define mark_time
	@$(SQLITE) $(BUILD_DB) "INSERT INTO build_timestamps (build_ts, target, target_ts) VALUES ('$(START_TIME)', '$@', '$(shell date +%s)');"
endef

# Build timing schema build_time_sec measures each phase's duration as the delta to the previous phase.
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE TABLE IF NOT EXISTS build_timestamps (id INTEGER PRIMARY KEY, build_ts INT, target TEXT, target_ts INT);
$(BUILD_DB): BUILD_DB_SCHEMA += CREATE VIEW build_time_sec AS \
	WITH deltas AS ( \
		SELECT build_timestamps.id AS id, build_timestamps.build_ts AS build_ts, build_timestamps.target AS target, build_timestamps.target_ts AS target_ts, jt_previous.target_ts AS previous_ts \
		FROM build_timestamps \
		LEFT JOIN build_timestamps jt_previous on build_timestamps.id = jt_previous.id + 1 and build_timestamps.build_ts = jt_previous.build_ts \
	) \
	SELECT build_ts, target, (target_ts - COALESCE(previous_ts,build_ts)) as delta_sec FROM deltas;

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
build-report:
	@$(SQLITE) $(BUILD_DB) "SELECT printf('%-18s %4d s', target, delta_sec) FROM build_time_sec WHERE build_ts = (SELECT MAX(build_ts) FROM build_timestamps);"

post_build:: build-report

endif # ifeq "$(origin stats_inc_mk)" "undefined"
