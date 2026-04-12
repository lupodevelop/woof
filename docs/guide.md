# woof — Guide

Full reference for the woof logging library.  
For a quick overview and installation see the [README](../README.md).  
For upgrading from v1.2 see [migration_v1_3.md](migration_v1_3.md).

---

## Contents

1. [Logging basics](#logging-basics)
2. [Typed fields](#typed-fields)
3. [Levels and filtering](#levels-and-filtering)
4. [Formats](#formats)
5. [Namespaced loggers](#namespaced-loggers)
6. [Context](#context)
7. [Sinks](#sinks)
8. [Testing](#testing)
9. [Lazy evaluation](#lazy-evaluation)
10. [Pipeline helpers](#pipeline-helpers)
11. [Configuration](#configuration)
12. [Colors](#colors)
13. [BEAM logger integration](#beam-logger-integration)
14. [Cross-platform notes](#cross-platform-notes)
15. [API reference](#api-reference)

---

## Logging basics

```gleam
import woof

woof.debug("Cache miss", [woof.str("key", "user:42")])
woof.info("Server started", [woof.str("host", "0.0.0.0"), woof.int("port", 3000)])
woof.warning("Rate limit approaching", [woof.int("current", 89), woof.int("limit", 100)])
woof.error("Connection lost", [woof.str("host", "db-primary")])
```

```
[DEBUG] 10:30:45 Cache miss
  key: user:42
[INFO] 10:30:45 Server started
  host: 0.0.0.0
  port: 3000
[WARN] 10:30:45 Rate limit approaching
  current: 89
  limit: 100
[ERROR] 10:30:45 Connection lost
  host: db-primary
```

No setup, no builder chains. Import and call.

---

## Typed fields

Since v1.3, fields carry their original Gleam types through the entire pipeline.

### Field constructors

| Constructor | Returns | FieldValue variant |
| :--- | :--- | :--- |
| `woof.str("key", "val")` | `#(String, FieldValue)` | `FString` |
| `woof.int("key", 42)` | `#(String, FieldValue)` | `FInt` |
| `woof.float("key", 3.14)` | `#(String, FieldValue)` | `FFloat` |
| `woof.bool("key", True)` | `#(String, FieldValue)` | `FBool` |

```gleam
woof.info("Payment processed", [
  woof.str("order_id", "ORD-42"),
  woof.int("amount_cents", 4999),
  woof.float("tax_rate", 8.5),
  woof.bool("express", True),
])
```

### FieldValue type

`FieldValue` is a public type — pattern-match on it in event sinks and tests:

```gleam
import woof.{FString, FInt, FFloat, FBool}

// In a custom EventSink:
fn my_sink(event: woof.LogEvent) -> Nil {
  list.each(event.fields, fn(field) {
    let #(key, value) = field
    case value {
      FInt(n)    -> send_metric(key, n)
      FBool(b)   -> record_flag(key, b)
      FString(s) -> record_tag(key, s)
      FFloat(f)  -> record_gauge(key, f)
    }
  })
}
```

### Legacy helpers

`field`, `int_field`, `float_field`, `bool_field` are kept for backwards compatibility.
Their call sites are unchanged; they now return `#(String, FieldValue)` instead of
`#(String, String)`. Prefer the new names (`str`, `int`, `float`, `bool`) for new code.

---

## Levels and filtering

Four levels ordered by severity:

| Level | Tag | When to use |
| :--- | :--- | :--- |
| `Debug` | `[DEBUG]` | Detailed traces, only useful during development |
| `Info` | `[INFO]` | Normal operational events |
| `Warning` | `[WARN]` | Unexpected but recoverable situations |
| `Error` | `[ERROR]` | Failures that need attention |

Set the minimum — messages below it are dropped before any allocation:

```gleam
woof.set_level(woof.Warning)

woof.debug("ignored", [])    // dropped
woof.info("ignored", [])     // dropped
woof.warning("shown", [])    // emitted
woof.error("shown", [])      // emitted
```

Check programmatically:

```gleam
case woof.is_enabled(woof.Debug) {
  True  -> woof.debug("snapshot: " <> expensive_dump(state), [])
  False -> Nil
}
```

---

## Formats

### Text (default)

Human-readable, multi-line. Colors apply here only.

```gleam
woof.set_format(woof.Text)
```

```
[INFO] 10:30:45 User signed in
  user_id: u_123
  method: oauth
```

### JSON

One object per line (NDJSON). Ideal for production and log aggregators.

```gleam
woof.set_format(woof.Json)
```

```json
{"level":"info","time":"2026-02-11T10:30:45.123Z","msg":"User signed in","user_id":"u_123","method":"oauth"}
```

Field values are serialised to strings in the JSON output in v1.3. Native JSON number
and boolean support comes in v2.0.

Reserved keys (`level`, `time`, `ns`, `msg`) are prefixed with `_` if a field key
collides with them.

### Compact

Single-line, `key=value` pairs. A readable middle ground for CI logs.

```gleam
woof.set_format(woof.Compact)
```

```
INFO 2026-02-11T10:30:45.123Z User signed in user_id=u_123 method=oauth
```

Values that contain spaces, `=`, or are empty are automatically quoted.

### Custom

Plug in any function that takes an `Entry` and returns a `String`:

```gleam
let my_format = fn(entry: woof.Entry) -> String {
  "[" <> woof.level_name(entry.level) <> "] " <> entry.message
}

woof.set_format(woof.Custom(my_format))
```

The `Entry` type carries `level`, `message`, `fields` (as `List(#(String, String))`),
`namespace`, and `timestamp`. If you need the original `FieldValue` types, use
an `EventSink` instead.

---

## Namespaced loggers

Organise output by component without polluting the message:

```gleam
let db   = woof.new("database")
let http = woof.new("http")

db   |> woof.log(woof.Info,  "Connected",      [woof.str("host", "localhost")])
db   |> woof.log(woof.Debug, "Query executed",  [woof.int("ms", 12)])
http |> woof.log(woof.Info,  "Listening",       [woof.int("port", 8080)])
http |> woof.log(woof.Warning, "Slow response", [woof.int("ms", 1200)])
```

```
[INFO] 10:30:45 database: Connected
  host: localhost
[DEBUG] 10:30:45 database: Query executed
  ms: 12
[INFO] 10:30:45 http: Listening
  port: 8080
[WARN] 10:30:45 http: Slow response
  ms: 1200
```

In JSON output the namespace appears as the `"ns"` key.

---

## Context

### Scoped context

Attach fields to every log call inside a callback. Ideal for request-scoped metadata.

```gleam
use <- woof.with_context([woof.str("request_id", req.id)])

woof.info("Handling request", [])   // includes request_id
do_work()
woof.info("Done", [])               // still includes request_id
```

Contexts nest — inner fields accumulate on top of outer ones:

```gleam
use <- woof.with_context([woof.str("service", "api")])
use <- woof.with_context([woof.str("request_id", id)])

woof.info("Processing", [])
// fields: service, request_id, plus any inline fields
```

On the BEAM, `with_context` uses the process dictionary — concurrent request handlers
never interfere. Fields from all three sources merge in order: global → scoped → inline.

> **JavaScript async users** — `with_context` uses a module-level variable on JS.
> If your callback `await`s (returns a `Promise`), the context may be overwritten by
> another concurrent request. For heavily concurrent async JS code, pass context
> explicitly rather than using `with_context`.

### Global context

Fields that appear on every message, everywhere:

```gleam
woof.set_global_context([
  woof.str("app", "my-service"),
  woof.str("version", "1.3.0"),
  woof.str("env", "production"),
])
```

Build it incrementally:

```gleam
woof.append_global_context([woof.str("region", "eu-west-1")])
```

Read it back:

```gleam
let ctx = woof.get_global_context()
// List(#(String, FieldValue))
```

---

## Sinks

A **sink** is a function that receives each log event and produces side-effects.
woof has two sink channels, both can be active simultaneously.

### Legacy sink — `fn(Entry, String) -> Nil`

Receives the resolved `Entry` (fields as strings) and the pre-formatted string.
This is the original sink type — all built-in sinks use it.

```gleam
woof.set_sink(fn(_entry, formatted) {
  simplifile.append(log_path, formatted <> "\n")
})
```

Built-in legacy sinks:

| Sink | Behaviour |
| :--- | :--- |
| `default_sink` | Prints formatted string to stdout (default) |
| `beam_logger_sink` | Routes through OTP `logger:log/4` on BEAM; `console.*` on JS |
| `silent_sink` | Discards everything |

### Event sink — `fn(LogEvent) -> Nil`

Receives a `LogEvent` with fields as `FieldValue` — no type information is lost.

```gleam
woof.set_event_sink(fn(event: woof.LogEvent) {
  case event.level {
    woof.Error -> alert_pagerduty(event.message, event.fields)
    _          -> Nil
  }
})
```

Both sinks fire independently on every emit. Remove with `clear_event_sink()`.

### Extending built-in sinks

```gleam
// Increment a counter AND write to stdout
woof.set_sink(fn(entry, formatted) {
  metrics.increment(woof.level_name(entry.level) <> ".count")
  woof.default_sink(entry, formatted)
})
```

---

## Testing

Use `test_sink()` to capture typed `LogEvent`s in tests without touching stdout.

```gleam
import woof
import gleeunit/should

pub fn payment_failure_is_logged_test() {
  let #(sink, get) = woof.test_sink()
  woof.set_sink(woof.silent_sink)   // suppress stdout
  woof.set_event_sink(sink)

  process_payment(order_id: "ORD-99", amount: 0)

  let assert [event] = get()
  event.level   |> should.equal(woof.Error)
  event.message |> should.equal("Payment rejected")
  event.fields  |> should.equal([
    #("order_id", woof.FString("ORD-99")),
    #("reason",   woof.FString("zero amount")),
  ])

  woof.clear_event_sink()
}
```

`get()` reads **and clears** the buffer, so repeated calls in one test return
non-overlapping slices.

Because the buffer lives in the process dictionary on BEAM, tests that run in
separate processes (which gleeunit/eunit does by default) are fully isolated.

---

## Lazy evaluation

When building the message or fields is expensive, use the lazy variants.
The thunk is only called if the level is currently enabled — zero allocation otherwise.

```gleam
woof.debug_lazy(fn() { "snapshot: " <> expensive_dump(state) }, [])
```

Available: `debug_lazy`, `info_lazy`, `warning_lazy`, `error_lazy`.

Equivalently, guard with `is_enabled`:

```gleam
case woof.is_enabled(woof.Debug) {
  True  -> woof.debug("dump", [woof.str("data", expensive_dump(state))])
  False -> Nil
}
```

---

## Pipeline helpers

### tap

Log and pass a value through — fits naturally in `|>` chains:

```gleam
fetch_user(id)
|> woof.tap_info("User fetched", [])
|> transform_user()
|> woof.tap_debug("Transformed", [])
|> save_user()
```

Available: `tap_debug`, `tap_info`, `tap_warning`, `tap_error`.

### log_error

Log at Error level only when a `Result` is `Error`, then pass through unchanged:

```gleam
fetch_data(url)
|> woof.log_error("Fetch failed", [woof.str("url", url)])
|> result.unwrap(default_value)
```

### time

Measure and log a block's duration:

```gleam
use <- woof.time("db_query")
database.query(sql)
```

Emits an `Info` message `"db_query completed"` with a `duration_ms` field.
Returns the block's return value unchanged.

---

## Configuration

### One-shot

```gleam
woof.configure(woof.Config(
  level:  woof.Info,
  format: woof.Json,
  colors: woof.Auto,
))
```

### Individual setters

```gleam
woof.set_level(woof.Info)
woof.set_format(woof.Json)
woof.set_colors(woof.Never)
```

---

## Colors

Colors apply to `Text` format only.

| Mode | Behaviour |
| :--- | :--- |
| `Auto` (default) | Colors when stdout is a TTY and `NO_COLOR` is not set |
| `Always` | Force ANSI codes regardless of environment |
| `Never` | Plain text, no escape codes |

```gleam
woof.set_colors(woof.Always)
```

Level colors in `Text` format: Debug → dim grey, Info → blue, Warning → yellow,
Error → bold red.

---

## BEAM logger integration

woof's default sink prints directly to stdout. For production OTP applications,
swap in `beam_logger_sink` once at startup:

```gleam
pub fn main() {
  woof.set_sink(woof.beam_logger_sink)
  // ... rest of startup
}
```

Every log event is then delivered to OTP's `logger` module (OTP 21+).

### Why bother?

Without `beam_logger_sink`:
- Applications run two independent logging systems in parallel.
- It is impossible to silence woof output from a library that uses it.
- BEAM logger features (async dispatch, load-shedding, handler routing) do not apply.
- External collectors (Loki, Datadog, etc.) only see half your logs.

With `beam_logger_sink`: one pipeline, full control.

### Filtering and routing

Each event is tagged `domain => [woof]`:

```erlang
%% Silence all woof output in a specific environment:
logger:add_primary_filter(no_woof,
    {fun logger_filters:domain/2, {stop, sub, [woof]}}).
```

### Metadata carried per event

| Key | Value |
| :--- | :--- |
| `domain` | `[woof]` |
| `fields` | `List(#(String, String))` — serialised field list |
| `namespace` | Logger namespace, if `woof.new/1` was used |

### Output format under beam_logger_sink

OTP's default handler owns the format when `beam_logger_sink` is active.
woof's `Text`/`Compact`/`JSON` setting has no effect on this output.

To customise: reconfigure the default OTP handler.

In Erlang:
```erlang
logger:set_handler_config(default, formatter, {logger_formatter, #{
    template => [level, " ", time, " ", msg, "\n"],
    single_line => true
}}).
```

In Elixir (`config/config.exs`):
```elixir
config :logger, :default_handler,
  formatter: {Logger.Formatter, %{
    format: [:level, " ", :time, " ", :message, "\n"]
  }}
```

### JavaScript target

`beam_logger_sink` on JS routes each event to the level-appropriate `console` method:

| woof level | console method |
| :--- | :--- |
| `Debug` | `console.debug` |
| `Info` | `console.info` |
| `Warning` | `console.warn` |
| `Error` | `console.error` |

woof's own formatting (Text, Compact, JSON, Custom) is preserved on JS.

---

## Cross-platform notes

| Feature | BEAM | JavaScript |
| :--- | :--- | :--- |
| Global state | `persistent_term` | Module-level variable |
| Scoped context | Process dictionary (per-process isolation) | Module-level variable (single-threaded) |
| TTY detection | `io:getopts/1` | `process.stdout.isTTY` |
| Environment vars | `os:getenv/1` | `process.env` |
| Test event buffer | Process dictionary (per-process isolation) | Module-level array |
| `beam_logger_sink` | OTP `logger:log/4` | `console.*` |

Structured fields, namespaces, context, lazy evaluation, and pipeline helpers
behave identically on both targets.

---

## API reference

### Logging

| Function | Signature | Description |
| :--- | :--- | :--- |
| `debug` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Debug |
| `info` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Info |
| `warning` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Warning |
| `error` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Error |
| `debug_lazy` | `(fn() -> String, List(#(String, FieldValue))) -> Nil` | Lazy Debug |
| `info_lazy` | … | Lazy Info |
| `warning_lazy` | … | Lazy Warning |
| `error_lazy` | … | Lazy Error |

### Namespaced loggers

| Function | Signature | Description |
| :--- | :--- | :--- |
| `new` | `(String) -> Logger` | Create a namespaced logger |
| `log` | `(Logger, Level, String, List(#(String, FieldValue))) -> Nil` | Log through a namespace |

### Field constructors

| Function | Returns | Notes |
| :--- | :--- | :--- |
| `str(key, String)` | `#(String, FString)` | Preferred for strings |
| `int(key, Int)` | `#(String, FInt)` | Preferred for integers |
| `float(key, Float)` | `#(String, FFloat)` | Preferred for floats |
| `bool(key, Bool)` | `#(String, FBool)` | Renders as `"true"`/`"false"` |
| `field(key, String)` | `#(String, FString)` | Alias for `str` — legacy |
| `int_field(key, Int)` | `#(String, FInt)` | Alias for `int` — legacy |
| `float_field(key, Float)` | `#(String, FFloat)` | Alias for `float` — legacy |
| `bool_field(key, Bool)` | `#(String, FBool)` | Alias for `bool` — legacy |

### Configuration

| Function | Signature | Description |
| :--- | :--- | :--- |
| `configure` | `(Config) -> Nil` | Set level + format + colors at once |
| `set_level` | `(Level) -> Nil` | Change minimum log level |
| `set_format` | `(Format) -> Nil` | Change output format |
| `set_colors` | `(ColorMode) -> Nil` | Change color mode |
| `is_enabled` | `(Level) -> Bool` | Check if a level is active |

### Sinks

| Function | Signature | Description |
| :--- | :--- | :--- |
| `set_sink` | `(Sink) -> Nil` | Register legacy sink `fn(Entry, String) -> Nil` |
| `set_event_sink` | `(EventSink) -> Nil` | Register typed sink `fn(LogEvent) -> Nil` |
| `clear_event_sink` | `() -> Nil` | Remove the typed event sink |
| `default_sink` | `Sink` | Prints to stdout (default) |
| `beam_logger_sink` | `Sink` | Routes through OTP logger / console.* |
| `silent_sink` | `Sink` | Discards everything |
| `test_sink` | `() -> #(EventSink, fn() -> List(LogEvent))` | Capture sink for tests |

### Context

| Function | Signature | Description |
| :--- | :--- | :--- |
| `with_context` | `(List(#(String, FieldValue)), fn() -> a) -> a` | Scoped fields |
| `set_global_context` | `(List(#(String, FieldValue))) -> Nil` | App-wide fields |
| `get_global_context` | `() -> List(#(String, FieldValue))` | Read current global ctx |
| `append_global_context` | `(List(#(String, FieldValue))) -> Nil` | Add to global ctx |

### Pipeline helpers

| Function | Description |
| :--- | :--- |
| `tap_debug` / `tap_info` / `tap_warning` / `tap_error` | Log and pass value through |
| `log_error` | Log on `Result` `Error`, pass through |
| `time` | Measure and log block duration |

### Utilities

| Function | Description |
| :--- | :--- |
| `format(Entry, Format) -> String` | Format an `Entry` without emitting |
| `level_name(Level) -> String` | `Warning` → `"warning"` |
