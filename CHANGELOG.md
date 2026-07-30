# Changelog for woof

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.9.0] - 2026-07-30

### Added

- **Production-hardening sink wrappers**, composable with `|>` like
  `filter_event_sink`:

  - `redact_event_sink(keys, sink)` masks matching field keys with
    `"[REDACTED]"`, recursively through nested `woof.map` fields.
  - `sample_event_sink(rate, always_keep_above, sink)` keeps a random
    fraction of events below a level floor.
  - `consistent_sample_event_sink(rate, key_field, always_keep_above, sink)`
    does the same, but deterministically by hashing `key_field` (FNV-1a),
    so every log line sharing the same key - e.g. a `trace_id` - is kept
    or dropped together.
  - `rate_limit_event_sink(per_second, sink)` is a token-bucket flood
    guard; each call creates its own independent bucket.
  - `batch_event_sink(max_size, max_interval_ms, sink)` groups events into
    a `fn(List(LogEvent)) -> Nil` batch sink, flushed by size or elapsed
    time - turns N per-event deliveries into one call.

  ```gleam
  woof.set_event_sink(
    otlp_http_sink
    |> woof.redact_event_sink(["password", "authorization"])
    |> woof.rate_limit_event_sink(2000)
    |> woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error)
    |> woof.batch_event_sink(200, 5000),
  )
  ```

- **`error_with(message, err, fields)`** - logs at Error with an
  `error.message` field prepended, aligned with the OTel `error.*`
  convention.

- **`log_at_most(n, key, level, message, fields)`** - logs at most `n`
  times per `key`, for the rest of the process lifetime. No time window,
  no reset - a hard cap, not a rate limit.

- **`test/bench/woof_bench.gleam`** - benchmark comparing each wrapper
  above against a direct sink. See
  [docs/benchmarks.md](docs/benchmarks.md).

- New documentation: [docs/production_setup.md](docs/production_setup.md)
  and [docs/sink_composition.md](docs/sink_composition.md).

Backwards-compatible - no existing API changed.

## [1.8.0] - 2026-05-17

### Added

- **Trace correlation.** Three entry points tie logs to a distributed trace
  using the OpenTelemetry-conventional `trace_id` and `span_id` field names:

  - `with_trace(trace_id, span_id, body)` attaches a trace to every log
    emitted inside `body`. Traces nest and restore on return.
  - `set_trace(logger, trace_id, span_id) -> Logger` returns a logger that
    carries a trace on every call. A logger trace wins over a scoped one.
  - `current_trace() -> Option(#(String, String))` reads the scoped trace.

  ```gleam
  woof.with_trace(trace_id, span_id, fn() {
    woof.info("payment captured", [woof.int("amount_cents", 4200)])
  })
  ```

- **`Format.OtlpJson`** - a new output format producing one
  OpenTelemetry-shaped JSON object per line: `timestamp_unix_nano`,
  `severity_number`, `severity_text`, `body`, `attributes`, and, when
  present, `trace_id`, `span_id`, and `resource`.

- **`format_event_otlp(LogEvent) -> String`** - public OTLP formatter for
  users writing custom sinks.

- **`set_resource(attrs)` / `get_resource()`** - OpenTelemetry resource
  attributes (`service.name`, `service.version`, and so on). Resource
  attributes describe the service rather than any single event and are
  emitted under `resource` by the `OtlpJson` format.

### Changed

- **`Format` has a new `OtlpJson` variant.** Code that pattern-matches
  exhaustively on `Format` needs a branch for it.

- **`Logger` carries an optional trace.** The type is opaque, so this is not
  a breaking change; `child` now inherits the parent's trace.

### Maintenance

- New tests cover trace propagation, OTLP output, and resource attributes.
- `do_emit` builds the `LogEvent` once and routes `Json` / `OtlpJson`
  through the typed formatters.
- `woof_ffi.erl` / `woof_ffi.mjs`: added `get_trace`, `set_trace`, and
  `iso_to_unix_nano`.
- New documentation: `docs/semantic_conventions.md`, `docs/log_levels.md`.

## [1.7.1] - 2026-05-13

### Fixed

- **NaN / Infinity float JSON safety** - `FFloat` values that serialise to
  `"NaN"`, `"Infinity"`, or `"-Infinity"` (reachable on the JavaScript target
  via FFI) now emit `null` in JSON output instead of producing invalid JSON.

- **ANSI escape sanitisation in Text format** - ESC bytes (``) in
  user-controlled message strings, namespace, field keys, and field values are
  stripped before being written to Text output.  This prevents terminal ANSI
  injection when log files are tailed in a terminal.  Json format was already
  safe via `json_escape` (converts ESC to ``).

