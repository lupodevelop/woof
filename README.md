<p align="center">
  <img src="assets/img/woof-logo.png" alt="woof logo" width="200" />
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

| Level     | Tag       | When to use                            |
|-----------|-----------|----------------------------------------|
| `Debug`   | `[DEBUG]` | Detailed info useful during development |
| `Info`    | `[INFO]`  | Normal operational events               |
| `Warning` | `[WARN]`  | Something unexpected but not broken     |
| `Error`   | `[ERROR]` | Something is wrong and needs attention  |

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

### Global context

Set fields that appear on every message, everywhere:

```gleam
woof.set_global_context([
  #("app", "my-service"),
  #("version", "1.2.0"),
  #("env", "production"),
])
```

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

| Function            | Purpose                                       |
|---------------------|-----------------------------------------------|
| `debug`             | Log at Debug level                            |
| `info`              | Log at Info level                             |
| `warning`           | Log at Warning level                          |
| `error`             | Log at Error level                            |
| `debug_lazy`        | Lazy Debug — thunk only runs when enabled     |
| `info_lazy`         | Lazy Info                                     |
| `warning_lazy`      | Lazy Warning                                  |
| `error_lazy`        | Lazy Error                                    |
| `new`               | Create a namespaced logger                    |
| `log`               | Log through a namespaced logger               |
| `configure`         | Set level + format + colors at once           |
| `set_level`         | Change the minimum level                      |
| `set_format`        | Change the output format                      |
| `set_colors`        | Change color mode (Auto/Always/Never)         |
| `set_global_context` | Set app-wide fields                          |
| `with_context`      | Scoped fields for a callback                  |
| `tap_debug`…`tap_error` | Log and pass a value through              |
| `log_error`         | Log on Result Error, pass through             |
| `time`              | Measure and log a block's duration            |
| `field`             | `#(String, String)` — string field            |
| `int_field`         | `#(String, String)` — from Int                |
| `float_field`       | `#(String, String)` — from Float              |
| `bool_field`        | `#(String, String)` — from Bool               |
| `format`            | Format an entry without printing it           |
| `level_name`        | `Warning` → `"warning"` (useful in formatters)|

## Cross-platform

---

woof works on both the Erlang and JavaScript targets.

- **Erlang**: global state uses `persistent_term` (part of `erts`, always
  available). Scoped context lives in the process dictionary.
- **JavaScript**: module-level variables. Safe because JS is
  single-threaded.

Output format is identical on both targets.

## Dependencies & Requirements

---


* Gleam **1.14** or newer (tested with 1.14.0).  
* OTP 22+ on the BEAM (CI uses OTP 28).  
* Just `gleam_stdlib` — no runtime dependencies.

---

<p align="center">Made with Gleam 💜</p>

