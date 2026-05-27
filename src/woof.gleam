import gleam/float as gleam_float
import gleam/int as gleam_int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A typed log field value.
///
/// Use the helper constructors (`woof.str`, `woof.int`, `woof.float`,
/// `woof.bool`) to build values rather than constructing these directly.
/// The type is public so that sinks and tests can pattern-match on it.
pub type FieldValue {
  FString(String)
  FInt(Int)
  FFloat(Float)
  FBool(Bool)
  FList(List(FieldValue))
  FMap(List(#(String, FieldValue)))
  FNull
}

/// A fully typed log event, delivered to every registered `EventSink`.
///
/// Unlike `Entry`, fields here carry their original Gleam types - no
/// information is lost before the sink decides how to format or route
/// the event.  Use `test_sink` to capture `LogEvent`s in tests.
pub type LogEvent {
  LogEvent(
    level: Level,
    message: String,
    fields: List(#(String, FieldValue)),
    timestamp: String,
    namespace: Option(String),
  )
}

/// Log severity levels, ordered from least to most severe.
///
/// Only messages at or above the configured minimum level are emitted.
/// The default level is `Debug` (everything is printed).
///
/// The eight levels mirror the OTP logger / syslog severity scale:
///
/// | Level       | Use for                                      |
/// | :---------- | :------------------------------------------- |
/// | `Debug`     | Development traces                           |
/// | `Info`      | Normal application flow                      |
/// | `Notice`    | Significant business events (not errors)     |
/// | `Warning`   | Anomalous but recoverable situations         |
/// | `Error`     | Failures requiring attention                 |
/// | `Critical`  | System degradation, partial failure          |
/// | `Alert`     | Immediate action required                    |
/// | `Emergency` | System is unusable                           |
pub type Level {
  Debug
  Info
  Notice
  Warning
  Error
  Critical
  Alert
  Emergency
}

/// Controls how log output is formatted.
///
/// - `Text` - human-readable lines, great for development.
/// - `Json` - one JSON object per line, great for production and log
///   aggregation tools.
/// - `Compact` - single-line, key=value pairs.  A middle ground between
///   `Text` readability and `Json` parsability.
/// - `OtlpJson` - one OpenTelemetry-shaped JSON object per line, with
///   `severity_number`, `body`, `attributes`, and (when present) `trace_id`,
///   `span_id`, and `resource`.  Use this to feed an OTLP log pipeline.
/// - `Custom` - bring your own formatter. The function receives a fully
///   assembled `Entry` and must return the string to print.  This is the
///   escape hatch for integrating with other formatting or output libraries.
pub type Format {
  Text
  Json
  Compact
  OtlpJson
  Custom(formatter: fn(Entry) -> String)
}

/// A legacy sink receives both the resolved `Entry` and the pre-formatted
/// string produced by the active `Format`.  Field values are serialised to
/// strings before this point, so the types are not available here.
///
/// For full type fidelity use an `EventSink` via `set_event_sink`.
pub type Sink =
  fn(Entry, String) -> Nil

/// A typed sink receives a `LogEvent` with the original `FieldValue` types
/// intact.  Register one with `set_event_sink`.  Use `test_sink` to build a
/// capture sink for assertions in tests.
pub type EventSink =
  fn(LogEvent) -> Nil

/// Controls whether ANSI colors are used in `Text` output.
pub type ColorMode {
  /// Auto-detect: colors are enabled when stdout is a TTY and the
  /// `NO_COLOR` environment variable is not set.
  Auto
  /// Always emit ANSI color codes, even when piped to a file.
  Always
  /// Never emit ANSI color codes.
  Never
}

/// Basic config: level, format, and colors.
/// Pass a `Config` to `woof.configure` to change settings.
pub type Config {
  Config(level: Level, format: Format, colors: ColorMode)
}

/// A fully resolved log entry, ready to be formatted.
///
/// Field values have been serialised to strings at this point.
/// This type is public so that `Custom` formatters can pattern-match on it
/// and arrange the data however they like.
pub type Entry {
  Entry(
    level: Level,
    message: String,
    fields: List(#(String, String)),
    namespace: Option(String),
    timestamp: String,
  )
}

/// A namespaced logger that optionally carries its own per-instance context.
///
/// Create with `woof.new("name")`.  Attach context with `woof.set_context`.
/// Context fields appear after global and scoped context, before inline fields.
///
/// ```gleam
/// let db = woof.new("database") |> woof.set_context([woof.str("pool", "ro")])
/// db |> woof.log(woof.Info, "query ok", [woof.int("ms", 12)])
/// ```
pub opaque type Logger {
  Logger(
    namespace: Option(String),
    context: List(#(String, FieldValue)),
    trace: Option(#(String, String)),
  )
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Replace the current configuration.
///
/// This sets level, format, and color mode at once.  Global context is
/// left untouched - use `set_global_context` if you need to change it.
pub fn configure(config: Config) -> Nil {
  let state = read_state()
  write_state(
    State(
      ..state,
      level: config.level,
      format: config.format,
      colors: config.colors,
    ),
  )
}

/// Change whether text logs use ANSI colors.
/// (Json/Compact formats ignore this setting.)
pub fn set_colors(mode: ColorMode) -> Nil {
  let state = read_state()
  write_state(State(..state, colors: mode))
}

/// Set the minimum log level.
///
/// Messages below this level are silently dropped with near-zero overhead.
pub fn set_level(level: Level) -> Nil {
  let state = read_state()
  write_state(State(..state, level: level))
}

/// Check if a specific log level is currently enabled.
///
/// Useful if you need to perform expensive work before emitting several
/// log messages, and want to skip that work if the level is silenced.
pub fn is_enabled(level: Level) -> Bool {
  let state = read_state()
  should_log(level, state.level)
}

/// Return the current minimum log level.
pub fn get_level() -> Level {
  let state = read_state()
  state.level
}

/// Parse a level name string (case-insensitive) into a `Level`.
///
/// Accepts the eight OTP level names: `"debug"`, `"info"`, `"notice"`,
/// `"warning"`, `"error"`, `"critical"`, `"alert"`, `"emergency"`.
/// Returns `Error(Nil)` for any unrecognised string.
///
/// ```gleam
/// woof.level_from_string("warning")  // Ok(Warning)
/// woof.level_from_string("WARN")     // Error(Nil)
/// ```
pub fn level_from_string(s: String) -> Result(Level, Nil) {
  let level = case string.lowercase(s) {
    "debug" -> Some(Debug)
    "info" -> Some(Info)
    "notice" -> Some(Notice)
    "warning" -> Some(Warning)
    "error" -> Some(Error)
    "critical" -> Some(Critical)
    "alert" -> Some(Alert)
    "emergency" -> Some(Emergency)
    _ -> None
  }
  option.to_result(level, Nil)
}

/// Read a log level from an environment variable and apply it.
///
/// Returns `Ok(Nil)` if the variable is set and its value is a recognised
/// level name (case-insensitive).  Returns `Error(Nil)` if the variable is
/// absent or its value is not a valid level name; in that case the current
/// level is unchanged.
///
/// ```gleam
/// // In your application startup:
/// let _ = woof.set_level_from_env("LOG_LEVEL")
/// ```
pub fn set_level_from_env(var: String) -> Result(Nil, Nil) {
  use val <- result.try(ffi_get_env(var))
  use level <- result.try(level_from_string(val))
  set_level(level)
  Ok(Nil)
}

/// Set the output format.
pub fn set_format(format: Format) -> Nil {
  let state = read_state()
  write_state(State(..state, format: format))
}

/// Set the legacy sink function used to emit formatted logs.
///
/// Replaces all registered sinks with the single given sink.  The legacy sink
/// receives an `Entry` (with string-serialised fields) and the pre-formatted
/// string.  For the original `FieldValue` types use `set_event_sink` instead.
///
/// Equivalent to `set_sinks([sink])`.
pub fn set_sink(sink: Sink) -> Nil {
  set_sinks([sink])
}

/// Register multiple legacy sinks.  Every registered sink is called in order
/// for each emitted log event.  Replaces any previously registered sinks.
///
/// ```gleam
/// woof.set_sinks([woof.default_sink, my_datadog_sink])
/// ```
pub fn set_sinks(sinks: List(Sink)) -> Nil {
  let state = read_state()
  write_state(State(..state, sinks: sinks))
}

/// Register a typed event sink.
///
/// The sink receives a `LogEvent` with fields as `FieldValue` - types are
/// preserved through the entire pipeline.  The legacy `Sink` (if any) is
/// called independently; both are active simultaneously.
///
/// Use `test_sink` to get a capture sink for tests.
pub fn set_event_sink(sink: EventSink) -> Nil {
  let state = read_state()
  write_state(State(..state, event_sink: Some(sink)))
}

/// Remove the registered event sink.
pub fn clear_event_sink() -> Nil {
  let state = read_state()
  write_state(State(..state, event_sink: None))
}

/// Wrap an `EventSink` with a predicate.
///
/// Events for which `predicate(event)` is `True` are forwarded to the wrapped
/// sink; the rest are dropped.  Enables selective routing without writing a
/// full custom sink.
///
/// ```gleam
/// // Route Error+ events to PagerDuty:
/// woof.set_event_sink(woof.filter_event_sink(
///   fn(e) { woof.level_to_int(e.level) >= woof.level_to_int(woof.Error) },
///   pagerduty_sink,
/// ))
/// ```
pub fn filter_event_sink(
  predicate: fn(LogEvent) -> Bool,
  sink: EventSink,
) -> EventSink {
  fn(event: LogEvent) -> Nil {
    case predicate(event) {
      True -> sink(event)
      False -> Nil
    }
  }
}

/// Dispatch a pre-built `LogEvent` through every registered sink.
///
/// Unlike the level-tagged shortcuts (`info`, `error`, ...), `emit` does not
/// merge global or scoped context: the event is delivered exactly as supplied.
/// The current minimum level is *not* enforced - the caller has already
/// decided to emit.
///
/// Useful for bridging from external logging systems and replaying captured
/// events in tests.
///
/// ```gleam
/// let event = woof.LogEvent(
///   level: woof.Warning,
///   message: "replayed",
///   fields: [woof.str("origin", "external")],
///   timestamp: woof_now(),
///   namespace: None,
/// )
/// woof.emit(event)
/// ```
pub fn emit(event: LogEvent) -> Nil {
  let state = read_state()
  let string_fields = fields_to_strings(event.fields)
  let entry =
    Entry(
      level: event.level,
      message: event.message,
      fields: string_fields,
      namespace: event.namespace,
      timestamp: event.timestamp,
    )
  let formatted = format_entry(entry, state.format, state.colors)
  list.each(state.sinks, fn(sink) {
    ffi_safe_call(fn() { sink(entry, formatted) })
  })
  case state.event_sink {
    None -> Nil
    Some(event_sink_fn) -> ffi_safe_call(fn() { event_sink_fn(event) })
  }
}

/// The default sink - prints the formatted log line to standard output.
///
/// This is the out-of-the-box behaviour: zero configuration, beautiful
/// output on any terminal.  Useful when building a custom sink that still
/// wants to write to stdout.
///
/// See `beam_logger_sink` for the OTP-integrated alternative.
pub fn default_sink(_entry: Entry, formatted: String) -> Nil {
  io.println(formatted)
}

/// A sink that routes log events through the official OTP logging pipeline.
///
/// On the **BEAM target** each event is delivered to OTP's `logger` module
/// (available since OTP 21), so the entire BEAM ecosystem can observe,
/// filter, and re-route woof messages:
///
/// - Applications that use woof no longer need a second logging system.
/// - Libraries that depend on woof can be silenced by the host application.
/// - BEAM logger handlers (Loki, Datadog, etc.) receive woof events.
/// - OTP performance features apply: async dispatch, load-shedding, etc.
///
/// Each event is tagged with `domain => [woof]` so handlers and filters
/// can target woof output specifically:
///
/// ```erlang
/// %% Silence all woof output in a specific environment:
/// logger:add_primary_filter(no_woof,
///     {fun logger_filters:domain/2, {stop, sub, [woof]}}).
/// ```
///
/// On the **JavaScript target** the event is passed to the level-appropriate
/// `console` method (`console.debug`, `console.info`, `console.warn`, or
/// `console.error`) - the JS equivalent of routing by severity.
///
/// ## Usage
///
/// Call once at application startup, before any logging:
///
/// ```gleam
/// pub fn main() {
///   woof.set_sink(woof.beam_logger_sink)
///   // ... rest of startup
/// }
/// ```
pub fn beam_logger_sink(entry: Entry, formatted: String) -> Nil {
  ffi_beam_log(
    entry.level,
    entry.message,
    entry.fields,
    entry.namespace,
    formatted,
  )
}

/// A typed event sink that routes log events through the OTP logger with
/// fully structured metadata.  Unlike `beam_logger_sink`, field values
/// are passed as native Erlang terms (`integer()`, `float()`, `boolean()`,
/// `binary()`) rather than pre-formatted strings.
///
/// Register alongside or instead of the legacy `beam_logger_sink`:
///
/// ```gleam
/// woof.set_event_sink(woof.beam_event_sink)
/// ```
///
/// On the JavaScript target the event is routed to the level-appropriate
/// `console` method, same as `beam_logger_sink`.
pub fn beam_event_sink(event: LogEvent) -> Nil {
  ffi_beam_event_log(event.level, event.message, event.fields, event.namespace)
}

/// A sink that does nothing and discards all log events.
///
/// Useful for muting logs entirely, for example during test runs:
/// `woof.set_sink(woof.silent_sink)`
pub fn silent_sink(_entry: Entry, _formatted: String) -> Nil {
  Nil
}

/// Configure woof for **development**: `Debug` level, `Text` format, `Auto`
/// colors, stdout output.  Clears any previously registered sinks.
pub fn dev() -> Nil {
  configure(Config(level: Debug, format: Text, colors: Auto))
  set_sinks([default_sink])
}

/// Configure woof for **production**: `Info` level, `Json` format, no
/// colors, OTP logger output via `beam_logger_sink`.  Clears any previously
/// registered sinks.
pub fn prod() -> Nil {
  configure(Config(level: Info, format: Json, colors: Never))
  set_sinks([beam_logger_sink])
}

/// Build a capture sink for use in tests.
///
/// Returns a pair of `#(sink, get)`:
/// - `sink` is an `EventSink` to register with `set_event_sink`.
/// - `get` reads and clears the captured `LogEvent` list.
///
/// ```gleam
/// let #(sink, get) = woof.test_sink()
/// woof.set_event_sink(sink)
///
/// woof.error("boom", [woof.int("code", 500)])
///
/// let assert [event] = get()
/// event.level   |> should.equal(woof.Error)
/// event.message |> should.equal("boom")
/// event.fields  |> should.equal([#("code", woof.FInt(500))])
/// ```
pub fn test_sink() -> #(EventSink, fn() -> List(LogEvent)) {
  ffi_clear_test_events()
  let sink = fn(event: LogEvent) -> Nil { ffi_push_test_event(event) }
  let get = fn() -> List(LogEvent) { ffi_pop_all_test_events() }
  #(sink, get)
}

// ---------------------------------------------------------------------------
// Logging - plain (no namespace)
// ---------------------------------------------------------------------------

/// Log at Debug level.
pub fn debug(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Debug, message, fields, None, None)
}

/// Log at Info level.
pub fn info(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Info, message, fields, None, None)
}

/// Log at Warning level.
pub fn warning(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Warning, message, fields, None, None)
}

/// Log at Error level.
pub fn error(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Error, message, fields, None, None)
}

/// Log at Notice level.  Use for significant business events that are not
/// errors - successful deployments, config reloads, scheduled task completions.
pub fn notice(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Notice, message, fields, None, None)
}

/// Log at Critical level.  Use when the system is partially degraded and
/// immediate investigation is required.
pub fn critical(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Critical, message, fields, None, None)
}

