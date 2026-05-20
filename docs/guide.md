# woof : Guide

Full reference for the woof logging library.  
For a quick overview and installation see the [README](../README.md).  
For upgrading from v1.2 see [migration_v1_3.md](migration_v1_3.md).

---

## Contents

1. [Logging basics](#logging-basics)
2. [Typed fields](#typed-fields)
3. [Levels and filtering](#levels-and-filtering)
4. [Formats](#formats)
5. [Trace correlation](#trace-correlation-v18)
6. [Resource attributes](#resource-attributes-v18)
7. [Namespaced loggers](#namespaced-loggers)
8. [Context](#context)
9. [Sinks](#sinks)
10. [Testing](#testing)
11. [Lazy evaluation](#lazy-evaluation)
12. [Pipeline helpers](#pipeline-helpers)
13. [Configuration](#configuration)
14. [Colors](#colors)
15. [BEAM logger integration](#beam-logger-integration)
16. [Cross-platform notes](#cross-platform-notes)
17. [API reference](#api-reference)

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
| `woof.list("key", items)` | `#(String, FieldValue)` | `FList` (v1.7) |
| `woof.map("key", pairs)` | `#(String, FieldValue)` | `FMap` (v1.7) |
| `woof.null("key")` | `#(String, FieldValue)` | `FNull` (v1.7) |

Raw value helpers (no key) for nested construction inside `FList` items
and `FMap` values:

| Helper | Returns | Wraps |
| :--- | :--- | :--- |
| `woof.vstr("v")` | `FieldValue` | `FString` |
| `woof.vint(42)` | `FieldValue` | `FInt` |
| `woof.vfloat(3.14)` | `FieldValue` | `FFloat` |
| `woof.vbool(True)` | `FieldValue` | `FBool` |
| `woof.vnull()` | `FieldValue` | `FNull` |

```gleam
woof.info("Payment processed", [
  woof.str("order_id", "ORD-42"),
  woof.int("amount_cents", 4999),
  woof.float("tax_rate", 8.5),
  woof.bool("express", True),
])
```

### FieldValue type

`FieldValue` is a public type - pattern-match on it in event sinks and tests:

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

### Nested data (v1.7)

Lists, nested objects, and explicit null pass through as typed values:

```gleam
woof.info("order", [
  woof.str("id", "ORD-42"),
  woof.list("items", [
    woof.vstr("widget"),
    woof.vstr("gadget"),
  ]),
  woof.map("address", [
    #("city", woof.vstr("Bologna")),
    #("zip", woof.vstr("40121")),
  ]),
  woof.null("coupon"),
])
```

JSON output emits real types (`"items":["widget","gadget"]`,
`"address":{...}`, `"coupon":null`). The Erlang FFI maps `FList` to a list,
`FMap` to a map with binary keys, and `FNull` to the atom `null`, so OTP
logger handlers and Elixir consumers see native Erlang terms.

`Text` and `Compact` formats stringify nested data for readability:
`[1,2,3]`, `{city=Bologna,zip=40121}`. For full type fidelity use `Json`
or `format_event_json`.

### Legacy helpers

`field`, `int_field`, `float_field`, `bool_field` are **deprecated** as of v1.5.
The Gleam compiler emits a warning at every call site.  They remain in the
public API until v2.0; migration is mechanical:

| Deprecated | Replacement |
| :--- | :--- |
| `field(key, val)` | `woof.str(key, val)` |
| `int_field(key, val)` | `woof.int(key, val)` |
| `float_field(key, val)` | `woof.float(key, val)` |
| `bool_field(key, val)` | `woof.bool(key, val)` |

---

## Levels and filtering

Eight levels ordered by severity - matching the OTP / syslog scale:

| Level | Tag | When to use |
| :--- | :--- | :--- |
| `Debug` | `[DEBUG]` | Detailed traces, only useful during development |
| `Info` | `[INFO]` | Normal operational events |
| `Notice` | `[NOTICE]` | Significant business events that are not errors |
| `Warning` | `[WARN]` | Unexpected but recoverable situations |
| `Error` | `[ERROR]` | Failures that need attention |
| `Critical` | `[CRIT]` | System degradation, partial failure |
| `Alert` | `[ALERT]` | Immediate human action required |
| `Emergency` | `[EMERG]` | System is completely unusable |

Set the minimum - messages below it are dropped before any allocation:

```gleam
woof.set_level(woof.Warning)

woof.debug("ignored", [])    // dropped
woof.info("ignored", [])     // dropped
woof.notice("ignored", [])   // dropped (Notice = 2, Warning = 3)
woof.warning("shown", [])    // emitted
woof.error("shown", [])      // emitted
woof.critical("shown", [])   // emitted
```

All eight levels have corresponding logging functions and lazy variants:

```gleam
woof.notice("Deployment complete", [woof.str("version", "1.4.0")])
woof.critical("Database replica lag", [woof.int("lag_ms", 5000)])
woof.alert("Disk almost full", [woof.int("free_gb", 1)])
woof.emergency("Cannot write to disk", [])

// lazy variants - thunk is only evaluated if the level is enabled
woof.critical_lazy(fn() { expensive_diagnostic() }, [])
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

Field values are emitted as **native JSON types** since v1.7:

```json
{"level":"info","time":"2026-04-30T10:30:45.123Z","msg":"Payment ok","amount_cents":4999,"express":true,"items":["widget","gadget"]}
```

| FieldValue | JSON output |
| :--------- | :---------- |
| `FString("v")` | `"v"` |
| `FInt(42)` | `42` |
| `FFloat(3.14)` | `3.14` |
| `FBool(True)` | `true` |
| `FNull` | `null` |
| `FList([...])` | `[...]` |
| `FMap([...])` | `{...}` |

Reserved keys (`level`, `time`, `ns`, `msg`) are prefixed with `_` if a field key
collides with them.

> **Migration note.** Before v1.7, all values were stringified
> (`"amount_cents":"4999"`, `"express":"true"`). Programs that grep-parsed
> JSON for stringified numbers or booleans must update; real JSON parsers
> are unaffected and gain type fidelity.

### Compact

Single-line, `key=value` pairs. A readable middle ground for CI logs.

```gleam
woof.set_format(woof.Compact)
```

```
INFO 2026-02-11T10:30:45.123Z User signed in user_id=u_123 method=oauth
```

Values that contain spaces, `=`, or are empty are automatically quoted.

### OtlpJson (v1.8)

One OpenTelemetry-shaped JSON object per line. Use this to feed an OTLP log
pipeline.

```gleam
woof.set_format(woof.OtlpJson)
```

```json
{"timestamp_unix_nano":1779000000000000000,"severity_number":9,"severity_text":"INFO","body":"User signed in","attributes":{"user_id":"u_123"}}
```

The output carries:

| Key | Meaning |
| :-- | :------ |
| `timestamp_unix_nano` | Event time as Unix nanoseconds (`0` if unparseable) |
| `severity_number` | OpenTelemetry severity on the 1..24 scale |
| `severity_text` | `DEBUG`, `INFO`, `WARN`, and so on |
| `body` | The log message |
| `attributes` | The event fields, with native JSON types |
| `trace_id`, `span_id` | Present when a trace is in scope |
| `resource` | Present when resource attributes are set |

Severity mapping for the eight levels:

| Level | `severity_number` | `severity_text` |
| :---- | :-: | :-- |
| `Debug` | 5 | `DEBUG` |
| `Info` | 9 | `INFO` |
| `Notice` | 10 | `INFO2` |
| `Warning` | 13 | `WARN` |
| `Error` | 17 | `ERROR` |
| `Critical` | 18 | `ERROR2` |
| `Alert` | 21 | `FATAL` |
| `Emergency` | 24 | `FATAL4` |

To format a `LogEvent` as OTLP without emitting it, use `format_event_otlp`.

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

## Trace correlation (v1.8)

Trace correlation ties a log line to a distributed trace. woof writes the
`trace_id` and `span_id` fields for you, using the OpenTelemetry-conventional
names.

### Scoped: `with_trace`

Every log emitted inside the body carries the trace. Traces nest, and the
outer trace is restored when the inner body returns.

```gleam
woof.with_trace(trace_id, span_id, fn() {
  woof.info("handling request", [])
  // fields: trace_id=..., span_id=...
})
```

On the BEAM the trace lives in the process dictionary, so concurrent request
handlers never share a trace. On JavaScript the same single-threaded caveat as
`with_context` applies.

### Instanced: `set_trace`

`set_trace` returns a logger that carries a trace on every call. A logger
trace takes precedence over a scoped one.

```gleam
let req = woof.new("http") |> woof.set_trace(trace_id, span_id)
req |> woof.log(woof.Info, "request handled", [])
```

`child` loggers inherit the parent's trace.

### Reading: `current_trace`

```gleam
woof.with_trace("t", "s", fn() {
  woof.current_trace()  // Some(#("t", "s"))
})
woof.current_trace()    // None
```

`current_trace` reports only the scoped trace, not a logger trace.

---

## Resource attributes (v1.8)

Resource attributes describe the service itself rather than any single event:
`service.name`, `service.version`, and so on. Set them once at startup. The
`OtlpJson` format emits them under a `resource` object; other formats ignore
them.

```gleam
woof.set_resource([
  woof.str("service.name", "checkout"),
  woof.str("service.version", "1.8.0"),
])

woof.get_resource()  // the current resource attributes
```

See [semantic_conventions.md](semantic_conventions.md) for the recommended
field names.

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

### Instanced logger context (v1.5)

A logger can carry its own typed context - fields it attaches to every call:

```gleam
let db = woof.new("database")
  |> woof.set_context([woof.str("component", "db"), woof.str("pool", "primary")])

db |> woof.log(woof.Info,  "Connected",   [woof.str("host", "localhost")])
db |> woof.log(woof.Error, "Query failed",[woof.int("code", 1045)])
// Both events carry: component="db", pool="primary"
```

`set_context` replaces the entire context and returns a new `Logger` (loggers are
immutable values). To add fields without losing what's already there, use
`append_context`:

```gleam
let base = woof.new("api")
  |> woof.set_context([woof.str("service", "api")])

// Add per-request fields on top of the base context:
let req = base |> woof.append_context([woof.str("request_id", id)])

req |> woof.log(woof.Info, "Handling", [])
// fields: service="api", request_id="abc123"
```

`set_context` to replace entirely, `append_context` to accumulate:

```gleam
let db = woof.new("db")
  |> woof.set_context([woof.str("pool", "primary")])    // replace
  |> woof.append_context([woof.str("region", "eu-w1")]) // add
```

### Child loggers (v1.6)

Build hierarchies of loggers. Children inherit the parent's context and add
a dot-separated suffix to the parent's namespace:

```gleam
let http   = woof.new("http")
let router = woof.child(http, "router")   // namespace: "http.router"
let get    = woof.child(router, "GET")    // namespace: "http.router.GET"

get |> woof.log(woof.Info, "Handling /users", [])
// [INFO] 10:30:45 http.router.GET: Handling /users
```

Children inherit the parent's context at creation time:

```gleam
let api = woof.new("api")
  |> woof.set_context([woof.str("service", "api"), woof.str("env", "prod")])

let users = woof.child(api, "users")
// users carries: service="api", env="prod"

users |> woof.append_context([woof.str("endpoint", "/users")])
// users now carries: service, env, endpoint. api still carries only service+env
```

Loggers are immutable values. `child(parent, ...)` never mutates `parent`.

Merge order across all context sources:

```
global context  →  scoped (with_context)  →  logger.context  →  inline fields
```

> **JavaScript async code** - instanced loggers are the recommended pattern on JS.
> Because `with_context` uses a module-level variable, two concurrent Promise chains
> can overwrite each other's context.  A logger value is just a record - pass it
> around instead of relying on global state.
>
> ```gleam
> // Instead of with_context in async code:
> let ctx = woof.new("api") |> woof.set_context([woof.str("request_id", id)])
> ctx |> woof.log(woof.Info, "Handling request", [])
> await do_work(ctx)
> ctx |> woof.log(woof.Info, "Done", [])
> ```

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

Contexts nest - inner fields accumulate on top of outer ones:

```gleam
use <- woof.with_context([woof.str("service", "api")])
use <- woof.with_context([woof.str("request_id", id)])

woof.info("Processing", [])
// fields: service, request_id, plus any inline fields
```

On the BEAM, `with_context` uses the process dictionary - concurrent request handlers
never interfere. Fields from all three sources merge in order: global → scoped → inline.

> **JavaScript async users** - `with_context` uses a module-level variable on JS.
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

### Legacy sink - `fn(Entry, String) -> Nil`

Receives the resolved `Entry` (fields as strings) and the pre-formatted string.
This is the original sink type - all built-in sinks use it.

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

### Multiple legacy sinks - `set_sinks(List(Sink))`

Register several sinks at once; each receives every event in order:

```gleam
woof.set_sinks([woof.beam_logger_sink, my_datadog_sink, my_metrics_sink])
```

`set_sink(s)` is shorthand for `set_sinks([s])`.

### Event sink - `fn(LogEvent) -> Nil`

Receives a `LogEvent` with fields as `FieldValue` - no type information is lost.

```gleam
woof.set_event_sink(fn(event: woof.LogEvent) {
  case event.level {
    woof.Error | woof.Critical | woof.Alert | woof.Emergency ->
      alert_pagerduty(event.message, event.fields)
    _ -> Nil
  }
})
```

Both channels (legacy + event) fire independently on every emit. Remove with
`clear_event_sink()`.

### Filtering an event sink (v1.6)

`filter_event_sink(predicate, sink)` wraps an `EventSink` so only events for
which `predicate(event)` returns `True` are forwarded. Selective routing
without writing a full custom sink:

```gleam
// Send only Error+ events to PagerDuty:
woof.set_event_sink(woof.filter_event_sink(
  fn(e) { woof.level_to_int(e.level) >= woof.level_to_int(woof.Error) },
  pagerduty_sink,
))

// Send only events from a specific namespace to a metrics pipeline:
woof.set_event_sink(woof.filter_event_sink(
  fn(e) { e.namespace == Some("payments") },
  metrics_sink,
))
```

`level_to_int(Level) -> Int` exposes the OTP / syslog ordinal (Debug=0..Emergency=7)
since Gleam custom types don't support `>=` directly.

### Emitting a pre-built `LogEvent` (v1.6)

`emit(LogEvent) -> Nil` dispatches a pre-built event through every registered
sink. Useful for bridging from external logging systems and replaying captured
events in tests.

```gleam
woof.emit(woof.LogEvent(
  level: woof.Warning,
  message: "replayed from external log",
  fields: [woof.str("origin", "datadog")],
  timestamp: ts,
  namespace: Some("bridge"),
))
```

Important differences from level-tagged shortcuts (`info`, `error`, ...):

- **No context merging.** The event is delivered as supplied; global / scoped
  context is *not* prepended.
- **No level filter.** The current minimum level is not enforced. The caller
  has already decided to emit. To honour the filter, guard with `is_enabled`.

### `beam_event_sink` - structured OTP logging

`beam_event_sink` is an `EventSink` that sends typed Erlang terms to OTP logger.
Unlike `beam_logger_sink`, integer fields arrive as integers, booleans as booleans:

```gleam
woof.set_event_sink(woof.beam_event_sink)
woof.info("Payment ok", [woof.int("amount", 4999), woof.bool("express", True)])
```

OTP logger receives: `#{fields => #{<<"amount">> => 4999, <<"express">> => true}}`.

### Presets

One-call configuration for common environments:

```gleam
woof.dev()   // Debug level, Text format, Auto colors, stdout
woof.prod()  // Info level, Json format, no colors, beam_logger_sink
```

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
The thunk is only called if the level is currently enabled - zero allocation otherwise.

```gleam
woof.debug_lazy(fn() { "snapshot: " <> expensive_dump(state) }, [])
```

Available: `debug_lazy`, `info_lazy`, `notice_lazy`, `warning_lazy`, `error_lazy`,
`critical_lazy`, `alert_lazy`, `emergency_lazy`.

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

Log and pass a value through - fits naturally in `|>` chains:

```gleam
fetch_user(id)
|> woof.tap_info("User fetched", [])
|> transform_user()
|> woof.tap_debug("Transformed", [])
|> save_user()
```

Available: `tap_debug`, `tap_info`, `tap_notice`, `tap_warning`, `tap_error`,
`tap_critical`, `tap_alert`, `tap_emergency`.

### inspect (v1.5)

Debug-log any Gleam value as its string representation, then return the value
unchanged. Zero cost when Debug is disabled.

```gleam
fetch_user(id)
|> woof.inspect("user")
// [DEBUG] user  value="User(id: 42, name: \"alice\")"
|> transform_user()
```

The field key is always `"value"`; the label becomes the log message.

### tap_time (v1.5)

Debug-log the current monotonic timestamp (integer milliseconds) as a
`monotonic_ms` field, then pass the value through.  Place it at two points in
a pipeline to see the wall-clock bracket in the log stream.

```gleam
pipeline_start
|> woof.tap_time("before_query")    // monotonic_ms = 12345
|> database.query()
|> woof.tap_time("after_query")     // monotonic_ms = 12358  → 13 ms elapsed
|> process_results()
```

Zero cost when Debug is disabled.

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

Emits an `Info` message `"db_query completed"` with a `duration_ms: Int` field.
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

### Level from environment variable

Read the log level from an env var at startup, common in OTP releases and containers:

```gleam
// Reads LOG_LEVEL, applies it; ignores missing/invalid values
let _ = woof.set_level_from_env("LOG_LEVEL")

// Or handle the result explicitly:
case woof.set_level_from_env("LOG_LEVEL") {
  Ok(Nil) -> Nil
  Error(Nil) -> woof.set_level(woof.Info)  // fallback
}
```

Parse a level name anywhere:

```gleam
woof.level_from_string("warning")  // Ok(Warning)
woof.level_from_string("WARNING")  // Ok(Warning), case-insensitive
woof.level_from_string("warn")     // Error(Nil), abbreviated names not accepted
woof.level_from_string("verbose")  // Error(Nil), unknown name
```

Read the active level programmatically:

```gleam
let current = woof.get_level()
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

Level colors in `Text` format: Debug → dim grey, Info → blue, Notice → cyan,
Warning → yellow, Error → bold red, Critical → bold magenta, Alert → bold red,
Emergency → bold red.

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
| `fields` | `List(#(String, String))` - serialised field list |
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

`beam_logger_sink` and `beam_event_sink` on JS route each event to the
level-appropriate `console` method:

| woof level | console method |
| :--- | :--- |
| `Debug` | `console.debug` |
| `Info` | `console.info` |
| `Notice`, `Warning` | `console.warn` |
| `Error`, `Critical`, `Alert`, `Emergency` | `console.error` |

woof's own formatting (Text, Compact, JSON, Custom) is preserved on JS for
`beam_logger_sink`. `beam_event_sink` uses the raw message on JS (no formatter).

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
| `notice` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Notice |
| `warning` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Warning |
| `error` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Error |
| `critical` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Critical |
| `alert` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Alert |
| `emergency` | `(String, List(#(String, FieldValue))) -> Nil` | Log at Emergency |
| `debug_lazy` | `(fn() -> String, List(#(String, FieldValue))) -> Nil` | Lazy Debug |
| `info_lazy` | … | Lazy Info |
| `notice_lazy` | … | Lazy Notice |
| `warning_lazy` | … | Lazy Warning |
| `error_lazy` | … | Lazy Error |
| `critical_lazy` | … | Lazy Critical |
| `alert_lazy` | … | Lazy Alert |
| `emergency_lazy` | … | Lazy Emergency |

### Namespaced loggers

| Function | Signature | Description |
| :--- | :--- | :--- |
| `new` | `(String) -> Logger` | Create a namespaced logger |
| `child` | `(Logger, String) -> Logger` | Sub-namespace logger inheriting parent context and trace |
| `set_context` | `(Logger, List(#(String, FieldValue))) -> Logger` | Replace logger's instance context |
| `append_context` | `(Logger, List(#(String, FieldValue))) -> Logger` | Add fields to instance context |
| `set_trace` | `(Logger, String, String) -> Logger` | Attach a trace and span to a logger (v1.8) |
| `log` | `(Logger, Level, String, List(#(String, FieldValue))) -> Nil` | Log through a namespace |

### Field constructors

| Function | Returns | Notes |
| :--- | :--- | :--- |
| `str(key, String)` | `#(String, FString)` | Preferred for strings |
| `int(key, Int)` | `#(String, FInt)` | Preferred for integers |
| `float(key, Float)` | `#(String, FFloat)` | Preferred for floats |
| `bool(key, Bool)` | `#(String, FBool)` | JSON output: native `true`/`false` |
| `list(key, List(FieldValue))` | `#(String, FList)` | Array, items typed (v1.7) |
| `map(key, List(#(String, FieldValue)))` | `#(String, FMap)` | Nested object (v1.7) |
| `null(key)` | `#(String, FNull)` | Explicit null (v1.7) |
| `vstr(String)` | `FString` | Raw value for nested construction (v1.7) |
| `vint(Int)` | `FInt` | Raw value (v1.7) |
| `vfloat(Float)` | `FFloat` | Raw value (v1.7) |
| `vbool(Bool)` | `FBool` | Raw value (v1.7) |
| `vnull()` | `FNull` | Raw value (v1.7) |
| `field(key, String)` | `#(String, FString)` | Alias for `str`, deprecated |
| `int_field(key, Int)` | `#(String, FInt)` | Alias for `int`, deprecated |
| `float_field(key, Float)` | `#(String, FFloat)` | Alias for `float`, deprecated |
| `bool_field(key, Bool)` | `#(String, FBool)` | Alias for `bool`, deprecated |

### Configuration

| Function | Signature | Description |
| :--- | :--- | :--- |
| `configure` | `(Config) -> Nil` | Set level + format + colors at once |
| `set_level` | `(Level) -> Nil` | Change minimum log level |
| `get_level` | `() -> Level` | Read current minimum log level |
| `level_from_string` | `(String) -> Result(Level, Nil)` | Parse level name (case-insensitive) |
| `set_level_from_env` | `(String) -> Result(Nil, Nil)` | Read level from env var and apply |
| `set_format` | `(Format) -> Nil` | Change output format |
| `set_colors` | `(ColorMode) -> Nil` | Change color mode |
| `is_enabled` | `(Level) -> Bool` | Check if a level is active |

### Sinks

| Function | Signature | Description |
| :--- | :--- | :--- |
| `set_sink` | `(Sink) -> Nil` | Register a single legacy sink (shorthand for `set_sinks`) |
| `set_sinks` | `(List(Sink)) -> Nil` | Register multiple legacy sinks |
| `set_event_sink` | `(EventSink) -> Nil` | Register typed sink `fn(LogEvent) -> Nil` |
| `clear_event_sink` | `() -> Nil` | Remove the typed event sink |
| `filter_event_sink` | `(fn(LogEvent) -> Bool, EventSink) -> EventSink` | Wrap an event sink with a predicate |
| `emit` | `(LogEvent) -> Nil` | Dispatch a pre-built event to all sinks (no context merge, no level filter) |
| `default_sink` | `Sink` | Prints to stdout (default) |
| `beam_logger_sink` | `Sink` | Routes through OTP logger / console.* |
| `beam_event_sink` | `EventSink` | Structured typed fields to OTP logger |
| `silent_sink` | `Sink` | Discards everything |
| `test_sink` | `() -> #(EventSink, fn() -> List(LogEvent))` | Capture sink for tests |
| `dev` | `() -> Nil` | Preset: Debug + Text + Auto colors + stdout |
| `prod` | `() -> Nil` | Preset: Info + Json + no colors + beam_logger_sink |

### Context

| Function | Signature | Description |
| :--- | :--- | :--- |
| `with_context` | `(List(#(String, FieldValue)), fn() -> a) -> a` | Scoped fields |
| `set_global_context` | `(List(#(String, FieldValue))) -> Nil` | App-wide fields |
| `get_global_context` | `() -> List(#(String, FieldValue))` | Read current global ctx |
| `append_global_context` | `(List(#(String, FieldValue))) -> Nil` | Add to global ctx |

### Trace correlation and resource (v1.8)

| Function | Signature | Description |
| :--- | :--- | :--- |
| `with_trace` | `(String, String, fn() -> a) -> a` | Scoped trace for every log in the body |
| `current_trace` | `() -> Option(#(String, String))` | Read the scoped trace |
| `set_resource` | `(List(#(String, FieldValue))) -> Nil` | Set OpenTelemetry resource attributes |
| `get_resource` | `() -> List(#(String, FieldValue))` | Read resource attributes |

### Pipeline helpers

| Function | Description |
| :--- | :--- |
| `tap_debug` / `tap_info` / `tap_notice` / `tap_warning` / `tap_error` | Log and pass value through |
| `tap_critical` / `tap_alert` / `tap_emergency` | Log and pass value through |
| `inspect(value, label) -> a` | Debug-log string repr of value, return value |
| `tap_time(value, label) -> a` | Debug-log `monotonic_ms` as Int, return value |
| `log_error` | Log on `Result` `Error`, pass through |
| `time` | Measure and log block duration as `duration_ms: Int` |

### Utilities

| Function | Description |
| :--- | :--- |
| `format(Entry, Format) -> String` | Format an `Entry` without emitting |
| `format_event_json(LogEvent) -> String` | Public JSON formatter, native typed values (v1.7) |
| `format_event_text(LogEvent, ColorMode) -> String` | Public Text formatter (v1.7) |
| `format_event_compact(LogEvent) -> String` | Public Compact formatter (v1.7) |
| `format_event_otlp(LogEvent) -> String` | Public OTLP JSON formatter (v1.8) |
| `level_name(Level) -> String` | `Warning` to `"warning"` |
| `level_to_int(Level) -> Int` | `Warning` to `3` (OTP / syslog ordinal) |
