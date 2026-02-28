import gleam/bool
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Log severity levels, ordered from least to most severe.
///
/// Only messages at or above the configured minimum level are emitted.
/// The default level is `Debug` (everything is printed).
pub type Level {
  Debug
  Info
  Warning
  Error
}

/// Controls how log output is formatted.
///
/// - `Text` — human-readable lines, great for development.
/// - `Json` — one JSON object per line, great for production and log
///   aggregation tools.
/// - `Compact` — single-line, key=value pairs.  A middle ground between
///   `Text` readability and `Json` parsability.
/// - `Custom` — bring your own formatter. The function receives a fully
///   assembled `Entry` and must return the string to print.  This is the
///   escape hatch for integrating with other formatting or output libraries.
pub type Format {
  Text
  Json
  Compact
  Custom(formatter: fn(Entry) -> String)
}

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

/// Top-level configuration.
///
/// ```gleam
/// woof.configure(woof.Config(
///   level: woof.Info,
///   format: woof.Json,
///   colors: woof.Auto,
/// ))
/// ```
pub type Config {
  Config(level: Level, format: Format, colors: ColorMode)
}

/// A fully resolved log entry, ready to be formatted.
///
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

/// An opaque logger handle carrying a namespace.
///
/// Create one with `new` and pass it to `log`:
///
/// ```gleam
/// let db = woof.new("database")
/// db |> woof.log(woof.Info, "Connected", [])
/// ```
pub opaque type Logger {
  Logger(namespace: String)
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Replace the current configuration.
///
/// This sets level, format, and color mode at once.  Global context is
/// left untouched — use `set_global_context` if you need to change it.
///
/// ```gleam
/// woof.configure(woof.Config(
///   level: woof.Info,
///   format: woof.Json,
///   colors: woof.Auto,
/// ))
/// ```
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

/// Set the color mode.
///
/// Colors only affect `Text` output — `Json` and `Compact` are never colored.
///
/// ```gleam
/// woof.set_colors(woof.Never)
/// ```
pub fn set_colors(mode: ColorMode) -> Nil {
  let state = read_state()
  write_state(State(..state, colors: mode))
}

/// Set the minimum log level.
///
/// Messages below this level are silently dropped with near-zero overhead.
///
/// ```gleam
/// woof.set_level(woof.Warning)
/// ```
pub fn set_level(level: Level) -> Nil {
  let state = read_state()
  write_state(State(..state, level: level))
}

/// Set the output format.
///
/// ```gleam
/// woof.set_format(woof.Json)
/// ```
pub fn set_format(format: Format) -> Nil {
  let state = read_state()
  write_state(State(..state, format: format))
}

// ---------------------------------------------------------------------------
// Logging — plain aka (no namespace)
// ---------------------------------------------------------------------------

/// Log at Debug level.
///
/// ```gleam
/// woof.debug("Cache hit", [#("key", cache_key)])
/// ```
pub fn debug(message: String, fields: List(#(String, String))) -> Nil {
  emit(Debug, message, fields, None)
}

/// Log at Info level.
///
/// ```gleam
/// woof.info("User signed in", [#("user_id", id)])
/// ```
pub fn info(message: String, fields: List(#(String, String))) -> Nil {
  emit(Info, message, fields, None)
}

/// Log at Warning level.
///
/// ```gleam
/// woof.warning("Rate limit at 90 %", [#("limit", "100/min")])
/// ```
pub fn warning(message: String, fields: List(#(String, String))) -> Nil {
  emit(Warning, message, fields, None)
}

/// Log at Error level.
///
/// ```gleam
/// woof.error("Connection lost", [#("host", "db01")])
/// ```
pub fn error(message: String, fields: List(#(String, String))) -> Nil {
  emit(Error, message, fields, None)
}

// ---------------------------------------------------------------------------
// Lazy logging
// ---------------------------------------------------------------------------

/// Log at Debug level, evaluating the message only if Debug is enabled.
///
/// Use this when building the message string is expensive.
///
/// ```gleam
/// woof.debug_lazy(fn() { expensive_debug_dump() }, [])
/// ```
pub fn debug_lazy(build: fn() -> String, fields: List(#(String, String))) -> Nil {
  emit_lazy(Debug, build, fields, None)
}

/// Log at Info level, evaluating the message only if Info is enabled.
pub fn info_lazy(build: fn() -> String, fields: List(#(String, String))) -> Nil {
  emit_lazy(Info, build, fields, None)
}

/// Log at Warning level, evaluating the message only if Warning is enabled.
pub fn warning_lazy(
  build: fn() -> String,
  fields: List(#(String, String)),
) -> Nil {
  emit_lazy(Warning, build, fields, None)
}

/// Log at Error level, evaluating the message only if Error is enabled.
pub fn error_lazy(build: fn() -> String, fields: List(#(String, String))) -> Nil {
  emit_lazy(Error, build, fields, None)
}

// ---------------------------------------------------------------------------
// Namespaced logging
// ---------------------------------------------------------------------------

/// Create a namespaced logger.
///
/// The namespace is prepended to every message formatted with `Text` and
/// included as a `"ns"` field in `Json` output.
///
/// ```gleam
/// let log = woof.new("database")
/// log |> woof.log(woof.Info, "Connected", [#("host", "localhost")])
/// ```
pub fn new(namespace: String) -> Logger {
  Logger(namespace: namespace)
}

/// Log a message through a namespaced logger.
///
/// ```gleam
/// let log = woof.new("http")
/// log |> woof.log(woof.Warning, "Slow response", [#("ms", "1200")])
/// ```
pub fn log(
  logger: Logger,
  level: Level,
  message: String,
  fields: List(#(String, String)),
) -> Nil {
  emit(level, message, fields, Some(logger.namespace))
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Field helpers — automatic type conversion
// ---------------------------------------------------------------------------

/// Create a string field. Same as writing `#(key, value)` directly, but
/// reads nicely alongside the typed helpers.
///
/// ```gleam
/// woof.info("Request", [woof.field("path", "/api/users")])
/// ```
pub fn field(key: String, value: String) -> #(String, String) {
  #(key, value)
}

/// Create a field from an `Int`.
///
/// ```gleam
/// woof.info("Response", [woof.int_field("status", 200)])
/// ```
pub fn int_field(key: String, value: Int) -> #(String, String) {
  #(key, int.to_string(value))
}

/// Create a field from a `Float`.
///
/// ```gleam
/// woof.info("Timing", [woof.float_field("duration_ms", 12.5)])
/// ```
pub fn float_field(key: String, value: Float) -> #(String, String) {
  #(key, float.to_string(value))
}

/// Create a field from a `Bool`.
///
/// ```gleam
/// woof.info("Cache", [woof.bool_field("hit", True)])
/// ```
pub fn bool_field(key: String, value: Bool) -> #(String, String) {
  #(key, bool.to_string(value))
}

// ---------------------------------------------------------------------------
// Context (scoped & global)
// ---------------------------------------------------------------------------

/// Run `body` with extra fields attached to every log call inside it.
///
/// Fields from the context are merged with inline fields.  If a key appears
/// in both, the inline value wins (it comes last in the list).
///
/// Contexts can be nested — inner fields accumulate on top of outer ones.
///
/// On the BEAM each process gets its own context (process dictionary), so
/// concurrent request handlers never interfere with each other.
///
/// ```gleam
/// use <- woof.with_context([#("request_id", req.id)])
/// woof.info("Processing", [])   // includes request_id automatically
/// ```
pub fn with_context(fields: List(#(String, String)), body: fn() -> a) -> a {
  let previous = ffi_get_context([])
  ffi_set_context(list.append(previous, fields))
  let result = body()
  ffi_set_context(previous)
  result
}

/// Set fields that appear on **every** log message globally.
///
/// Typically called once at application start.
///
/// ```gleam
/// woof.set_global_context([
///   #("app", "my-service"),
///   #("version", "1.2.0"),
/// ])
/// ```
pub fn set_global_context(fields: List(#(String, String))) -> Nil {
  let state = read_state()
  write_state(State(..state, global_context: fields))
}

// ---------------------------------------------------------------------------
// Helpers — tap
// ---------------------------------------------------------------------------

/// Log the value at Info level and pass it through.  Fits naturally in
/// pipelines.
///
/// ```gleam
/// fetch_user(id)
/// |> woof.tap_info("Fetched user", [])
/// |> transform_user()
/// ```
pub fn tap_info(value: a, message: String, fields: List(#(String, String))) -> a {
  info(message, fields)
  value
}

/// Log the value at Debug level and pass it through.
pub fn tap_debug(
  value: a,
  message: String,
  fields: List(#(String, String)),
) -> a {
  debug(message, fields)
  value
}

/// Log the value at Warning level and pass it through.
pub fn tap_warning(
  value: a,
  message: String,
  fields: List(#(String, String)),
) -> a {
  warning(message, fields)
  value
}

/// Log the value at Error level and pass it through.
pub fn tap_error(
  value: a,
  message: String,
  fields: List(#(String, String)),
) -> a {
  error(message, fields)
  value
}

// ---------------------------------------------------------------------------
// Helpers — Result logging
// ---------------------------------------------------------------------------

/// If the `Result` is `Error`, log the message at Error level and pass
/// the original value through — useful in result pipelines.
///
/// ```gleam
/// fetch_data()
/// |> woof.log_error("Failed to fetch data", [])
/// |> result.unwrap(default)
/// ```
pub fn log_error(
  res: Result(a, b),
  message: String,
  fields: List(#(String, String)),
) -> Result(a, b) {
  case result.is_ok(res) {
    True -> res
    False -> {
      error(message, fields)
      res
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers — timing
// ---------------------------------------------------------------------------

/// Measure how long `body` takes and log it at Info level.
///
/// Returns whatever `body` returns — the timing log is a side effect.
///
/// ```gleam
/// use <- woof.time("db_query")
/// database.query(sql)
/// ```
pub fn time(label: String, body: fn() -> a) -> a {
  let start = ffi_monotonic_now()
  let result = body()
  let elapsed = ffi_monotonic_now() - start
  info(label <> " completed", [
    #("duration_ms", int.to_string(elapsed)),
  ])
  result
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Format an entry without emitting it.
///
/// Handy for testing, previews, or sending formatted output to a custom
/// sink (file, HTTP, etc.).
///
/// ```gleam
/// let line = woof.format(entry, woof.Json)
/// ```
pub fn format(entry: Entry, output_format: Format) -> String {
  format_entry(entry, output_format, Never)
}

/// Return the lowercase name of a level.
///
/// Useful inside `Custom` formatters.
///
/// ```gleam
/// woof.level_name(woof.Warning)  // -> "warning"
/// ```
pub fn level_name(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warning -> "warning"
    Error -> "error"
  }
}

// ---------------------------------------------------------------------------
// Internals — state
// ---------------------------------------------------------------------------

type State {
  State(
    level: Level,
    format: Format,
    colors: ColorMode,
    global_context: List(#(String, String)),
  )
}

fn default_state() -> State {
  State(level: Debug, format: Text, colors: Auto, global_context: [])
}

fn read_state() -> State {
  ffi_get_state(default_state())
}

fn write_state(state: State) -> Nil {
  ffi_set_state(state)
}

// ---------------------------------------------------------------------------
// Internals — emit
// ---------------------------------------------------------------------------

fn emit(
  level: Level,
  message: String,
  fields: List(#(String, String)),
  namespace: Option(String),
) -> Nil {
  let state = read_state()
  case should_log(level, state.level) {
    False -> Nil
    True -> do_emit(state, level, message, fields, namespace)
  }
}

fn emit_lazy(
  level: Level,
  build: fn() -> String,
  fields: List(#(String, String)),
  namespace: Option(String),
) -> Nil {
  let state = read_state()
  case should_log(level, state.level) {
    False -> Nil
    True -> do_emit(state, level, build(), fields, namespace)
  }
}

fn do_emit(
  state: State,
  level: Level,
  message: String,
  fields: List(#(String, String)),
  namespace: Option(String),
) -> Nil {
  let ctx = ffi_get_context([])
  let all_fields = list.flatten([state.global_context, ctx, fields])
  let entry =
    Entry(
      level: level,
      message: message,
      fields: all_fields,
      namespace: namespace,
      timestamp: ffi_now(),
    )
  format_entry(entry, state.format, state.colors)
  |> io.println
}

fn should_log(msg_level: Level, min_level: Level) -> Bool {
  level_to_int(msg_level) >= level_to_int(min_level)
}

fn level_to_int(level: Level) -> Int {
  case level {
    Debug -> 0
    Info -> 1
    Warning -> 2
    Error -> 3
  }
}

// ---------------------------------------------------------------------------
// Internals — formatting
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
    Custom(f) -> f(entry)
  }
}

/// Decide whether to actually use colors given the mode.
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
    Some(n) -> n <> ": "
  }

  let header = case use_colors {
    False -> "[" <> tag <> "] " <> time <> " " <> ns <> entry.message
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
      <> entry.message
    }
  }

  case entry.fields {
    [] -> header
    fields -> {
      let field_lines =
        list.map(fields, fn(pair) {
          let #(k, v) = pair
          "  " <> k <> ": " <> v
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
  let base = tag <> " " <> entry.timestamp <> ns <> " " <> entry.message
  case entry.fields {
    [] -> base
    fields -> {
      let pairs =
        list.map(fields, fn(f) {
          let #(k, v) = f
          k <> "=" <> v
        })
        |> string.join(" ")
      base <> " " <> pairs
    }
  }
}

/// JSON format — one object per line (NDJSON / JSON Lines).
///
/// Example:
///   {"level":"info","time":"2026-…","msg":"Server started","port":"3000"}
fn format_json(entry: Entry) -> String {
  let base = [
    json_pair("level", level_name(entry.level)),
    json_pair("time", entry.timestamp),
  ]
  let with_ns = case entry.namespace {
    None -> base
    Some(ns) -> list.append(base, [json_pair("ns", ns)])
  }
  let with_msg = list.append(with_ns, [json_pair("msg", entry.message)])
  let with_fields =
    list.append(
      with_msg,
      list.map(entry.fields, fn(f) {
        let #(k, v) = f
        json_pair(k, v)
      }),
    )

  "{" <> string.join(with_fields, ",") <> "}"
}

fn json_pair(key: String, value: String) -> String {
  "\"" <> json_escape(key) <> "\":\"" <> json_escape(value) <> "\""
}

fn json_escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
  |> string.replace("\u{0008}", "\\b")
  |> string.replace("\u{000C}", "\\f")
}

fn level_tag(level: Level) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARN"
    Error -> "ERROR"
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

const ansi_yellow = "\u{001b}[33m"

const ansi_blue = "\u{001b}[34m"

const ansi_red_bold = "\u{001b}[1;31m"

fn level_color(level: Level) -> String {
  case level {
    Debug -> ansi_dim
    Info -> ansi_blue
    Warning -> ansi_yellow
    Error -> ansi_red_bold
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
fn ffi_get_context(default: List(#(String, String))) -> List(#(String, String))

@external(erlang, "woof_ffi", "set_context")
@external(javascript, "./woof_ffi.mjs", "set_context")
fn ffi_set_context(ctx: List(#(String, String))) -> Nil

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