/// Log at Alert level.  Use when automatic action is insufficient and a
/// human must intervene right away.
pub fn alert(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Alert, message, fields, None, None)
}

/// Log at Emergency level.  Use when the system is completely unusable.
pub fn emergency(message: String, fields: List(#(String, FieldValue))) -> Nil {
  do_log(Emergency, message, fields, None, None)
}

// ---------------------------------------------------------------------------
// Lazy logging
// ---------------------------------------------------------------------------

/// Log at Debug level, evaluating the message only if Debug is enabled.
///
/// Use this when building the message string is expensive.
pub fn debug_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Debug, build, fields, None, None)
}

/// Log at Info level, evaluating the message only if Info is enabled.
pub fn info_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Info, build, fields, None, None)
}

/// Log at Warning level, evaluating the message only if Warning is enabled.
pub fn warning_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Warning, build, fields, None, None)
}

/// Log at Error level, evaluating the message only if Error is enabled.
pub fn error_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Error, build, fields, None, None)
}

/// Log at Notice level, evaluating the message only if Notice is enabled.
pub fn notice_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Notice, build, fields, None, None)
}

/// Log at Critical level, evaluating the message only if Critical is enabled.
pub fn critical_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Critical, build, fields, None, None)
}

/// Log at Alert level, evaluating the message only if Alert is enabled.
pub fn alert_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Alert, build, fields, None, None)
}

