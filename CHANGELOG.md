# Changelog for woof

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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

[1.0.1]: https://hex.pm/packages/woof/1.0.1
[1.0.0]: https://hex.pm/packages/woof/1.0.0
