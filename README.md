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

For quickstart, concepts, a full reference, and runnable examples - host, library + tests,
code generation, cross-compiled firmware - see **[sibuild-examples](https://github.com/achayun/sibuild-examples)**.

## Requirements

GNU Make ≥ 3.81; `sqlite3` for the `stats` / `clangd` add-ons.
See each `*.inc.mk` for its specific requirements.

## License

[MIT](LICENSE).