/// Log at Emergency level, evaluating the message only if Emergency is enabled.
pub fn emergency_lazy(
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  emit_lazy(Emergency, build, fields, None, None)
}

// ---------------------------------------------------------------------------
// Namespaced logging
// ---------------------------------------------------------------------------

/// Create a namespaced logger.
///
/// The namespace is prepended to every message formatted with `Text` and
/// included as a `"ns"` field in `Json` output.
pub fn new(namespace: String) -> Logger {
  Logger(namespace: Some(namespace), context: [], trace: None)
}

/// Create a child logger that inherits the parent's context and appends a
/// dot-separated suffix to the parent's namespace.
///
/// ```gleam
/// let http   = woof.new("http")
/// let router = woof.child(http, "router")   // namespace: "http.router"
/// let get    = woof.child(router, "GET")    // namespace: "http.router.GET"
/// ```
///
/// Loggers are immutable - mutating the child via `set_context` /
/// `append_context` does not affect the parent.  If the parent has no
/// namespace, the child uses the suffix as its full namespace.  The child
/// inherits the parent's trace, if one was set with `set_trace`.
pub fn child(parent: Logger, suffix: String) -> Logger {
  let namespace = case parent.namespace {
    None -> Some(suffix)
    Some(parent_ns) -> Some(parent_ns <> "." <> suffix)
  }
  Logger(namespace: namespace, context: parent.context, trace: parent.trace)
}

/// Attach per-instance context fields to a logger.
///
/// Context fields appear after global and scoped context, before inline fields.
/// Each call to `set_context` replaces the previous context.
///
/// ```gleam
/// let db = woof.new("database") |> woof.set_context([woof.str("pool", "ro")])
/// ```
pub fn set_context(
  logger: Logger,
  fields: List(#(String, FieldValue)),
) -> Logger {
  Logger(..logger, context: fields)
}

/// Append fields to a logger's instance context without replacing it.
///
/// Unlike `set_context`, which replaces the entire context, `append_context`
/// adds fields at the end of the existing list. Returns a new `Logger`.
///
/// ```gleam
/// let base = woof.new("api") |> woof.set_context([woof.str("service", "api")])
/// let req  = base |> woof.append_context([woof.str("request_id", id)])
/// ```
pub fn append_context(
  logger: Logger,
  fields: List(#(String, FieldValue)),
) -> Logger {
  Logger(..logger, context: list.append(logger.context, fields))
}

/// Attach a trace and span to a logger.
///
/// Every message logged through the returned logger carries `trace_id` and
/// `span_id` fields, using the OpenTelemetry-conventional names.  Returns a
/// new `Logger`; the original is unchanged.
///
/// A logger trace takes precedence over a scoped trace from `with_trace`.
///
/// ```gleam
/// let req = woof.new("http") |> woof.set_trace(trace_id, span_id)
/// req |> woof.log(woof.Info, "request handled", [])
/// ```
pub fn set_trace(logger: Logger, trace_id: String, span_id: String) -> Logger {
  Logger(..logger, trace: Some(#(trace_id, span_id)))
}

/// Log a message through a namespaced logger.
///
/// Logger context fields (set via `set_context`) are prepended to inline fields.
pub fn log(
  logger: Logger,
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
) -> Nil {
  do_log(
    level,
    message,
    list.append(logger.context, fields),
    logger.namespace,
    logger.trace,
  )
}

// ---------------------------------------------------------------------------
// Field constructors - typed (v1.3)
// ---------------------------------------------------------------------------

/// Create a string field.
///
/// ```gleam
/// woof.info("user login", [woof.str("method", "oauth")])
/// ```
pub fn str(key: String, value: String) -> #(String, FieldValue) {
  #(key, FString(value))
}

/// Create an integer field.  The value is preserved as `FInt` through the
/// entire pipeline and only serialised to a string by the legacy sink.
///
/// ```gleam
/// woof.info("request", [woof.int("status", 200)])
/// ```
pub fn int(key: String, value: Int) -> #(String, FieldValue) {
  #(key, FInt(value))
}

/// Create a float field.
///
/// ```gleam
/// woof.info("timing", [woof.float("ms", 12.4)])
/// ```
pub fn float(key: String, value: Float) -> #(String, FieldValue) {
  #(key, FFloat(value))
}

/// Create a boolean field.  Renders as `"true"` / `"false"` (lowercase) in
/// the legacy string path.
///
/// ```gleam
/// woof.info("auth", [woof.bool("cached", True)])
/// ```
pub fn bool(key: String, value: Bool) -> #(String, FieldValue) {
  #(key, FBool(value))
}

