# Changelog for woof

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-04-17

### Added

- **Eight OTP log levels** - `Level` now includes `Notice`, `Critical`, `Alert`,
  and `Emergency` in addition to the original four.  The ordinal mapping matches
  the OTP / syslog severity scale:

  | Level       | Int | Use for                                  |
  | :---------- | :-: | :--------------------------------------- |
  | `Debug`     |  0  | Development traces                       |
  | `Info`      |  1  | Normal application flow                  |
  | `Notice`    |  2  | Significant business events (not errors) |
  | `Warning`   |  3  | Anomalous but recoverable situations     |
  | `Error`     |  4  | Failures requiring attention             |
  | `Critical`  |  5  | System degradation, partial failure      |
  | `Alert`     |  6  | Immediate action required                |
  | `Emergency` |  7  | System is unusable                       |

- **New logging functions** - `notice`, `critical`, `alert`, `emergency` (and
  their `_lazy` variants) mirror the new level values.

- **`beam_event_sink`** - a new `EventSink` (`fn(LogEvent) -> Nil`) that routes
  events through OTP `logger:log/4` with fully structured metadata.  Unlike
  `beam_logger_sink`, field values arrive as native Erlang terms - integers,
  floats, booleans, binaries - instead of pre-formatted strings.

  ```gleam
  woof.set_event_sink(woof.beam_event_sink)
  ```

- **`set_sinks(List(Sink)) -> Nil`** - register multiple legacy sinks at once.
  Every sink in the list receives the event in order.  `set_sink` remains a
  convenient shorthand for `set_sinks([sink])`.

- **`dev()` / `prod()` presets** - one-call opinionated configuration:

  ```gleam
  woof.dev()   // Debug level, Text format, Auto colors, stdout
  woof.prod()  // Info level, Json format, no colors, beam_logger_sink
  ```

### Notes

- Fully backwards-compatible.  The four original levels retain their semantics;
  `Warning` is now ordinal 3 (was 2) because `Notice` was inserted at 2.  All
  existing `is_enabled` and `set_level` calls behave identically.
- `beam_logger_sink` is unchanged and works with all eight levels; OTP logger
  accepts the new level atoms natively.
- The `beam_event_sink` test helper `test_event_get_int_field/2` is exposed in
  `woof_ffi.erl` for asserting on native integer fields in Erlang tests.

## [1.3.0] - 2026-04-12

> ⚠️ **Breaking change.** The field list type changed from `List(#(String, String))`
> to `List(#(String, FieldValue))`. The compiler will point you to every affected call
> site. Migration is mechanical - see [docs/migration_v1_3.md](docs/migration_v1_3.md).

### Added

- **`FieldValue` type** - `FString(String)` / `FInt(Int)` / `FFloat(Float)` / `FBool(Bool)`.
  Fields now carry their original Gleam types all the way to the sink.

- **`LogEvent` type** - a typed event record with `fields: List(#(String, FieldValue))`,
  `level`, `message`, `timestamp`, and `namespace`. Delivered to every registered `EventSink`.

- **`EventSink` type alias** - `fn(LogEvent) -> Nil`. A second sink channel that receives
  the full typed event without any string serialisation. Registered separately from the
  legacy `Sink` via `set_event_sink`; both fire on every emit.

- **Typed field constructors** - `woof.str`, `woof.int`, `woof.float`, `woof.bool`.
  Each returns `#(String, FieldValue)` with the value wrapped in the appropriate variant.

- **`set_event_sink(EventSink) -> Nil`** - register a typed event sink alongside the
  legacy `Sink`. Both sinks are active simultaneously.

- **`clear_event_sink() -> Nil`** - remove the registered event sink.

- **`test_sink() -> #(EventSink, fn() -> List(LogEvent))`** - a capture sink for tests.
  Returns a `(sink, get)` pair: the sink accumulates events in process-local storage;
  `get()` reads and clears the list. Use it instead of inspecting formatted strings.

### Changed

