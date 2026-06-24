# sibuild: run Python tooling inside a per-directory venv virtual environment.
#
# venv is created for each requirements.txt under BUILD_DIR, in a relative path sandboxed from
# system Python. To initialize; declare a dependency on the venv's requirements stamp:
#   $(BUILD_DIR)/tools/venv/requirements.txt
# then run commands inside it with the py_venv function.
ifeq "$(origin python_inc_mk)" "undefined"
python_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
endif
include $(SIBUILD_DIR)/build.inc.mk

PYTHON ?= python3

# py_venv: run a command inside a directory's virtual environment.
#   $(1) - source directory whose venv to use (maps under BUILD_DIR)
#   $(2) - the command/module to run (e.g. -m pip)
#   $(3) - arguments to the command
# Notes:
# * Shell variables are deferred with $$ so the venv is resolved at run time.
# * The bin/ vs Scripts/ probe is only there to also work under Windows venvs.
define py_venv
	@VENV_DIR="$(BUILD_DIR)/$(call rel,$(1))/venv"; \
	if [ -x $$VENV_DIR/bin/python ]; then \
		PYTHON_BIN=$$VENV_DIR/bin/python; \
	elif [ -x $$VENV_DIR/Scripts/python.exe ]; then \
		PYTHON_BIN=$$VENV_DIR/Scripts/python.exe; \
	else \
		echo "Error: no Python binary found in $$VENV_DIR" >&2; exit 1; \
	fi; \
	exec $$PYTHON_BIN $(2) $(3)
endef

# Create and populate a venv as one target, copying requirements.txt into
# BUILD_DIR as the up-to-date stamp against the source requirements.txt.
#
# A mutex (atomic mkdir) serializes venv/pip operations across parallel (-j)
# jobs: concurrent `python -m venv` / `pip` share global state — the pip cache
# and ensurepip's bundled wheels — and corrupt one another. mkdir is portable
# (works on macOS, unlike flock); we cannot use ".NOTPARALLEL: <targets>" because
# before GNU Make 4.4 it disables -j for the entire build.
$(BUILD_DIR)/%/venv/requirements.txt: $(PROJ_DIR)/%/requirements.txt
	$(call log,PIP,$<)
	@set -e; venv='$(dir $@)'; lock='$(BUILD_DIR)/.venv.lock'; \
	 until mkdir "$$lock" 2>/dev/null; do sleep 0.2; done; \
	 trap 'rmdir "$$lock" 2>/dev/null' EXIT; \
	 if   [ -x "$${venv}bin/python" ];         then py="$${venv}bin/python"; \
	 elif [ -x "$${venv}Scripts/python.exe" ]; then py="$${venv}Scripts/python.exe"; \
	 else $(PYTHON) -m venv "$$venv"; \
	      if [ -x "$${venv}bin/python" ]; then py="$${venv}bin/python"; else py="$${venv}Scripts/python.exe"; fi; \
	 fi; \
	 "$$py" -m pip install -r '$<' --disable-pip-version-check --quiet; \
	 cp '$<' '$@'

endif # ifeq "$(origin python_inc_mk)" "undefined"
