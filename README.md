<p align="center">
  <img src="https://raw.githubusercontent.com/lupodevelop/woof/main/assets/img/woof-logo.png" alt="woof logo" width="200" />
</p>

[![Package Version](https://img.shields.io/hexpm/v/woof)](https://hex.pm/packages/woof) [![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/woof/) [![Built with Gleam](https://img.shields.io/badge/built%20with-gleam-ffaff3?logo=gleam)](https://gleam.run) [![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# woof 

A straightforward logging library for Gleam.  
Dedicated to Echo, my dog.

woof gets out of your way: import it, call `info(...)`, and you're done.
When you need more structured fields, namespaces, scoped context.
It's all there without changing the core workflow.

## Quick start

```sh
gleam add woof
```

```gleam
import woof

pub fn main() {
  woof.info("Server started", [#("port", "3000")])
  woof.warning("Cache almost full", [#("usage", "92%")])
}
```

Output:

```
[INFO] 10:30:45 Server started
  port: 3000
[WARN] 10:30:46 Cache almost full
  usage: 92%
```

That's it. No setup, no builder chains, no ceremony.

## Structured fields

Every log function accepts a list of `#(String, String)` tuples.
Use the built-in field helpers to skip manual conversion:

```gleam
import woof

woof.info("Payment processed", [
  woof.field("order_id", "ORD-42"),
  woof.int_field("amount", 4999),
  woof.float_field("tax", 8.5),
  woof.bool_field("express", True),
])
```

Plain tuples still work if you prefer — the helpers are just convenience:

```gleam
woof.info("Request", [#("method", "GET"), #("path", "/api")])
```

Available helpers: `field`, `int_field`, `float_field`, `bool_field`.

## Levels

Four levels, ordered by severity:

| Level     | Tag       | When to use                              |
|-----------|-----------|------------------------------------------|
| `Debug`   | `[DEBUG]` | Detailed info useful during development  |
| `Info`    | `[INFO]`  | Normal operational events                |
| `Warning` | `[WARN]`  | Something unexpected but not broken      |
| `Error`   | `[ERROR]` | Something is wrong and needs attention   |

Set the minimum level to silence the noise:

```gleam
woof.set_level(woof.Warning)

woof.debug("ignored", [])      // dropped — below Warning
woof.info("also ignored", [])  // dropped
woof.warning("shown", [])      // printed
woof.error("shown too", [])    // printed
```

## Formats

### Text (default)

Human-readable, great for development.

```gleam
woof.set_format(woof.Text)
```

```
[INFO] 10:30:45 User signed in
  user_id: u_123
  method: oauth
```

### JSON

Machine-readable, one object per line — ideal for production and tools
like Loki, Datadog, or CloudWatch.

```gleam
woof.set_format(woof.Json)
```

```json
{"level":"info","time":"2026-02-11T10:30:45.123Z","msg":"User signed in","user_id":"u_123","method":"oauth"}
```

### Custom

Plug in any function that takes an `Entry` and returns a `String`.
This is the escape hatch for integrating with other formatting or output
libraries.

```gleam
let my_format = fn(entry: woof.Entry) -> String {
  woof.level_name(entry.level) <> " | " <> entry.message
}

woof.set_format(woof.Custom(my_format))
```

### Compact

Single-line, `key=value` pairs — a compact middle ground.

```gleam
woof.set_format(woof.Compact)
```

```
INFO 2026-02-11T10:30:45.123Z User signed in user_id=u_123 method=oauth
```

## Namespaces

Organise log output by component without polluting the message itself.

```gleam
let log = woof.new("database")

log |> woof.log(woof.Info, "Connected", [#("host", "localhost")])
log |> woof.log(woof.Debug, "Query executed", [#("ms", "12")])
```

```
[INFO] 10:30:45 database: Connected
  host: localhost
[DEBUG] 10:30:45 database: Query executed
  ms: 12
```

In JSON output the namespace appears as the `"ns"` field.

## Context

### Scoped context

Attach fields to every log call inside a callback. Perfect for
request-scoped metadata.

```gleam
use <- woof.with_context([#("request_id", req.id)])

woof.info("Handling request", [])   // includes request_id
do_work()
woof.info("Done", [])              // still includes request_id
```

On the BEAM each process (= each request handler) gets its own context via
the process dictionary, so concurrent handlers never interfere.

Nesting works — inner contexts accumulate on top of outer ones:

```gleam
use <- woof.with_context([#("service", "api")])
use <- woof.with_context([#("request_id", id)])

woof.info("Processing", [])
// fields: service=api, request_id=<id>
```

> **Notice for JavaScript async users**  
> On the BEAM, `with_context` uses the process dictionary, so concurrent requests never interfere. On the JavaScript target, because JS is fundamentally single-threaded with cooperative concurrency, `with_context` modifies a global state. If your `with_context` callback returns a `Promise` (or does asynchronous `await`s), the context might leak or be overwritten by other concurrent async operations. If you heavily rely on async/await in Node/Deno for concurrent requests, consider passing context explicitly instead of using `with_context`.

### Global context

Set fields that appear on every message, everywhere:

```gleam
woof.set_global_context([
  #("app", "my-service"),
  #("version", "1.2.0"),
  #("env", "production"),
])
```

You can also incrementally add fields to the global context using `woof.append_global_context([#("key", "value")])`.

## Configuration

For one-shot setup, use `configure`:

```gleam
woof.configure(woof.Config(
  level: woof.Info,
  format: woof.Json,
  colors: woof.Auto,
))
```

Or change individual settings:

```gleam
woof.set_level(woof.Info)
woof.set_format(woof.Json)
woof.set_colors(woof.Never)
```

## Sinks

A **sink** is a function `fn(Entry, String) -> Nil` that receives each log
event. It gets both the structured `Entry` (level, message, fields,
namespace, timestamp) and the string that woof's formatter produced.

The active sink is set with `set_sink`. woof ships two ready-made sinks:

| Sink                | When to use                                  |
|---------------------|----------------------------------------------|
| `default_sink`      | Development, scripts, CLI tools (default)    |
| `beam_logger_sink`  | Production OTP applications                  |
| `silent_sink`       | Discard all logs (useful for test suites)    |

### Custom sinks

Use `set_sink` to replace the active sink with any side-effecting function:

```gleam
// Write to a file (simplified example)
woof.set_sink(fn(_entry, formatted) {
  simplifile.append(log_path, formatted <> "\n")
})
```

```gleam
// Send structured data to an external service
woof.set_sink(fn(entry, _formatted) {
  send_to_datadog(entry.level, entry.message, entry.fields)
})
```

```gleam
// Extend an existing sink rather than replacing it
woof.set_sink(fn(entry, formatted) {
  metrics.increment(woof.level_name(entry.level) <> ".count")
  woof.default_sink(entry, formatted)
})
```

### Capturing output in tests

Custom sinks are the idiomatic way to capture log output in tests without
touching stdout:

```gleam
import gleam/erlang/process

pub fn my_test() {
  let subject = process.new_subject()

  woof.set_sink(fn(entry, _formatted) {
    process.send(subject, entry)
  })

  woof.info("something happened", [#("key", "value")])

  let assert Ok(entry) = process.receive(subject, 0)
  let assert "something happened" = entry.message
}
```

## BEAM logger integration

woof's default sink prints directly to stdout — zero configuration,
beautiful coloured output, works everywhere.

For **production OTP applications**, swap in `beam_logger_sink` once at
startup to route every log event through OTP's
[`logger`](https://www.erlang.org/doc/apps/kernel/logger_chapter.html)
module:

```gleam
pub fn main() {
  woof.set_sink(woof.beam_logger_sink)

  woof.info("Server started", [woof.int_field("port", 3000)])
}
```

One line. That is all.

### Why bother?

Without `beam_logger_sink`, woof bypasses the OTP logging pipeline entirely:

- Apps that use woof run **two independent logging systems** in parallel.
- It is impossible to silence or redirect woof output — even from libraries
  that use woof as a dependency.
- BEAM logger features (async dispatch, load-shedding, handler routing) do
  not apply to woof messages.
- External log collectors (Loki, Datadog, etc.) only see half your logs.

With `beam_logger_sink` all of that goes away: one pipeline, full control.

### Filtering and routing

Each event is tagged with `domain => [woof]` so handlers and primary
filters can target woof output specifically.

Silence all woof output (e.g. during tests or in certain environments):

```erlang
logger:add_primary_filter(no_woof,
    {fun logger_filters:domain/2, {stop, sub, [woof]}}).
```

### Metadata

Each event carries the following logger metadata:

| Key         | Value                                          |
|-------------|------------------------------------------------|
| `domain`    | `[woof]` — lets filters target woof events     |
| `fields`    | The structured `#(String, String)` field list  |
| `namespace` | The logger namespace, if `woof.new/1` was used |

### Output format

When `beam_logger_sink` is active, the OTP logger handler owns the output
format. The default handler (`logger_formatter`) wraps the message with its
own timestamp and level prefix:

```text
2026-03-22T10:30:45.123+00:00 info:
Server started
```

woof's `Text`/`Compact`/`JSON` format setting does not affect this output —
it only applies when `default_sink` (or a custom sink) is active.

To customise the OTP format, reconfigure the default handler. In Erlang:

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

On JavaScript there is no centralised logger equivalent to OTP's `logger`.
`beam_logger_sink` on JS routes each event to the level-appropriate
`console` method so browser DevTools and Node.js can filter by severity:

| woof level | console method  |
|------------|-----------------|
| `Debug`    | `console.debug` |
| `Info`     | `console.info`  |
| `Warning`  | `console.warn`  |
| `Error`    | `console.error` |

woof's own formatting (Text, Compact, JSON, Custom) is preserved — the
formatted string is what gets passed to the console method.

## Colors

Colors apply to `Text` format only.  Three modes:

- `Auto` (default) — colors are enabled when stdout is a TTY and `NO_COLOR`
  is not set.
- `Always` — force ANSI colors regardless of environment.
- `Never` — plain text, no escape codes.

```gleam
woof.set_colors(woof.Always)
```

Level colors: Debug → dim grey, Info → blue, Warning → yellow, Error → bold red.

## Lazy evaluation

When building the log message is expensive, use the lazy variants.
The thunk is only called if the level is enabled.

```gleam
woof.debug_lazy(fn() { expensive_debug_dump(state) }, [])
```

Available: `debug_lazy`, `info_lazy`, `warning_lazy`, `error_lazy`.

You can also manually check if a level is enabled before doing setup work:
```gleam
if woof.is_enabled(woof.Debug) {
  let complex_data = do_expensive_work()
  woof.debug("Done", [woof.field("data", complex_data)])
}
```

## Pipeline helpers

### tap

Log and pass a value through — fits naturally in pipelines:

```gleam
fetch_user(id)
|> woof.tap_info("Fetched user", [])
|> transform_user()
|> woof.tap_debug("Transformed", [])
|> save_user()
```

Available: `tap_debug`, `tap_info`, `tap_warning`, `tap_error`.

### log_error

Log only when a `Result` is `Error`, then pass it through:

```gleam
fetch_data()
|> woof.log_error("Fetch failed", [#("endpoint", url)])
|> result.unwrap(default)
```

### time

Measure and log the duration of a block:

```gleam
use <- woof.time("db_query")
database.query(sql)
```

Emits: `db_query completed` with a `duration_ms` field.

## API at a glance

| Function                | Purpose                                        |
|-------------------------|------------------------------------------------|
| `debug`                 | Log at Debug level                             |
| `info`                  | Log at Info level                              |
| `warning`               | Log at Warning level                           |
| `error`                 | Log at Error level                             |
| `debug_lazy`            | Lazy Debug — thunk only runs when enabled      |
| `info_lazy`             | Lazy Info                                      |
| `warning_lazy`          | Lazy Warning                                   |
| `error_lazy`            | Lazy Error                                     |
| `new`                   | Create a namespaced logger                     |
| `log`                   | Log through a namespaced logger                |
| `configure`             | Set level + format + colors at once            |
| `set_level`             | Change the minimum level                       |
| `set_format`            | Change the output format                       |
| `set_colors`            | Change color mode (Auto/Always/Never)          |
| `set_global_context`    | Set app-wide fields                            |
|                     ... | See `get_global_context`, `append_global_context`|
| `set_sink`              | Replace the output sink                        |
| `default_sink`          | The built-in sink (BEAM logger / console)      |
| `silent_sink`           | Discard all logs                               |
| `is_enabled`            | Check if a log level is currently enabled      |
| `with_context`          | Scoped fields for a callback                   |
| `tap_debug`…`tap_error` | Log and pass a value through                   |
| `log_error`             | Log on Result Error, pass through              |
| `time`                  | Measure and log a block's duration             |
| `field`                 | `#(String, String)` — string field             |
| `int_field`             | `#(String, String)` — from Int                 |
| `float_field`           | `#(String, String)` — from Float               |
| `bool_field`            | `#(String, String)` — from Bool                |
| `format`                | Format an entry without emitting it            |
| `level_name`            | `Warning` → `"warning"` (useful in formatters) |

## Cross-platform

woof works on both the Erlang and JavaScript targets.

- **Erlang**: global state uses `persistent_term` (part of `erts`, always
  available). Scoped context lives in the process dictionary.
  The default sink routes output through OTP `logger` — see
  [BEAM logger integration](#beam-logger-integration) above.
- **JavaScript**: module-level variables. Safe because JS is
  single-threaded. The default sink uses woof's own formatting and writes
  via `console.debug` / `console.info` / `console.warn` / `console.error`.

Structured fields, namespaces, context, lazy evaluation, and pipeline
helpers behave identically on both targets.

## Dependencies & Requirements


* Gleam **1.14** or newer (tested with 1.14.0).  
* OTP 22+ on the BEAM (CI uses OTP 28).  
* Just `gleam_stdlib` — no runtime dependencies.

---

<p align="center">Made with Gleam 💜</p>