- **Sink crash isolation** - a panic or unhandled exception in one legacy sink
  or event sink no longer prevents subsequent sinks from receiving the event.
  The error is reported to stderr and execution continues.  Applies to both
  `do_emit` (the normal logging path) and the public `emit` function.

### Maintenance

- New tests cover all three fixes.
- `woof_ffi.erl`: added `safe_call_fn/1` with stderr crash reporting.
- `woof_ffi.mjs`: added `safe_call_fn`, `nan_float`, `infinity_float`.

## [1.7.0] - 2026-04-30

### Added

- **`FList(List(FieldValue))` / `FMap(List(#(String, FieldValue)))` / `FNull`** -
  three new `FieldValue` variants. Nested data (arrays, objects, explicit
  null) can now flow through the entire pipeline as typed values.

- **`woof.list(key, items)` / `woof.map(key, pairs)` / `woof.null(key)`** -
  field constructors for the new variants.

- **`woof.vstr` / `vint` / `vfloat` / `vbool` / `vnull`** - raw-value helpers
  (no key) for ergonomic nested construction inside `FList` / `FMap`:

  ```gleam
  woof.info("order", [
    woof.str("id", "ORD-42"),
    woof.list("items", [woof.vstr("widget"), woof.vstr("gadget")]),
    woof.map("address", [
      #("city", woof.vstr("Bologna")),
      #("zip",  woof.vstr("40121")),
    ]),
  ])
  ```

- **Native JSON output** - the `Json` formatter now emits native JSON types:

  | Field | Before (v1.6) | After (v1.7) |
  | :---- | :------------ | :----------- |
  | `FInt(42)` | `"42"` | `42` |
  | `FBool(True)` | `"true"` | `true` |
  | `FNull` | (n/a) | `null` |
  | `FList([FInt(1), FInt(2)])` | (n/a) | `[1, 2]` |
  | `FMap([("k", FInt(1))])` | (n/a) | `{"k": 1}` |

  Reserved keys (`level`, `time`, `ns`, `msg`) are still prefixed with `_` on
  collision. JSON escaping for strings is unchanged.

- **`format_event_json(LogEvent) -> String`** - public JSON formatter taking
  a `LogEvent` directly. Uses the native typed serialisation.

- **`format_event_text(LogEvent, ColorMode) -> String`** - public Text
  formatter for users writing custom sinks.

- **`format_event_compact(LogEvent) -> String`** - public Compact formatter.

### Changed

- **JSON output is no longer string-stringified.** Programs that grep-parsed
  JSON for stringified numbers / booleans (e.g. `"port":"3000"`) will need
  to update their consumers. Real JSON parsers are unaffected and gain type
  fidelity.

- **Erlang FFI `field_value_to_term/1`** extended for the new variants:
  `FList` becomes a list, `FMap` becomes a map with binary keys, `FNull`
  becomes the atom `null`.

### Maintenance

- **`dev/woof_dev.gleam`** showcase updated. The legacy field helper demo
  (`field` / `int_field` / `float_field` / `bool_field`) was replaced with
  a v1.7 nested-data demo (`list` / `map` / `null` + `v*` raw helpers).
  Running `gleam dev` is now warning-free.
- Removed four trivial unit tests for the deprecated field helpers. The
  helpers are 1-line aliases over `str` / `int` / `float` / `bool`; the
  `@deprecated` attribute itself is the test, and removing the call sites
  silences the build noise.

## [1.6.0] - 2026-04-25

### Added

- **`child(Logger, String) -> Logger`** - create a sub-namespace logger that
  inherits the parent's context.  The child namespace is the parent namespace
  joined with `.`:

  ```gleam
  let http   = woof.new("http")
  let router = woof.child(http, "router")   // namespace: "http.router"
  let get    = woof.child(router, "GET")    // namespace: "http.router.GET"
  ```

  Loggers are immutable. Mutating the child does not affect the parent.

- **`filter_event_sink(fn(LogEvent) -> Bool, EventSink) -> EventSink`** - wrap
  an `EventSink` with a predicate.  Events for which the predicate returns
  `True` are forwarded; the rest are dropped.

  ```gleam
  woof.set_event_sink(woof.filter_event_sink(
    fn(e) { woof.level_to_int(e.level) >= woof.level_to_int(woof.Error) },
    pagerduty_sink,
  ))
  ```

- **`emit(LogEvent) -> Nil`** - dispatch a pre-built `LogEvent` through every
  registered sink.  Does not merge global / scoped context (the event is
  delivered as supplied) and does not enforce the current minimum level.
  Useful for bridging from external logging systems and for replaying captured
  events in tests.

  ```gleam
  woof.emit(woof.LogEvent(
    level: woof.Warning,
    message: "replayed",
    fields: [woof.str("origin", "external")],
    timestamp: ts,
    namespace: None,
  ))
  ```