- **Breaking** - the `fields` parameter of all public logging functions
  (`debug`, `info`, `warning`, `error` and their lazy/tap/log_error variants),
  `with_context`, `set_global_context`, `append_global_context`, and `log` (namespaced)
  changed from `List(#(String, String))` to `List(#(String, FieldValue))`.

  Migration is mechanical. See [docs/migration_v1_3.md](docs/migration_v1_3.md).

- **`field`, `int_field`, `float_field`, `bool_field`** - kept for backwards compatibility.
  Their return type changed from `#(String, String)` to `#(String, FieldValue)`.
  Call sites are unchanged; prefer the new `str`, `int`, `float`, `bool` names going forward.

- **`FBool` string rendering** - `FBool(True)` now serialises to `"true"` and
  `FBool(False)` to `"false"` (lowercase, JSON-consistent).
  Previously `bool_field` produced `"True"` / `"False"` via `gleam/bool.to_string`.

### Notes

- `Entry.fields` stays `List(#(String, String))` - existing `Custom` formatters and
  legacy `Sink` implementations receive strings as before. `FieldValue` is converted
  to string before `Entry` is built; no changes to formatters or `beam_logger_sink`.
- `get_global_context()` now returns `List(#(String, FieldValue))`.

## [1.2.0] - 2026-03-22

### Added

- **`silent_sink/2`** - a builtin sink that completely discards log events, useful for muting logs during test runs.
- **`is_enabled/1`** - check if a specific log level is currently enabled, useful for bypassing expensive work.
- **`get_global_context/0`** and **`append_global_context/1`** - retrieve or incrementally build the global context.
- **`beam_logger_sink/2`** - a new public sink for production OTP
  applications. When set via `woof.set_sink(woof.beam_logger_sink)`, every
  log event is delivered to OTP's `logger` module (available since OTP 21)
  instead of being printed directly to stdout. This means:
  - Applications that use woof no longer need to manage two independent
    logging systems - woof feeds into the same BEAM logger pipeline as
    everything else.
  - Libraries that depend on woof can be silenced or redirected by the host
    application without any changes to the library itself.
  - Other OTP/Elixir components (including Elixir's `Logger`) can observe,
    filter, and re-route woof messages via standard BEAM logger
    configuration.
  - OTP performance features apply: async dispatch, load-shedding, handler
    routing.
  - Each event carries `domain => [woof]` and `fields` metadata so handlers
    and primary filters can target woof events specifically.
  - On the **JavaScript target**, `beam_logger_sink` routes each event to
    the level-appropriate `console` method (`console.debug`, `console.info`,
    `console.warn`, `console.error`) while preserving woof's own formatting.

### Notes

- The default behaviour is **unchanged**: `default_sink` still prints the
  formatted log line directly to stdout via `io.println`. Existing code
  compiled against v1.1.0 or earlier works without modification.
- `beam_logger_sink` is opt-in. Add one line to your application startup to
  enable it: `woof.set_sink(woof.beam_logger_sink)`.
- All other public API (`set_level`, `set_format`, `set_colors`,
  `with_context`, `set_global_context`, pipeline helpers, etc.) is
  unaffected.
- OTP 21 or newer is required for `logger:log/4`; the existing OTP 22+
  minimum already satisfies this.

## [1.1.0] - 2026-03-07

### Added

- Introduced `Sink` type and `set_sink/1` function allowing clients to
  provide custom side-effect handlers (e.g. write to file, send over
  network).
- Public `default_sink/2` function exposed so custom sinks can delegate to
  the original console printer.
- Updated internal state to carry the configured sink; defaults continue to
  behave exactly as before. Fully backwards-compatible with v1.0.x.

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

[1.4.0]: https://hex.pm/packages/woof/1.4.0
[1.3.0]: https://hex.pm/packages/woof/1.3.0
[1.2.0]: https://hex.pm/packages/woof/1.2.0
[1.1.0]: https://hex.pm/packages/woof/1.1.0
[1.0.3]: https://hex.pm/packages/woof/1.0.3
[1.0.2]: https://hex.pm/packages/woof/1.0.2
[1.0.1]: https://hex.pm/packages/woof/1.0.1
[1.0.0]: https://hex.pm/packages/woof/1.0.0
