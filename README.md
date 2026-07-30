> ℹ️ **v1.9** adds production-hardening sink wrappers (`redact_event_sink`, `sample_event_sink`, `consistent_sample_event_sink`, `rate_limit_event_sink`, `batch_event_sink`), plus `error_with` and `log_at_most`.
>
> ℹ️ **v1.8** adds trace correlation (`with_trace`, `set_trace`, `current_trace`), the `OtlpJson` format with `format_event_otlp`, and OpenTelemetry resource attributes (`set_resource`, `get_resource`).
>
> ℹ️ **v1.7** adds `FList`/`FMap`/`FNull` variants, `list`/`map`/`null` constructors, `vstr`/`vint`/`vfloat`/`vbool`/`vnull` raw helpers, native typed JSON output, and public `format_event_*` helpers.
>
> ℹ️ **v1.6** adds `child` loggers, `filter_event_sink`, public `emit(LogEvent)`, and public `level_to_int`. No breaking changes.
>
> ℹ️ **v1.5** adds instanced logger context, `inspect`, `tap_time`, `level_from_string`, `set_level_from_env`, `get_level`, `append_context`, and soft deprecation warnings for legacy field helpers.
>
> ℹ️ **v1.4** adds 4 new OTP levels (`Notice`, `Critical`, `Alert`, `Emergency`), `beam_event_sink`, multi-sink dispatch, and `dev()`/`prod()` presets.
>
> ⚠️ **v1.3 breaking change:** fields changed from `List(#(String, String))` to `List(#(String, FieldValue))`. See [docs/migration_v1_3.md](docs/migration_v1_3.md).

<p align="center">
  <img src="https://raw.githubusercontent.com/lupodevelop/woof/main/assets/img/woof-logo.png" alt="woof logo" width="200" />
</p>