/// Create a list field.  Items are themselves `FieldValue`s, so lists may
/// hold mixed-type or nested data.  Use the `v*` raw-value helpers (`vstr`,
/// `vint`, `vfloat`, `vbool`, `vnull`) to build items ergonomically.
///
/// ```gleam
/// woof.info("tags", [woof.list("tags", [woof.vstr("urgent"), woof.vstr("billing")])])
/// ```
pub fn list(key: String, items: List(FieldValue)) -> #(String, FieldValue) {
  #(key, FList(items))
}

/// Create a map (nested object) field.  Pairs use `String` keys and
/// `FieldValue` values, so maps may hold any combination of typed values.
///
/// ```gleam
/// woof.info("login", [woof.map("address", [
///   #("city", woof.vstr("Bologna")),
///   #("zip",  woof.vstr("40121")),
/// ])])
/// ```
pub fn map(
  key: String,
  pairs: List(#(String, FieldValue)),
) -> #(String, FieldValue) {
  #(key, FMap(pairs))
}

/// Create a null field.  Distinct from omitting the key: in JSON output
/// the key appears with `null` as its value.  Useful when the absence of
/// a value is itself meaningful (database NULL, optional field).
pub fn null(key: String) -> #(String, FieldValue) {
  #(key, FNull)
}

// ---------------------------------------------------------------------------
// Raw-value helpers (no key) for nested construction (FList / FMap items)
// ---------------------------------------------------------------------------

/// Wrap a `String` in `FString`.  Use inside `FList` items or `FMap` values.
pub fn vstr(s: String) -> FieldValue {
  FString(s)
}

/// Wrap an `Int` in `FInt`.  Use inside `FList` items or `FMap` values.
pub fn vint(n: Int) -> FieldValue {
  FInt(n)
}

/// Wrap a `Float` in `FFloat`.  Use inside `FList` items or `FMap` values.
pub fn vfloat(f: Float) -> FieldValue {
  FFloat(f)
}

/// Wrap a `Bool` in `FBool`.  Use inside `FList` items or `FMap` values.
pub fn vbool(b: Bool) -> FieldValue {
  FBool(b)
}

/// Return the `FNull` value.  Use inside `FList` items or `FMap` values.
pub fn vnull() -> FieldValue {
  FNull
}

// ---------------------------------------------------------------------------
// Legacy field helpers
// ---------------------------------------------------------------------------

/// Create a string field.
///
/// Prefer `woof.str`. This alias is kept for backwards compatibility.
@deprecated("Use woof.str instead")
pub fn field(key: String, value: String) -> #(String, FieldValue) {
  str(key, value)
}

/// Create a field from an `Int`.
///
/// Prefer `woof.int`. This alias is kept for backwards compatibility.
@deprecated("Use woof.int instead")
pub fn int_field(key: String, value: Int) -> #(String, FieldValue) {
  int(key, value)
}

/// Create a field from a `Float`.
///
/// Prefer `woof.float`. This alias is kept for backwards compatibility.
@deprecated("Use woof.float instead")
pub fn float_field(key: String, value: Float) -> #(String, FieldValue) {
  float(key, value)
}

/// Create a field from a `Bool`.
///
/// Prefer `woof.bool`. This alias is kept for backwards compatibility.
@deprecated("Use woof.bool instead")
pub fn bool_field(key: String, value: Bool) -> #(String, FieldValue) {
  bool(key, value)
}

// ---------------------------------------------------------------------------
// Context (scoped & global)
// ---------------------------------------------------------------------------

