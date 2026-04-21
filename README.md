> ℹ️ **v1.5** adds instanced logger context, `inspect`, `tap_time`, `level_from_string`, `set_level_from_env`, `get_level`, `append_context`, and soft deprecation warnings for legacy field helpers. No breaking changes.
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

Ideal for JS async code where global context is unreliable.

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

## Documentation

| Document | Contents |
| :--- | :--- |
| [docs/guide.md](docs/guide.md) | Full reference: levels, formats, sinks, context, BEAM integration, API table |
| [docs/migration_v1_3.md](docs/migration_v1_3.md) | Upgrading from v1.2 - what changed and how to fix it |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [hexdocs.pm/woof](https://hexdocs.pm/woof/) | Generated module reference |

## Requirements

- Gleam **1.14** or newer
- OTP **22+** on the BEAM (CI uses OTP 28)
- `gleam_stdlib` the only dependency

---

<p align="center">Made with Gleam 💜</p>
