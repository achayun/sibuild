# sibuild: general build definitions and lifecycle targets
ifeq "$(origin build_inc_mk)" "undefined"
build_inc_mk := defined

# SIBUILD_DIR locates the sibuild makefiles. A project may set it before including (e.g. SIBUILD_DIR := $(PROJ_DIR)/sibuild);
# Defaults to the absolute directory this file lives in. Set once using `ifndef/:=` rather than `?=:`
# ?= is recursively expanded, so $(lastword ...) would be re-evaluated later and point at the wrong file
# := captures value once, conditionally with ifndef
ifndef SIBUILD_DIR
SIBUILD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
endif

.DEFAULT_GOAL = build

# By default use the git top level, even when invoked from a submodule.
export GIT_ROOT ?= $(abspath $(shell git rev-parse --show-toplevel 2>/dev/null))

# Project root is the anchor for the whole source tree: By default the git top level.
export PROJ_DIR ?= $(GIT_ROOT)

ifeq ($(strip $(PROJ_DIR)),)
$(error sibuild: PROJ_DIR is empty -- not a git repository? Set PROJ_DIR explicitly before including sibuild, e.g. PROJ_DIR := $$(CURDIR))
endif

# Output and intermediate artifacts directory.
export BUILD_DIR ?= $(PROJ_DIR)/build

# GNU Make 4.4 references GNUMAKEFLAGS while rebuilding MAKEFLAGS. Define to prevent warning.
GNUMAKEFLAGS ?=

# Strict make run with minimal assumptions
MAKEFLAGS += --warn-undefined-variables --no-builtin-rules --no-builtin-variables --no-print-directory
.SUFFIXES:			# Delete all default suffixes
.SECONDARY:			# Do not delete intermediate targets, trust me, I am an engineer
.DELETE_ON_ERROR:	# If a recipe fails, delete its (possibly half-written) target. Use .PRECIOUS to protect specific targets

# Measure build time and identify this build. Conditional one-time with ifndef/:= rather than ?=:
ifndef START_TIME
START_TIME := $(shell date +%s)
endif
export START_TIME

# Force a predictable UTF-8 locale so tools (sort, sed, etc.) behave consistently
# regardless of user's environment. C.UTF-8 ships on macOS and on glibc >= 2.35;
# if absent tools warn and fall back to the plain C locale.
LOCALE := C.UTF-8
export LANG := $(LOCALE)
export LANGUAGE := $(LOCALE)
export LC_ALL := $(LOCALE)

# Shell tools behavior. '--' guards against paths starting with '-'.
MKDIR = mkdir -p
RM = rm -rf --

# Convert an absolute path relative to project, by stripping the PROJ_DIR or BUILD_DIR prefix.
# patsubst is anchored at the start and matches the whole word.
rel = $(patsubst $(PROJ_DIR)/%,%,$(patsubst $(BUILD_DIR)/%,%,$(abspath $(1))))

# Resolve path against PROJ_DIR unless it is already absolute.
# Let source lists be shorthanded project-relative (src/main.c) rather than $(PROJ_DIR)/src/main.c
# Absolute paths (e.g. $(COMPONENT_DIR)/x.c in a multi-directory project) pass through.
at_proj = $(foreach f,$(1),$(if $(filter /%,$(f)),$(f),$(PROJ_DIR)/$(f)))

# Map source files in the project to targets under BUILD_DIR, appending suffix such as .c -> .c.o
# The translation preserves path relative to the tree root to prevent collision on identically named files.
# A generated source under BUILD_DIR maps to the same slot rather than nesting a second build/ inside it.
to_build_target = $(addprefix $(BUILD_DIR)/,$(call rel,$(addsuffix $(1),$(call at_proj,$(2)))))

# log: a progress line: $(call log,TAG,msg).
# Use printf rather than $(info) so lines appear in execution order with parallel (-j) builds.
ifdef SIBUILD_QUIET
log =
else
log = @printf '  %-4s %s\n' '$(strip $(1))' '$(call rel,$(2))'
endif


$(BUILD_DIR):
	@$(MKDIR) $@

# Build lifecycle PHASES. Run strictly in order, but work in a phase parallelizes under -j.
PHASES := configure generate_sources collect_objects targets post_build
.PHONY: build $(PHASES)

# The top-level makefile, so each phase sub-make re-enters this same build.
sibuild_makefile := $(firstword $(MAKEFILE_LIST))

# PHASES are double-colon targets, to be extended with more prerequisites and recipes.
# Each phase carries a silent no-op recipe to silence "Nothing to be done" message.
$(PHASES):: | $(BUILD_DIR)
	@:

# Each phase runs as an isolated, sequential sub-makes, so a later phase can never race an earlier one.
build::
	@for phase in $(PHASES); do \
		$(MAKE) --no-print-directory -f '$(sibuild_makefile)' $$phase || exit $$?; \
	done

endif # ifeq "$(origin build_inc_mk)" "undefined"
