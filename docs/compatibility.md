# Compatibility

d6 numbers its releases major.minor.patch:

- **Patch releases** (1.4.1, 1.4.2, ...) contain only bug fixes and performance
  improvements. Nothing in a patch release breaks a working program.
- **Minor releases** (1.5, 1.6, ...) add features, and occasionally make a
  breaking change when that fixes a real problem. Each one is marked
  **Breaking** in the
  [changelog](https://github.com/diamond-language/d6/blob/main/CHANGELOG.md)
  and the release notes, with what to change.

Pin the version you build with, as a mise version or a package, and upgrade
when you're ready. Until 1.4.0, minor releases made no breaking changes; the
first was 1.4.0's [character Strings](release-1.4.0.md#breaking-strings-count-characters).

## Language and standard library

Apart from the changes marked **Breaking**, source that compiles and runs on one
release compiles and runs, with the same results, on later releases. Later
releases may add syntax, core methods, classes, modules, cuts and command-line
options.

These are not covered:

- **Bugs.** A fix may change behavior that contradicted this documentation, or
  that crashed, hung or corrupted data.
- **Security fixes,** which may tighten what the sandbox, TLS, the HTTP parser or
  the package installer accept.
- **Names added to the standard library.** A new core class, module, function or
  method can share a name with one an application defines, and the application
  may need a small refactor, usually renaming its own definition.
- **Message text.** Exception classes and the conditions that raise them are
  stable. The wording of error messages, warnings, backtraces and `inspect` output is
  not.
- **Performance and memory use,** which may change in either direction.
- **Interfaces marked experimental,** below.

## Compiled programs

The bytecode cache and the programs `d6 build` produces belong to the exact
build of `d6` that made them; see [caching](caching.md). Another build
treats a cache file as a miss and recompiles the source, so upgrading needs no
action. A standalone executable keeps running as built. To move it to a new
release, run `d6 build` again with that release.

There is no bytecode format to target. Distribute source or executables, not
cache files.

## Projects and packages

Every `facet` reads `Cutfile`, `Cutfile.dev` and `Cutfile.lock` files
written by earlier releases, and installs from them the same versions they
lock. Later releases may add manifest keys. A project that uses a new key needs
a `facet` that knows it, and older releases reject it rather than ignoring it.

Published cut releases are immutable; see the [cut contract](cut-contract.md).
A cut that a breaking change affects can name the d6 versions it works with
(`"d6": ">=1.4.0"` in its Cutfile). facet and the registry then give an older
d6 the cut's last release that works for it, so a project that hasn't upgraded
keeps installing.

## Experimental interfaces

These may change in any release:

- **The C embedding API.** The headers under `src/`, `ProgramBuilder` and the
  VM's native entry points are the implementation, not a library interface.
  No release installs a header or a shared library to embed.
- **Tuning and diagnostic variables,** such as `DIAMOND_JIT_THRESHOLD`,
  `DIAMOND_STRESS_GC` and the `DIAMOND_TRACE_*` family. The one exception is
  `DIAMOND_JIT=1`, which turns the JIT on: that variable is stable.
- **The self-hosted compiler** under `selfhost/`. It is a test oracle for the
  native compiler, not a supported frontend.
- **The debugger and language server protocols** beyond what their editors use:
  [debugging](debugging.md) and [lsp](lsp.md) describe the supported clients.

## Platforms

Supported platforms are listed in [portability](portability.md). A release
may add platforms. It drops one only when its toolchain or vendor support ends,
and the changelog announces the change a release ahead.
