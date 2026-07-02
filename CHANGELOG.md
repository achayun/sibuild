# Changelog

All notable changes to sibuild are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.2] - 2026-07-02

Minor bugfix release

### Fixes
- Allow extending PHASES

[1.0.2]: https://github.com/achayun/sibuild/releases/tag/v1.0.2

## [1.0.1] - 2026-06-30

Minor bugfix release

### Fixes
- Fixed a dependency issue with the git submodule Makefile. It now depends correctly on the submodule
  index which should change in top repo pull
- Some comments clarifying behavior
- Silence VENV shell

[1.0.1]: https://github.com/achayun/sibuild/releases/tag/v1.0.1

## [1.0.0] - 2026-06-18

First public release: the consolidation of a Makefile collection refined over years
across host and cross-compiled firmware projects into a uniform, documented build foundation.

### Features

- `build.inc.mk` - project anchors (`PROJ_DIR`, `BUILD_DIR`,
  `SIBUILD_DIR`, `GIT_ROOT`), Make hardening (no built-in rules/variables,
  warn on undefined variables), double-colon build lifecycle
  (`configure → generate_sources → collect_objects → targets → post_build`),
  and project path helpers (`rel` / `to_build_target` etc.).
- `ccxx.inc.mk` - C, C++, ASM implicit rules, a strict default warning
  set, static-archives (`%.a`) and host-executable (`%.out`) rules.
- `firmware.inc.mk` - cross-toolchain scaffolding: wires up the toolchain from
  `CROSS_COMPILE` and produces `.elf`+`.map`, `.bin`. Intel `.hex`,
  `.dis` on demand. Stays out of architecture policy (arch flags, `-std`,
  optimization level, freestanding, linker script, startup are the project's).
  Sets firmware good-practice flags defaults - LTO, code elimination and flash/RAM usage report.
- `stats.inc.mk` - sqlite3 build journal per-phase timing. Include and call `make build-report`.
- `clangd.inc.mk` - generate `compile_commands.json` and an include-path file;
  `make clangd-config` writes a `.clangd` (database path + `QueryDriver`, so clangd
  resolves a cross toolchain's system headers).
- `clang-tidy.inc.mk` - clang-tidy targets after the build is done.
- `python.inc.mk` - run Python build tooling in a sandboxed Python venv.
- `submodule.inc.mk` - lazy git submodule checkout.

[1.0.0]: https://github.com/achayun/sibuild/releases/tag/v1.0.0