- **`level_to_int(Level) -> Int`** - now public.  Maps each `Level` to its OTP /
  syslog ordinal (0..7).  Required for writing comparison predicates inside
  `filter_event_sink`, since Gleam custom types don't support `>=` directly.

## [1.5.0] - 2026-04-21

### Added

- **Instanced logger context** - `Logger` now carries per-instance typed context.
  Build a logger that attaches a fixed set of fields to every call, without
  relying on global or process-scoped context:

  ```gleam
  let db = woof.new("database") |> woof.set_context([woof.str("component", "db")])
  db |> woof.log(woof.Info, "Connected", [woof.str("host", "localhost")])
  // fields: component="db", host="localhost"
  ```

  Merge order: `global → scoped → logger.context → inline`.

- **`set_context(Logger, List(#(String, FieldValue))) -> Logger`** - replace the
  logger's context (returns a new immutable `Logger`).

- **`inspect(value: a, label: String) -> a`** - debug-log any Gleam value as its
  string representation, then return the value unchanged. No cost when Debug is off.

  ```gleam
  fetch_user(id)
  |> woof.inspect("user")
  // [DEBUG] user  value="User(id: 42, name: \"alice\")"
  |> transform()
  ```

- **`tap_time(value: a, label: String) -> a`** - debug-log the current monotonic
  timestamp (ms) as an integer field `monotonic_ms`, then pass the value through.
  Chain at two points to bracket a duration in the log:

  ```gleam
  start
  |> woof.tap_time("before_query")   // monotonic_ms = 12345
  |> database.query()
  |> woof.tap_time("after_query")    // monotonic_ms = 12358
  ```

- **`get_level() -> Level`** - read the current minimum log level. Symmetric
  counterpart to `set_level`.

- **`level_from_string(String) -> Result(Level, Nil)`** - parse a level name
  (case-insensitive) into a `Level`. Returns `Error(Nil)` for unknown names.

  ```gleam
  woof.level_from_string("warning")  // Ok(Warning)
  woof.level_from_string("DEBUG")    // Ok(Debug)
  woof.level_from_string("verbose")  // Error(Nil)
  ```

- **`set_level_from_env(String) -> Result(Nil, Nil)`** - read a log level from
  an environment variable and apply it in one call. Returns `Error(Nil)` if the
  variable is absent or its value is not a recognised level name; the current
  level is unchanged in that case.

  ```gleam
  // Application startup
  let _ = woof.set_level_from_env("LOG_LEVEL")
  ```

- **`append_context(Logger, List(#(String, FieldValue))) -> Logger`** - add
  fields to a logger's instance context without replacing it. Complements
  `set_context` (which replaces).

  ```gleam
  let base = woof.new("api") |> woof.set_context([woof.str("service", "api")])
  let req  = base |> woof.append_context([woof.str("request_id", id)])
  ```

### Fixed

- **`time()` duration field** - `duration_ms` is now emitted as `FInt` (integer)
  instead of `FString`. OTP logger and custom event sinks receive the raw integer.

### Deprecated

The following helpers produce a Gleam compiler warning at call sites.
They remain in the public API until v2.0:

| Deprecated | Replacement |
| :--- | :--- |
| `field(key, val)` | `woof.str(key, val)` |
| `int_field(key, val)` | `woof.int(key, val)` |
| `float_field(key, val)` | `woof.float(key, val)` |
| `bool_field(key, val)` | `woof.bool(key, val)` |

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
- Zero-configuration API with four severity levels (`debug`, `info`,
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
- Cross-platform support: identical behaviour on BEAM and JavaScript targets.
- Test suite and documentation in README and project reference.

[1.7.0]: https://hex.pm/packages/woof/1.7.0
[1.6.0]: https://hex.pm/packages/woof/1.6.0
[1.5.0]: https://hex.pm/packages/woof/1.5.0
[1.4.0]: https://hex.pm/packages/woof/1.4.0
[1.3.0]: https://hex.pm/packages/woof/1.3.0
[1.2.0]: https://hex.pm/packages/woof/1.2.0
[1.1.0]: https://hex.pm/packages/woof/1.1.0
[1.0.3]: https://hex.pm/packages/woof/1.0.3
[1.0.2]: https://hex.pm/packages/woof/1.0.2
[1.0.1]: https://hex.pm/packages/woof/1.0.1
[1.0.0]: https://hex.pm/packages/woof/1.0.0
