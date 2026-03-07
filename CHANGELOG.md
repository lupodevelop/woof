# Changelog for woof

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-03-07
### Added
- Introduced `Sink` type and `set_sink/1` function allowing clients to provide custom side-effect handlers (e.g. write to file, send over network).
- Public `default_sink/2` function exposed so custom sinks can delegate to the original console printer.
- Updated internal state to carry the configured sink; defaults continue to behave exactly as before.

### Notes
- Change is fully backwards-compatible; existing code compiled against 1.0.3 or earlier will function without modification.
- This enhancement paves the way for external adapters that implement advanced features such as log rotation, batching, or remote ingestion.

## [1.0.3] - 2026-03-07
### Fixed
- Fixed a detached doc comment warning in `woof.gleam` during compilation.
- Proper escaping of newlines (`\n`, `\r`) and backslashes in `Compact` format output, ensuring multi-line log messages don't break logfmt parsers.
- Improved the performance of JSON format structure assembly by batching list elements and reducing sequential `list.append` operations.
- Made public API doc comments more conversational and readable.

## [1.0.2] - 2026-03-03
### Fixed
- Changed `Compact` format to wrap values in quotes when they contain spaces, `=` or are empty, conforming more closely to logfmt parsers.
- Protected internal JSON keys (`level`, `time`, `ns`, `msg`) by prefixing user fields with `_` if they collide.
- Enhanced `json_escape` to properly escape ANSI sequence control characters (`\u001b` / `\x1b`) so they don't break JSON log pipelines.

### Documentation
- Added a "Notice for JavaScript async users" in the README and docs for `with_context`, detailing how cooperatively scheduled Promise-based code in JS affects the global context.

## [1.0.1] - 2026-02-28
### Fixed
- Fixed changelog link pointing to `0.1.0` instead of `1.0.0`.
- Simplified `time()` duration formatting: removed unnecessary
  `Int → Float → String` conversion, now uses `int.to_string` directly.
- Added missing `\b` (backspace) and `\f` (form feed) escapes in
  `json_escape`, as required by RFC 8259.
- Removed redundant `---` horizontal rules in the README under
  "Cross-platform" and "Dependencies & Requirements" headings.

## [1.0.0] - 2026-02-21
### Added
- Initial public release of the `woof` logging library for Gleam. Dedicated to Echo the dog.
- Zero‑configuration API with four severity levels (`debug`, `info`,
  `warning`, `error`).
- Structured logging using simple `#(String, String)` tuples and helper
  constructors (`field`, `int_field`, `float_field`, `bool_field`).
- Multiple output formats: human-readable Text (with optional ANSI colours),
  Compact `key=value`, JSON and a `Custom` formatter callback.
- Namespaced loggers via `woof.new/1` and `woof.log` for component-specific
  messages.
- Scoped (`with_context`) and global (`set_global_context`) field contexts.
- Lazy logging variants (`*_lazy`), pipeline helpers (`tap_*`, `log_error`,
  `time`), and convenience configuration functions (`configure`, `set_level`,
  `set_format`, `set_colors`).
- Cross‑platform support: identical behaviour on BEAM and JavaScript targets.
- Comprehensive test suite (34 tests) and detailed documentation in README and
  project reference.

[1.0.2]: https://hex.pm/packages/woof/1.0.2
[1.0.1]: https://hex.pm/packages/woof/1.0.1
[1.0.0]: https://hex.pm/packages/woof/1.0.0
