# sibuild

**A uniform, multi-target build foundation for C/C++ that makes modern standards,
good practices, and reproducible results the default.**

The name **sibuild** nods to SI (International System of Units): a small, shared vocabulary of precise primitives that scales consistently.

A collection of `*.inc.mk` files to include from your `Makefile`, scaling from a
one-file host tool to a cross-compiled, multi-phase, multi-target firmware tree on
one consistent model. Plain Make, with strict defaults, so the build does exactly what is written;
parallel-safe (`-j`) and reproducible. Pinned tools, no ambient system state, all
artifacts out of tree. Built for C and C++, but the lifecycle, path model and
tooling are not C-specific.

Complex builds use the same primitives: in a multi-module tree with code
generation, baked data and mixed host/cross toolchains, the phased lifecycle keeps
generation → compilation → linking strictly ordered (even under `-j`), generated
sources compile straight out of `BUILD_DIR`, and any project-specific tooling
is just another `.inc.mk`. sibuild provides a rigid minimal spine; you compose the assembly.

## Principles

- **Explicit over heuristic** - declared dependency graph; no `add_source`-style magic.
- **Build lifecycle** - when strict ordering matters, mutually exclusive build phases that every module extends.
- **Out-of-source, self-contained** - artifacts mirror the source tree under `BUILD_DIR`; `make clean` is `rm -rf build/`.
- **Cross-compile first** - the host is just another target triple, which keeps builds reproducible.
- **Explicit and isolated** - no built-in `make` rules and no ambient environment state leaking into the build.
- **Tooling-friendly** - emits `compile_commands.json` and a per-phase build journal for editors and CI.

## Tradeoffs

- Tools are not provisioned: system tools must already exist on `PATH`.
- The `stats` / `clangd` / `clang-tidy` add-ons use `sqlite3` for bookkeeping.
- By default no-extension binaries get a `.out` suffix. Read why in `ccxx.inc.mk`.

## Makefiles

| File | Provides |
|---|---|
| `build.inc.mk` | Build lifecycle phases, system tool configuration. Path helpers |
| `ccxx.inc.mk` | C/C++/asm rules, default warnings, produces static libraries `%.a`, and binaries `%.out` |
| `firmware.inc.mk` | cross-toolchain (`CROSS_COMPILE`), produces embedded binaries `%.elf` / `.bin` / `.hex` / `.dis` |
| `stats.inc.mk` | sqlite3 build journal + per-phase timing |
| `clangd.inc.mk` | sqlite3 compilation commands journal renders `compile_commands.json` for editors |
| `clang-tidy.inc.mk` | Post build `make clang-tidy` |
| `python.inc.mk` | run Python based build tools in a per-directory venv |
| `submodule.inc.mk` | lazy `git submodule` checkout |

## Usage

Vendor sibuild (e.g. git submodule), then include what you need from your `Makefile`. Basic example:

```make
PROJ_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(PROJ_DIR)/sibuild/ccxx.inc.mk

CFLAGS   += -std=c17 -O2
INC_DIRS += include
APP_SRC = src/main.c

$(BUILD_DIR)/app.out: $(call src_to_obj,$(APP_SRC))
targets:: $(BUILD_DIR)/app.out
```

`make` builds `build/app.out`.

### Bootstrapping

When sibuild is referenced as a dependency, say a submodule, a fresh `git clone` leaves it empty and the `include` fails.
There are several suggested ways to bootstrap it.

**Manual init** -- Document that the project must be cloned with `git clone --recursive`,
or that `git submodule update --init` has to be run once, or a custom bootstrap script.
This costs the build nothing, but `--recursive` initializes every submodule in the tree
whether the build needs it or not, and it relies on the every reader not forgetting.

The patterns below let the `Makefile` resolve sibuild on its own instead. The examples
are for git submodule but both strategies can be used for other means.

**Parse-time guard** -- Runs before the first `include`, so one guard covers every sibuild
file the tree pulls in, from wherever it is included:

```make
SIBUILD_DIR := $(PROJ_DIR)/mk/sibuild

ifeq ($(wildcard $(SIBUILD_DIR)/build.inc.mk),)
    $(info [GIT] $(SIBUILD_DIR))
    sibuild_init := $(shell git submodule update --init -- $(SIBUILD_DIR) >&2 \
                         && test -f $(SIBUILD_DIR)/build.inc.mk && echo ok)
    ifneq "$(sibuild_init)" "ok"
        $(error failed to initialize submodule $(SIBUILD_DIR))
    endif
endif

include $(SIBUILD_DIR)/build.inc.mk
```

This is the recommended approach. The `test -f` is what confirms the checkout: make caches
directory listings for the whole run, so re-checking with `$(wildcard)` would still report
the file as missing.

**Remaking rule** -- A missing `include` is a deferred, non-fatal error: make looks for a rule
to build the file, runs it, then re-executes itself.

```make
SIBUILD_DIR := $(PROJ_DIR)/mk/sibuild

$(SIBUILD_DIR)/build.inc.mk:
	@git submodule update --init -- $(SIBUILD_DIR)
	@test -f $@ || { echo "error: failed to initialize $(@D)" >&2; exit 1; }

include $(SIBUILD_DIR)/build.inc.mk
```

This is only practical when the project includes a single sibuild file. Make decides whether a missing
makefile is buildable *before* it runs any recipe, so every sibuild file included anywhere in
the tree needs a target of its own - listed in this rule or given a separate one - otherwise
make aborts on the first one it cannot build, even though an earlier recipe would already have
checked it out. Each target must also match its `include` string character for character, since
a relative target does not satisfy an absolute `include`. Under `-j`, make remakes makefiles in
parallel, turning several missing includes into concurrent `git submodule update` calls that
race each other.


For quickstart, concepts, a full reference, and runnable examples - host, library + tests,
code generation, cross-compiled firmware - see **[sibuild-examples](https://github.com/achayun/sibuild-examples)**.

## Requirements

GNU Make ≥ 3.81; `sqlite3` for the `stats` / `clangd` add-ons.
See each `*.inc.mk` for its specific requirements.

## License

[MIT](LICENSE).