/// Run `body` with extra fields attached to every log call inside it.
///
/// Fields from the context are merged with inline fields.  If a key appears
/// in both, the inline value wins (it comes last in the list).
///
/// Contexts can be nested - inner fields accumulate on top of outer ones.
///
/// On the BEAM each process gets its own context (process dictionary), so
/// concurrent request handlers never interfere with each other.
///
/// **Notice for JavaScript async users**: On the JavaScript target, because
/// JS uses cooperative concurrency and is single-threaded, `with_context`
/// modifies a global state. If your callback enters an async sleep/promise,
/// the context might be overwritten by other concurrent tasks. Use with
/// caution in highly concurrent async Node/Deno servers.
pub fn with_context(fields: List(#(String, FieldValue)), body: fn() -> a) -> a {
  let previous = ffi_get_context([])
  ffi_set_context(list.append(previous, fields))
  let value = body()
  ffi_set_context(previous)
  value
}

/// Set fields that appear on **every** log message globally.
///
/// Typically called once at application start.
pub fn set_global_context(fields: List(#(String, FieldValue))) -> Nil {
  let state = read_state()
  write_state(State(..state, global_context: fields))
}

/// Get the current global context fields.
pub fn get_global_context() -> List(#(String, FieldValue)) {
  let state = read_state()
  state.global_context
}

/// Append fields to the global context without replacing the existing ones.
pub fn append_global_context(fields: List(#(String, FieldValue))) -> Nil {
  let current = get_global_context()
  set_global_context(list.append(current, fields))
}

// ---------------------------------------------------------------------------
// Trace correlation (v1.8)
// ---------------------------------------------------------------------------

/// Run `body` with a trace and span attached to every log call inside it.
///
/// Each log emitted within `body` carries `trace_id` and `span_id` fields,
/// using the OpenTelemetry-conventional names.  Traces nest: an inner
/// `with_trace` shadows an outer one and the outer trace is restored when
/// the inner body returns.
///
/// On the BEAM the trace lives in the process dictionary, so concurrent
/// request handlers never share a trace.  The JavaScript caveat from
/// `with_context` applies here too.
///
/// ```gleam
/// woof.with_trace(trace_id, span_id, fn() {
///   woof.info("handling request", [])
/// })
/// ```
pub fn with_trace(trace_id: String, span_id: String, body: fn() -> a) -> a {
  let previous = ffi_get_trace(None)
  ffi_set_trace(Some(#(trace_id, span_id)))
  let value = body()
  ffi_set_trace(previous)
  value
}

/// Read the trace currently in scope, if any.
///
/// Returns `Some(#(trace_id, span_id))` when called inside a `with_trace`
/// body, and `None` otherwise.  A logger trace set with `set_trace` is not
/// reported here; this reads only the scoped trace.
pub fn current_trace() -> Option(#(String, String)) {
  ffi_get_trace(None)
}

// ---------------------------------------------------------------------------
// Resource attributes (v1.8)
// ---------------------------------------------------------------------------

/// Set the OpenTelemetry resource attributes.
///
/// Resource attributes describe the entity producing the logs (the service
/// itself) rather than any single event: `service.name`, `service.version`,
/// `service.instance.id`, and so on.  They are emitted under a `resource`
/// object by the `OtlpJson` format and are otherwise unused.
///
/// Typically called once at application start.
///
/// ```gleam
/// woof.set_resource([
///   woof.str("service.name", "checkout"),
///   woof.str("service.version", "1.8.0"),
/// ])
/// ```
pub fn set_resource(attrs: List(#(String, FieldValue))) -> Nil {
  let state = read_state()
  write_state(State(..state, resource: attrs))
}

/// Get the current OpenTelemetry resource attributes.
pub fn get_resource() -> List(#(String, FieldValue)) {
  let state = read_state()
  state.resource
}

// ---------------------------------------------------------------------------
// Helpers - tap
// ---------------------------------------------------------------------------

/// Log the value at Info level and pass it through.  Fits naturally in
/// pipelines.
pub fn tap_info(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  info(message, fields)
  value
}

/// Log the value at Debug level and pass it through.
pub fn tap_debug(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  debug(message, fields)
  value
}

/// Log the value at Warning level and pass it through.
pub fn tap_warning(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  warning(message, fields)
  value
}

/// Log the value at Error level and pass it through.
pub fn tap_error(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  error(message, fields)
  value
}

/// Log the value at Notice level and pass it through.
pub fn tap_notice(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  notice(message, fields)
  value
}

/// Log the value at Critical level and pass it through.
pub fn tap_critical(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  critical(message, fields)
  value
}

/// Log the value at Alert level and pass it through.
pub fn tap_alert(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  alert(message, fields)
  value
}

/// Log the value at Emergency level and pass it through.
pub fn tap_emergency(
  value: a,
  message: String,
  fields: List(#(String, FieldValue)),
) -> a {
  emergency(message, fields)
  value
}

// ---------------------------------------------------------------------------
// Helpers - Result logging
// ---------------------------------------------------------------------------

/// If the `Result` is `Error`, log the message at Error level and pass
/// the original value through - useful in result pipelines.
pub fn log_error(
  res: Result(a, b),
  message: String,
  fields: List(#(String, FieldValue)),
) -> Result(a, b) {
  case res {
    Ok(_) -> res
    _ -> {
      error(message, fields)
      res
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers - timing
// ---------------------------------------------------------------------------

/// Measure how long `body` takes and log it at Info level.
///
/// Returns whatever `body` returns - the timing log is a side effect.
pub fn time(label: String, body: fn() -> a) -> a {
  let start = ffi_monotonic_now()
  let value = body()
  let elapsed = ffi_monotonic_now() - start
  info(label <> " completed", [int("duration_ms", elapsed)])
  value
}

/// Log the current monotonic timestamp at Debug level and pass the value through.
///
/// Insert at multiple points in a pipeline to measure elapsed time between steps.
/// Each call emits a `monotonic_ms` field. Diff adjacent values for duration.
///
/// ```gleam
/// fetch_data()
/// |> woof.tap_time("after fetch")
/// |> transform()
/// |> woof.tap_time("after transform")
/// ```
pub fn tap_time(value: a, label: String) -> a {
  let ms = ffi_monotonic_now()
  debug(label, [int("monotonic_ms", ms)])
  value
}

/// Log the string representation of a value at Debug level and pass it through.
///
/// Useful for inspecting intermediate values in pipelines without breaking
/// the chain.  The value is rendered via `string.inspect`.
///
/// ```gleam
/// compute()
/// |> woof.inspect("result before filter")
/// |> list.filter(fn(x) { x > 0 })
/// ```
pub fn inspect(value: a, label: String) -> a {
  debug(label, [str("value", string.inspect(value))])
  value
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Format an `Entry` without emitting it.
///
/// Handy for testing formatter output or building custom sink wrappers.
/// Directly constructs `Entry` values with string fields for full control.
pub fn format(entry: Entry, output_format: Format) -> String {
  format_entry(entry, output_format, Never)
}

/// Format a `LogEvent` as JSON with native typed values.
///
/// Numbers, booleans, null, arrays, and nested objects are emitted as their
/// native JSON types (no string-stringification).  Reserved keys (`level`,
/// `time`, `ns`, `msg`) are prefixed with `_` if a user field collides.
pub fn format_event_json(event: LogEvent) -> String {
  format_log_event_json(event)
}

/// Format a `LogEvent` as multi-line `Text`.
///
/// `Text` output stringifies values for readability.  For native typed
/// JSON output use `format_event_json`.
pub fn format_event_text(event: LogEvent, colors: ColorMode) -> String {
  let entry = log_event_to_entry(event)
  format_text(entry, resolve_colors(colors))
}

/// Format a `LogEvent` as a single-line `Compact` `key=value` line.
///
/// Values are stringified, with quoting around values that contain spaces,
/// `=`, or are empty (logfmt-compatible).
pub fn format_event_compact(event: LogEvent) -> String {
  let entry = log_event_to_entry(event)
  format_compact(entry)
}

/// Format a `LogEvent` as a single OpenTelemetry-shaped JSON object.
///
/// The output carries `timestamp_unix_nano`, `severity_number`,
/// `severity_text`, `body`, and `attributes`.  When the event has `trace_id`
/// or `span_id` fields they are promoted to top-level keys rather than left
/// in `attributes`.  The current resource (see `set_resource`) is emitted
/// under `resource` when it is non-empty.
pub fn format_event_otlp(event: LogEvent) -> String {
  format_log_event_otlp(event, get_resource())
}

fn log_event_to_entry(event: LogEvent) -> Entry {
  Entry(
    level: event.level,
    message: event.message,
    fields: fields_to_strings(event.fields),
    namespace: event.namespace,
    timestamp: event.timestamp,
  )
}

fn format_log_event_json(event: LogEvent) -> String {
  let core = case event.namespace {
    Some(ns) -> [
      json_pair("level", level_name(event.level)),
      json_pair("time", event.timestamp),
      json_pair("ns", ns),
      json_pair("msg", event.message),
    ]
    None -> [
      json_pair("level", level_name(event.level)),
      json_pair("time", event.timestamp),
      json_pair("msg", event.message),
    ]
  }

  let user_fields =
    list.map(event.fields, fn(f) {
      let #(k, v) = f
      let safe_k = case k {
        "level" | "time" | "ns" | "msg" -> "_" <> k
        _ -> k
      }
      json_pair_typed(safe_k, v)
    })

  "{" <> string.join(list.append(core, user_fields), ",") <> "}"
}

// ---------------------------------------------------------------------------
// OpenTelemetry OTLP serialisation (v1.8)
// ---------------------------------------------------------------------------

/// Map a `Level` to its OpenTelemetry severity number (the 1..24 scale).
/// woof's eight levels land on the OTel range as follows:
/// Debug 5, Info 9, Notice 10, Warning 13, Error 17, Critical 18,
/// Alert 21, Emergency 24.
fn severity_number(level: Level) -> Int {
  case level {
    Debug -> 5
    Info -> 9
    Notice -> 10
    Warning -> 13
    Error -> 17
    Critical -> 18
    Alert -> 21
    Emergency -> 24
  }
}

/// Map a `Level` to its OpenTelemetry severity text.
fn severity_text(level: Level) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Notice -> "INFO2"
    Warning -> "WARN"
    Error -> "ERROR"
    Critical -> "ERROR2"
    Alert -> "FATAL"
    Emergency -> "FATAL4"
  }
}

fn format_log_event_otlp(
  event: LogEvent,
  resource: List(#(String, FieldValue)),
) -> String {
  let head = [
    "\"timestamp_unix_nano\":" <> ffi_iso_to_unix_nano(event.timestamp),
    "\"severity_number\":" <> gleam_int.to_string(severity_number(event.level)),
    json_pair("severity_text", severity_text(event.level)),
    json_pair("body", event.message),
  ]

  let trace = case otlp_trace_field(event.fields, "trace_id") {
    Some(value) -> [json_pair("trace_id", value)]
    None -> []
  }
  let span = case otlp_trace_field(event.fields, "span_id") {
    Some(value) -> [json_pair("span_id", value)]
    None -> []
  }

  let resource_part = case resource {
    [] -> []
    attrs -> ["\"resource\":" <> json_object_typed(attrs)]
  }

  // trace_id / span_id are promoted to top-level keys, so they are dropped
  // from attributes.  The logger namespace, which has no dedicated OTLP
  // field, is carried as an attribute so it is not lost.
  let event_attributes = list.filter(event.fields, fn(f) { !is_trace_key(f.0) })
  let attributes = case event.namespace {
    Some(ns) -> [#("namespace", FString(ns)), ..event_attributes]
    None -> event_attributes
  }
  let attributes_part = ["\"attributes\":" <> json_object_typed(attributes)]

  let parts = list.flatten([head, trace, span, resource_part, attributes_part])
  "{" <> string.join(parts, ",") <> "}"
}

/// Read a trace field (`trace_id` / `span_id`) from a field list, if it is
/// present and holds a string value.
fn otlp_trace_field(
  fields: List(#(String, FieldValue)),
  key: String,
) -> Option(String) {
  case list.key_find(fields, key) {
    Ok(FString(value)) -> Some(value)
    _ -> None
  }
}

fn is_trace_key(key: String) -> Bool {
  key == "trace_id" || key == "span_id"
}

fn json_object_typed(pairs: List(#(String, FieldValue))) -> String {
  let body =
    pairs
    |> list.map(fn(p) { json_pair_typed(p.0, p.1) })
    |> string.join(",")
  "{" <> body <> "}"
}

/// Return the lowercase name of a level.
///
/// Useful inside `Custom` formatters.
pub fn level_name(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Notice -> "notice"
    Warning -> "warning"
    Error -> "error"
    Critical -> "critical"
    Alert -> "alert"
    Emergency -> "emergency"
  }
}

// ---------------------------------------------------------------------------
// Internals - state
// ---------------------------------------------------------------------------

type State {
  State(
    level: Level,
    format: Format,
    colors: ColorMode,
    global_context: List(#(String, FieldValue)),
    resource: List(#(String, FieldValue)),
    sinks: List(Sink),
    event_sink: Option(EventSink),
  )
}

fn default_state() -> State {
  State(
    level: Debug,
    format: Text,
    colors: Auto,
    global_context: [],
    resource: [],
    sinks: [default_sink],
    event_sink: None,
  )
}

fn read_state() -> State {
  ffi_get_state(default_state())
}

fn write_state(state: State) -> Nil {
  ffi_set_state(state)
}

// ---------------------------------------------------------------------------
// Internals - field serialisation
// ---------------------------------------------------------------------------

fn field_value_to_string(fv: FieldValue) -> String {
  case fv {
    FString(s) -> s
    FInt(n) -> gleam_int.to_string(n)
    FFloat(f) -> gleam_float.to_string(f)
    FBool(True) -> "true"
    FBool(False) -> "false"
    FNull -> "null"
    FList(items) -> {
      let parts = list.map(items, field_value_to_string)
      "[" <> string.join(parts, ",") <> "]"
    }
    FMap(pairs) -> {
      let parts =
        list.map(pairs, fn(p) {
          let #(k, v) = p
          k <> "=" <> field_value_to_string(v)
        })
      "{" <> string.join(parts, ",") <> "}"
    }
  }
}

fn fields_to_strings(
  fields: List(#(String, FieldValue)),
) -> List(#(String, String)) {
  list.map(fields, fn(pair) {
    let #(k, fv) = pair
    #(k, field_value_to_string(fv))
  })
}

// ---------------------------------------------------------------------------
// Internals - emit
// ---------------------------------------------------------------------------

fn do_log(
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
  namespace: Option(String),
  trace: Option(#(String, String)),
) -> Nil {
  let state = read_state()
  case should_log(level, state.level) {
    False -> Nil
    True -> do_emit(state, level, message, fields, namespace, trace)
  }
}

fn emit_lazy(
  level: Level,
  build: fn() -> String,
  fields: List(#(String, FieldValue)),
  namespace: Option(String),
  trace: Option(#(String, String)),
) -> Nil {
  let state = read_state()
  case should_log(level, state.level) {
    False -> Nil
    True -> do_emit(state, level, build(), fields, namespace, trace)
  }
}

fn do_emit(
  state: State,
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
  namespace: Option(String),
  logger_trace: Option(#(String, String)),
) -> Nil {
  let ctx = ffi_get_context([])
  let merged = list.flatten([state.global_context, ctx, fields])
  // A logger trace (set_trace) takes precedence over a scoped trace
  // (with_trace).  When either is present, trace_id and span_id are
  // prepended so every formatter and sink sees them.
  let all_fields = case option.or(logger_trace, ffi_get_trace(None)) {
    Some(#(trace_id, span_id)) -> [
      #("trace_id", FString(trace_id)),
      #("span_id", FString(span_id)),
      ..merged
    ]
    None -> merged
  }
  let timestamp = ffi_now()

  let entry =
    Entry(
      level: level,
      message: message,
      fields: fields_to_strings(all_fields),
      namespace: namespace,
      timestamp: timestamp,
    )
  let log_event =
    LogEvent(
      level: level,
      message: message,
      fields: all_fields,
      timestamp: timestamp,
      namespace: namespace,
    )
  // Json and OtlpJson use native typed serialisation (v1.7 / v1.8);
  // Text / Compact / Custom receive the stringified Entry.
  let formatted = case state.format {
    Json -> format_log_event_json(log_event)
    OtlpJson -> format_log_event_otlp(log_event, state.resource)
    _ -> format_entry(entry, state.format, state.colors)
  }
  list.each(state.sinks, fn(sink) {
    ffi_safe_call(fn() { sink(entry, formatted) })
  })

  case state.event_sink {
    None -> Nil
    Some(event_sink_fn) -> ffi_safe_call(fn() { event_sink_fn(log_event) })
  }
}

fn should_log(msg_level: Level, min_level: Level) -> Bool {
  level_to_int(msg_level) >= level_to_int(min_level)
}

/// Map a `Level` to its OTP / syslog integer ordinal.
///
/// `Debug = 0, Info = 1, Notice = 2, Warning = 3, Error = 4,
/// Critical = 5, Alert = 6, Emergency = 7`.
///
/// Useful for writing comparison predicates (e.g. inside `filter_event_sink`)
/// since Gleam custom types don't support `>=` directly.
///
/// ```gleam
/// fn(e: woof.LogEvent) {
///   woof.level_to_int(e.level) >= woof.level_to_int(woof.Error)
/// }
/// ```
pub fn level_to_int(level: Level) -> Int {
  case level {
    Debug -> 0
    Info -> 1
    Notice -> 2
    Warning -> 3
    Error -> 4
    Critical -> 5
    Alert -> 6
    Emergency -> 7
  }
}

// ---------------------------------------------------------------------------
// Internals - formatting
// ---------------------------------------------------------------------------

fn format_entry(
  entry: Entry,
  output_format: Format,
  colors: ColorMode,
) -> String {
  case output_format {
    Text -> format_text(entry, resolve_colors(colors))
    Json -> format_json(entry)
    Compact -> format_compact(entry)
    OtlpJson -> format_log_event_otlp(entry_to_log_event(entry), get_resource())
    Custom(f) -> f(entry)
  }
}

/// Lift an `Entry` (string fields) back into a `LogEvent` so the typed
/// formatters can run on it.  Field values become `FString`, so the typed
/// path keeps full fidelity only when fed a real `LogEvent`.
fn entry_to_log_event(entry: Entry) -> LogEvent {
  LogEvent(
    level: entry.level,
    message: entry.message,
    fields: list.map(entry.fields, fn(p) { #(p.0, FString(p.1)) }),
    timestamp: entry.timestamp,
    namespace: entry.namespace,
  )
}

fn resolve_colors(mode: ColorMode) -> Bool {
  case mode {
    Always -> True
    Never -> False
    Auto ->
      case ffi_is_tty() {
        False -> False
        True ->
          case no_color_set() {
            True -> False
            False -> True
          }
      }
  }
}

fn no_color_set() -> Bool {
  result.is_ok(ffi_get_env("NO_COLOR"))
}

/// Strip ESC bytes from user-controlled strings in Text output to prevent
/// terminal ANSI injection.  Json format is safe via json_escape.
fn strip_ansi(s: String) -> String {
  string.replace(s, "\u{001B}", "")
}

/// Text format example:
///   [INFO] 10:30:45 Server started
///     port: 3000
///
/// With namespace:
///   [INFO] 10:30:45 database: Connecting
fn format_text(entry: Entry, use_colors: Bool) -> String {
  let tag = level_tag(entry.level)
  let time = short_time(entry.timestamp)
  let ns = case entry.namespace {
    None -> ""
    Some(n) -> strip_ansi(n) <> ": "
  }
  let message = strip_ansi(entry.message)

  let header = case use_colors {
    False -> "[" <> tag <> "] " <> time <> " " <> ns <> message
    True -> {
      let color = level_color(entry.level)
      color
      <> "["
      <> tag
      <> "]"
      <> ansi_reset
      <> " "
      <> ansi_dim
      <> time
      <> ansi_reset
      <> " "
      <> ns
      <> message
    }
  }

  case entry.fields {
    [] -> header
    fields -> {
      let field_lines =
        list.map(fields, fn(pair) {
          let #(k, v) = pair
          "  " <> strip_ansi(k) <> ": " <> strip_ansi(v)
        })
        |> string.join("\n")
      header <> "\n" <> field_lines
    }
  }
}

/// Compact format: single-line, key=value style.
///
///   INFO 2026-02-11T10:30:45Z Server started port=3000 workers=4
fn format_compact(entry: Entry) -> String {
  let tag = level_tag(entry.level)
  let ns = case entry.namespace {
    None -> ""
    Some(n) -> " ns=" <> n
  }

  let msg =
    entry.message
    |> string.replace("\\", "\\\\")
    |> string.replace("\n", "\\n")
    |> string.replace("\r", "\\r")

  let base = tag <> " " <> entry.timestamp <> ns <> " " <> msg
  case entry.fields {
    [] -> base
    fields -> {
      let pairs =
        list.map(fields, fn(f) {
          let #(k, v) = f
          let needs_quotes =
            string.contains(v, " ")
            || string.contains(v, "=")
            || string.contains(v, "\n")
            || string.contains(v, "\r")
            || string.is_empty(v)

          let val = case needs_quotes {
            True ->
              "\""
              <> v
              |> string.replace("\\", "\\\\")
              |> string.replace("\"", "\\\"")
              |> string.replace("\n", "\\n")
              |> string.replace("\r", "\\r")
              <> "\""
            False -> v
          }
          k <> "=" <> val
        })
        |> string.join(" ")
      base <> " " <> pairs
    }
  }
}

/// JSON format - one object per line (NDJSON / JSON Lines).
///
/// Example:
///   {"level":"info","time":"2026-…","msg":"Server started","port":"3000"}
fn format_json(entry: Entry) -> String {
  let core = case entry.namespace {
    Some(ns) -> [
      json_pair("level", level_name(entry.level)),
      json_pair("time", entry.timestamp),
      json_pair("ns", ns),
      json_pair("msg", entry.message),
    ]
    None -> [
      json_pair("level", level_name(entry.level)),
      json_pair("time", entry.timestamp),
      json_pair("msg", entry.message),
    ]
  }

  let user_fields =
    list.map(entry.fields, fn(f) {
      let #(k, v) = f
      let safe_k = case k {
        "level" | "time" | "ns" | "msg" -> "_" <> k
        _ -> k
      }
      json_pair(safe_k, v)
    })

  "{" <> string.join(list.append(core, user_fields), ",") <> "}"
}

fn json_pair(key: String, value: String) -> String {
  "\"" <> json_escape(key) <> "\":\"" <> json_escape(value) <> "\""
}

// ---------------------------------------------------------------------------
// Native JSON serialisation (v1.7) - emit FInt as 42, FBool as true,
// FNull as null, FList as array, FMap as object.  No string-stringification.
// ---------------------------------------------------------------------------

fn field_value_to_json(fv: FieldValue) -> String {
  case fv {
    FString(s) -> "\"" <> json_escape(s) <> "\""
    FInt(n) -> gleam_int.to_string(n)
    FFloat(f) -> {
      let s = gleam_float.to_string(f)
      let lower = string.lowercase(s)
      let non_finite =
        string.starts_with(lower, "nan")
        || string.starts_with(lower, "inf")
        || string.starts_with(lower, "-inf")
      case non_finite {
        True -> "null"
        False -> s
      }
    }
    FBool(True) -> "true"
    FBool(False) -> "false"
    FNull -> "null"
    FList(items) -> {
      let parts = list.map(items, field_value_to_json)
      "[" <> string.join(parts, ",") <> "]"
    }
    FMap(pairs) -> {
      let parts =
        list.map(pairs, fn(p) {
          let #(k, v) = p
          "\"" <> json_escape(k) <> "\":" <> field_value_to_json(v)
        })
      "{" <> string.join(parts, ",") <> "}"
    }
  }
}

fn json_pair_typed(key: String, value: FieldValue) -> String {
  "\"" <> json_escape(key) <> "\":" <> field_value_to_json(value)
}

fn json_escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\u{001B}", "\\u001b")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
  |> string.replace("\u{0008}", "\\b")
  |> string.replace("\u{000C}", "\\f")
}

fn level_tag(level: Level) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Notice -> "NOTICE"
    Warning -> "WARN"
    Error -> "ERROR"
    Critical -> "CRIT"
    Alert -> "ALERT"
    Emergency -> "EMERG"
  }
}

/// Extract HH:MM:SS from an ISO 8601 timestamp.
/// "2026-02-11T10:30:45.123Z" → "10:30:45"
fn short_time(iso: String) -> String {
  string.slice(iso, 11, 8)
}

// ---------------------------------------------------------------------------
// ANSI helpers
// ---------------------------------------------------------------------------

const ansi_reset = "\u{001b}[0m"

const ansi_dim = "\u{001b}[90m"

const ansi_cyan = "\u{001b}[36m"

const ansi_yellow = "\u{001b}[33m"

const ansi_blue = "\u{001b}[34m"

const ansi_red_bold = "\u{001b}[1;31m"

const ansi_magenta_bold = "\u{001b}[1;35m"

fn level_color(level: Level) -> String {
  case level {
    Debug -> ansi_dim
    Info -> ansi_blue
    Notice -> ansi_cyan
    Warning -> ansi_yellow
    Error -> ansi_red_bold
    Critical -> ansi_magenta_bold
    Alert -> ansi_red_bold
    Emergency -> ansi_red_bold
  }
}

// ---------------------------------------------------------------------------
// FFI bindings
// ---------------------------------------------------------------------------

@external(erlang, "woof_ffi", "get_state")
@external(javascript, "./woof_ffi.mjs", "get_state")
fn ffi_get_state(default: State) -> State

@external(erlang, "woof_ffi", "set_state")
@external(javascript, "./woof_ffi.mjs", "set_state")
fn ffi_set_state(state: State) -> Nil

@external(erlang, "woof_ffi", "get_context")
@external(javascript, "./woof_ffi.mjs", "get_context")
fn ffi_get_context(
  default: List(#(String, FieldValue)),
) -> List(#(String, FieldValue))

@external(erlang, "woof_ffi", "set_context")
@external(javascript, "./woof_ffi.mjs", "set_context")
fn ffi_set_context(ctx: List(#(String, FieldValue))) -> Nil

@external(erlang, "woof_ffi", "now")
@external(javascript, "./woof_ffi.mjs", "now")
fn ffi_now() -> String

@external(erlang, "woof_ffi", "monotonic_now")
@external(javascript, "./woof_ffi.mjs", "monotonic_now")
fn ffi_monotonic_now() -> Int

@external(erlang, "woof_ffi", "is_tty")
@external(javascript, "./woof_ffi.mjs", "is_tty")
fn ffi_is_tty() -> Bool

@external(erlang, "woof_ffi", "get_env")
@external(javascript, "./woof_ffi.mjs", "get_env")
fn ffi_get_env(name: String) -> Result(String, Nil)

@external(erlang, "woof_ffi", "beam_log")
@external(javascript, "./woof_ffi.mjs", "beam_log")
fn ffi_beam_log(
  level: Level,
  message: String,
  fields: List(#(String, String)),
  namespace: Option(String),
  formatted: String,
) -> Nil

@external(erlang, "woof_ffi", "push_test_event")
@external(javascript, "./woof_ffi.mjs", "push_test_event")
fn ffi_push_test_event(event: LogEvent) -> Nil

@external(erlang, "woof_ffi", "pop_all_test_events")
@external(javascript, "./woof_ffi.mjs", "pop_all_test_events")
fn ffi_pop_all_test_events() -> List(LogEvent)

@external(erlang, "woof_ffi", "clear_test_events")
@external(javascript, "./woof_ffi.mjs", "clear_test_events")
fn ffi_clear_test_events() -> Nil

@external(erlang, "woof_ffi", "beam_event_log")
@external(javascript, "./woof_ffi.mjs", "beam_event_log")
fn ffi_beam_event_log(
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
  namespace: Option(String),
) -> Nil

@external(erlang, "woof_ffi", "safe_call_fn")
@external(javascript, "./woof_ffi.mjs", "safe_call_fn")
fn ffi_safe_call(f: fn() -> Nil) -> Nil

@external(erlang, "woof_ffi", "get_trace")
@external(javascript, "./woof_ffi.mjs", "get_trace")
fn ffi_get_trace(
  default: Option(#(String, String)),
) -> Option(#(String, String))

@external(erlang, "woof_ffi", "set_trace")
@external(javascript, "./woof_ffi.mjs", "set_trace")
fn ffi_set_trace(trace: Option(#(String, String))) -> Nil

@external(erlang, "woof_ffi", "iso_to_unix_nano")
@external(javascript, "./woof_ffi.mjs", "iso_to_unix_nano")
fn ffi_iso_to_unix_nano(iso: String) -> String
