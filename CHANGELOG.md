# Changelog for woof

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-02-21
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

[0.1.0]: https://hex.pm/packages/woof/0.1.0