[![Package Version](https://img.shields.io/hexpm/v/woof)](https://hex.pm/packages/woof) [![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/woof/) [![Built with Gleam](https://img.shields.io/badge/built%20with-gleam-ffaff3?logo=gleam)](https://gleam.run) [![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# woof

A straightforward logging library for Gleam.  
Dedicated to Echo, my dog.

woof gets out of your way: import it, call `info(...)`, and you're done.
Structured fields, namespaces, scoped context, typed events - all there
when you need them, invisible when you don't.

## Install

```sh
gleam add woof
```

## Quick start

```gleam
import woof

pub fn main() {
  woof.info("Server started", [woof.str("host", "0.0.0.0"), woof.int("port", 3000)])
  woof.warning("Cache almost full", [woof.int("usage_pct", 92)])
  woof.error("Connection lost", [woof.str("host", "db-primary")])
}
```

```
[INFO] 10:30:45 Server started
  host: 0.0.0.0
  port: 3000
[WARN] 10:30:46 Cache almost full
  usage_pct: 92
[ERROR] 10:30:47 Connection lost
  host: db-primary
```

No setup, no builder chains, no ceremony.

## Typed fields

Fields carry their original Gleam types through the entire pipeline.
Pattern-match on them in event sinks, assert on them in tests.

```gleam
woof.info("Payment processed", [
  woof.str("order_id", "ORD-42"),
  woof.int("amount_cents", 4999),
  woof.float("tax_rate", 8.5),
  woof.bool("express", True),
])
```

## Nested data

Lists, nested objects, and explicit null pass through as typed values:

```gleam
woof.info("order", [
  woof.str("id", "ORD-42"),
  woof.list("items", [woof.vstr("widget"), woof.vstr("gadget")]),
  woof.map("address", [
    #("city", woof.vstr("Bologna")),
    #("zip",  woof.vstr("40121")),
  ]),
  woof.null("coupon"),
])
```

JSON output emits real types: `"items":["widget","gadget"]`, `"address":{...}`,
`"coupon":null`. Numbers are numbers, booleans are booleans.

## Testing capture typed events

```gleam
let #(sink, get) = woof.test_sink()
woof.set_sink(woof.silent_sink)
woof.set_event_sink(sink)

process_payment(order_id: "ORD-99", amount: 0)

let assert [event] = get()
event.level   |> should.equal(woof.Error)
event.message |> should.equal("Payment rejected")
event.fields  |> should.equal([
  #("order_id", woof.FString("ORD-99")),
  #("reason",   woof.FString("zero amount")),
])
```

## One-call setup

```gleam
pub fn main() {
  woof.dev()   // Debug level, Text format, colors Auto, stdout
  // - or -
  woof.prod()  // Info level, Json format, OTP logger
}
```

Or wire up sinks explicitly:

```gleam
woof.set_sinks([woof.beam_logger_sink, my_metrics_sink])
woof.set_event_sink(woof.beam_event_sink) // structured typed fields to OTP
```

## Instanced loggers with context

Pass a fixed set of fields through a logger instance - no global state needed:

```gleam
let db = woof.new("database") |> woof.set_context([woof.str("component", "db")])
db |> woof.log(woof.Info, "Connected", [woof.str("host", "localhost")])
// → namespace: "database", fields: component="db", host="localhost"
```

Build hierarchies with `child` (inherits parent context, dot-joined namespace):

```gleam
let http   = woof.new("http")
let router = woof.child(http, "router")   // namespace: "http.router"
```

Ideal for JS async code where global context is unreliable.

## Selective sink routing

Wrap a sink with a predicate to send only matching events somewhere:

```gleam
woof.set_event_sink(woof.filter_event_sink(
  fn(e) { woof.level_to_int(e.level) >= woof.level_to_int(woof.Error) },
  pagerduty_sink,
))
```

## Production hardening

Redact secrets, cap volume, and batch deliveries by composing sink
wrappers - redact first, batch last:

```gleam
woof.set_event_sink(
  otlp_http_sink
  |> woof.redact_event_sink(["password", "authorization"])
  |> woof.rate_limit_event_sink(2000)
  |> woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error)
  |> woof.batch_event_sink(200, 5000),
)
```

`error_with` and `log_at_most` cover two more common cases: a structured
error field, and capping a noisy log line without an `if` at every call
site.

```gleam
woof.error_with("payment failed", "timeout", [woof.str("order_id", "O1")])
woof.log_at_most(5, "db_retry_failed", woof.Warning, "retry failed", [])
```

See [docs/production_setup.md](docs/production_setup.md) for the reasoning
behind the composition order and [docs/guide.md](docs/guide.md) for the
full reference.

## Debugging helpers

```gleam
fetch_user(id)
|> woof.inspect("user")          // logs string repr at Debug, passes value through
|> woof.tap_time("after_fetch")  // logs monotonic_ms as Int field at Debug
|> transform()
```

## Level from environment variable

```gleam
pub fn main() {
  let _ = woof.set_level_from_env("LOG_LEVEL")  // reads LOG_LEVEL, falls back silently
  // ...
}
```

```sh
LOG_LEVEL=warning ./my_app   # sets Warning level at startup
```

Parse or inspect the level anywhere:

```gleam
woof.level_from_string("critical")  // Ok(Critical)
woof.get_level()                    // current Level
```

## Trace correlation and OpenTelemetry

Tie logs to a distributed trace. Inside `with_trace`, every log carries
`trace_id` and `span_id`:

```gleam
woof.with_trace(trace_id, span_id, fn() {
  woof.info("payment captured", [woof.int("amount_cents", 4200)])
})
```

Set OpenTelemetry resource attributes once at startup, then switch the format
to `OtlpJson` for an OpenTelemetry-shaped object per line:

```gleam
woof.set_resource([
  woof.str("service.name", "checkout"),
  woof.str("service.version", "1.8.0"),
])
woof.configure(woof.Config(woof.Info, woof.OtlpJson, woof.Never))
```

```json
{"timestamp_unix_nano":1779000000000000000,"severity_number":9,"severity_text":"INFO","body":"payment captured","trace_id":"...","span_id":"...","resource":{"service.name":"checkout"},"attributes":{"amount_cents":4200}}
```

## Documentation

| Document | Contents |
| :--- | :--- |
| [docs/guide.md](docs/guide.md) | Full reference: levels, formats, sinks, context, BEAM integration, API table |
| [docs/production_setup.md](docs/production_setup.md) | Composing v1.9 sink wrappers for production |
| [docs/sink_composition.md](docs/sink_composition.md) | Why sink wrapper order matters |
| [docs/benchmarks.md](docs/benchmarks.md) | Measured overhead of each sink wrapper |
| [docs/semantic_conventions.md](docs/semantic_conventions.md) | Standard field names for queryable logs |
| [docs/log_levels.md](docs/log_levels.md) | Choosing the right log level |
| [docs/migration_v1_3.md](docs/migration_v1_3.md) | Upgrading from v1.2 - what changed and how to fix it |
| [ROADMAP.md](ROADMAP.md) | Future releases v1.9 to v2.0 |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [hexdocs.pm/woof](https://hexdocs.pm/woof/) | Generated module reference |

## Requirements

- Gleam **1.14** or newer
- OTP **22+** on the BEAM (CI uses OTP 28)
- `gleam_stdlib` the only dependency

---

<p align="center">Made with Gleam 💜</p>
