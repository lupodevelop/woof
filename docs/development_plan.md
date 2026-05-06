# Woof: Development Plan
**Status:** Working Document | **Current version:** v1.6.0

---

## Current State (v1.6.0)

### What exists

| Area | Implementation |
| :--- | :--- |
| Levels | All 8 OTP levels (`Debug`, `Info`, `Notice`, `Warning`, `Error`, `Critical`, `Alert`, `Emergency`) |
| Fields | Typed `FieldValue` (`FString` / `FInt` / `FFloat` / `FBool`) |
| Sinks | Dual: legacy `fn(Entry, String)` + typed `EventSink = fn(LogEvent) -> Nil` |
| Multi-sink | `set_sinks(List(Sink))` + composable `filter_event_sink` |
| Formats | `Text`, `Json` (string-serialised values), `Compact`, `Custom(fn)` |
| Context | Global + scoped (`with_context`) + instanced Logger context |
| Logger | Namespaced + child loggers (`child(Logger, String)`) |
| Pipeline | `tap_*`, `log_error`, `time`, `inspect`, `tap_time` |
| BEAM | `beam_logger_sink` (formatted) + `beam_event_sink` (native typed terms) |
| JS | Module-level state, `console.*` routing, TTY detection |
| Config | `set_level_from_env`, `level_from_string`, `get_level`, `is_enabled` |
| Bridging | Public `emit(LogEvent)` for replay/external bridging |
| Tests | 115 tests, both BEAM and JS targets |

### Remaining gaps before v2.0

1. **Incomplete data model.** No `FList` / `FMap` / `FNull`: promised in v1.3 roadmap but never shipped. Nested data is impossible to represent without serialising to a string.
2. **JSON output stringifies values.** `FInt(42)` → `"42"`, `FBool(True)` → `"true"`. Embarrassing for a "data-driven" library; downstream JSON consumers cannot rely on types.
3. **No OpenTelemetry semantics.** No `trace_id` / `span_id` correlation, no OTLP-compatible output. Required to be taken seriously as observability infrastructure.
4. **No production hardening.** No sampling, rate limiting, redaction, or cardinality cap. Required for high-volume / regulated environments.
5. **Legacy sink + formatter still load-bearing.** `Entry`, `Format`, `set_format`, and `fn(Entry, String)` will be removed in v2.0; need final cleanup pass.

### Starting Point: Original v1.2.0 baseline (historical)

The library shipped v1.2.0 with: 4 log levels, string-only fields,
single sink of type `fn(Entry, String) -> Nil`, only `set_sink` (no
multi-sink), `beam_logger_sink` mapping 4→8 levels with information loss,
51 tests. Everything in §"What exists" above was added in v1.3 → v1.6.

---

## Architectural Direction

The core move across v1.3 → v2.0 is:

```
v1.x   fields: #(String, String)   sink: fn(Entry, String) -> Nil
v2.0   fields: FieldValue          sink: fn(LogEvent) -> Nil
```

The formatter moves **inside the sink**, not before it. The sink decides if and how to format. This makes the BEAM sink a true OTP-native citizen and makes the test sink trivially accurate.

The pipeline stays the same. The API surface stays small. The breaking changes are isolated to the field type and sink signature.

---

## v1.3: Typed Fields (Transition)

**Goal:** introduce `FieldValue` and `LogEvent` as opt-in additions, without removing anything. Users who pass `#(String, String)` keep working.

### New types

```gleam
pub type FieldValue {
  FString(String)
  FInt(Int)
  FFloat(Float)
  FBool(Bool)
  FList(List(FieldValue))
  FMap(List(#(String, FieldValue)))
}

pub type LogEvent {
  LogEvent(
    level: Level,
    message: String,
    fields: List(#(String, FieldValue)),
    timestamp: Int,           // monotonic ms
    namespace: Option(String),
    context: List(#(String, FieldValue)),
  )
}
```

### New field constructors

```gleam
pub fn str(key: String, value: String) -> #(String, FieldValue)
pub fn int(key: String, value: Int) -> #(String, FieldValue)
pub fn float(key: String, value: Float) -> #(String, FieldValue)
pub fn bool(key: String, value: Bool) -> #(String, FieldValue)
pub fn list(key: String, value: List(FieldValue)) -> #(String, FieldValue)
pub fn map(key: String, value: List(#(String, FieldValue))) -> #(String, FieldValue)
```

These coexist with the existing `field`, `int_field`, `float_field`, `bool_field` helpers. The old helpers are soft-deprecated (documented as legacy, not removed).

### New Sink signature

```gleam
pub type Sink = fn(LogEvent) -> Nil
```

The old `fn(Entry, String) -> Nil` signature is kept as `LegacySink` for one release cycle. The existing `default_sink`, `beam_logger_sink`, `silent_sink` are ported to the new signature. A compatibility shim wraps old sinks for users who have custom implementations.

### TestSink

```gleam
pub fn test_sink() -> #(Sink, fn() -> List(LogEvent))
```

Returns a sink function and a capture function. The sink appends events to a process-local list. The capture function returns and clears the list.

```gleam
// Usage in tests
let #(sink, get_events) = woof.test_sink()
woof.set_sink(sink)
woof.error("something failed", [woof.int("code", 42)])
let events = get_events()
assert list.any(events, fn(e) { e.level == Error })
```

### Migration path for existing `Entry` users

`Entry` is kept. The internal `emit` path builds both an `Entry` (for format-aware sinks) and a `LogEvent` (for new-style sinks). New `set_sink` accepts `fn(LogEvent) -> Nil`. Legacy `set_legacy_sink` accepts `fn(Entry, String) -> Nil`. Both can coexist.

### Deliverables

- [x] Define `FieldValue` and `LogEvent` types
- [x] Add `str`, `int`, `float`, `bool` constructors *(`list`, `map` deferred to v1.7)*
- [x] Port `default_sink`, `beam_logger_sink`, `silent_sink` to new signature
- [x] Implement `test_sink()`
- [x] Add `set_event_sink` accepting `fn(LogEvent) -> Nil` *(coexists with legacy)*
- [x] Keep legacy `set_sink` for old signature *(both channels active)*
- [x] Update all logging functions to build `LogEvent`
- [x] Add tests for all new constructors and TestSink
- [x] Update README with migration guide

---

## v1.4: Extended Levels, BeamSink v2, Dispatcher

**Goal:** complete OTP alignment, fix the BEAM sink to be truly structured, allow multiple sinks.

### Extended Level type

```gleam
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
```

The level ordering is ordinal. `is_enabled` and the fast-path filter use integer comparison.

```gleam
fn level_to_int(level: Level) -> Int {
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
```

**Semantic guidance (documented, not enforced):**

| Level | Use for |
| :--- | :--- |
| Debug | Development traces |
| Info | Normal application flow |
| Notice | Significant business events (not errors) |
| Warning | Anomalous but recoverable situations |
| Error | Failures requiring attention |
| Critical | System degradation, partial failure |
| Alert | Immediate action required |
| Emergency | System is unusable |

New shortcut functions: `notice`, `critical`, `alert`, `emergency` (and their `_lazy` variants).

### BeamSink v2

The new BEAM sink sends a structured report. It never calls `io:format`. It maps `FieldValue` directly to Erlang terms via the FFI.

```erlang
%% What OTP logger receives
logger:log(info, #{msg => <<"User login">>}, #{
  woof => #{
    fields   => #{user_id => 42, success => true},
    context  => #{},
    namespace => <<"api">>,
    timestamp => 1712926187
  },
  domain => [woof]
})
```

`FieldValue` mapping:

| Gleam | Erlang |
| :--- | :--- |
| `FString` | `binary()` |
| `FInt` | `integer()` |
| `FFloat` | `float()` |
| `FBool` | `true` / `false` |
| `FList` | `list()` |
| `FMap` | `map()` (binary keys) |

The Erlang FFI conversion loop lives in `woof_ffi.erl`. The Gleam layer passes the raw `LogEvent` fields; the FFI does the term conversion.

### Dispatcher

```gleam
pub fn set_sinks(sinks: List(Sink)) -> Nil
```

Replaces `set_sink`. Each event is delivered to every registered sink in order. Error in one sink does not prevent delivery to others (errors are caught and logged to stderr).

### Presets

```gleam
pub fn dev() -> Nil    // pretty stdout, Debug level, colors Auto
pub fn prod() -> Nil   // beam_logger_sink, Info level
```

These call `configure` and `set_sinks` atomically.

### Deliverables

- [x] Extend `Level` to 8 values
- [x] Update `level_to_int` and `level_tag`
- [x] Add `notice`, `critical`, `alert`, `emergency` (and `_lazy`) functions
- [x] Add `beam_event_sink` using structured report via FFI *(beam_logger_sink left for legacy compat)*
- [x] Implement `FieldValue -> Erlang term` conversion in `woof_ffi.erl`
- [x] Add `set_sinks(List(Sink))` dispatcher
- [x] Add `dev()` and `prod()` preset functions
- [x] Add tests for new levels, BeamSink structured output, dispatcher

---

## v1.5: Deprecations & DX Completions

**Goal:** close the gap before v2.0, add developer quality-of-life tools.

### Soft deprecations (warnings in docs, not compile errors)

- `field(key, value)` → use `woof.str(key, value)` instead
- `int_field`, `float_field`, `bool_field` → use `woof.int`, `woof.float`, `woof.bool`
- `set_global_context(List(#(String, String)))` on JS → instanced loggers are the right model
- `set_legacy_sink` → migrate to `fn(LogEvent) -> Nil`

### Instanced loggers

Extend `Logger` to carry its own context:

```gleam
pub opaque type Logger {
  Logger(namespace: Option(String), context: List(#(String, FieldValue)))
}

pub fn new(namespace: String) -> Logger
pub fn with_context(logger: Logger, ctx: List(#(String, FieldValue))) -> Logger
pub fn log(logger: Logger, level: Level, msg: String, fields: List(#(String, FieldValue))) -> Nil
```

The instanced logger is the recommended pattern for JS targets where global context is unreliable in async code.

### Debugging helpers

```gleam
pub fn inspect(value: a, label: String) -> a
// Logs the Gleam string_tree representation of value at Debug level, returns value

pub fn tap_time(value: a, label: String) -> a
// Measures time between calls in a pipeline: logs at Debug level
```

`woof.diff` is deferred to v2.0 or later as it requires a structural comparison API that doesn't yet exist in Gleam stdlib.

### Deliverables

- [x] Extend `Logger` type to carry typed context
- [x] Add `set_context` and `append_context` builders on Logger
- [x] Add `inspect(value, label)` pipeline helper
- [x] Add `tap_time(value, label)` pipeline helper
- [x] `@deprecated` attribute on `field`, `int_field`, `float_field`, `bool_field`
- [x] JS-specific guide: "Using woof in async contexts" *(in docs/guide.md)*
- [x] Bonus: `level_from_string`, `set_level_from_env`, `get_level`

---

## v1.6: Sink Composition & Logger Ergonomics

**Goal:** close the remaining DX gaps before v2.0.  All additions are backwards-compatible.

### `child(Logger, String) -> Logger`

Create a sub-namespace logger that inherits the parent's context.
The child namespace is the parent namespace joined with `.`:

```gleam
let http   = woof.new("http")
let router = woof.child(http, "router")   // namespace: "http.router"
let get    = woof.child(router, "GET")    // namespace: "http.router.GET"
```

Context is copied at creation time (loggers are immutable).  Further calls to
`set_context` / `append_context` on the child do not affect the parent.

### `filter_event_sink(fn(LogEvent) -> Bool, EventSink) -> EventSink`

Wrap an `EventSink` with a predicate.  Only events for which the predicate
returns `True` are forwarded.  Enables selective routing without custom wrappers:

```gleam
woof.set_event_sink(
  woof.filter_event_sink(
    fn(e) { e.level >= woof.Error },
    pagerduty_sink,
  )
)
```

The level comparison `e.level >= woof.Error` works because `Level` values are
ordered by `level_to_int`.

### `emit(LogEvent) -> Nil`

Dispatch a pre-built `LogEvent` through all registered sinks.  Useful for
bridging from external logging systems and for replaying captured events in tests.

```gleam
let event = LogEvent(
  level: woof.Warning,
  message: "replayed event",
  fields: [woof.str("source", "legacy")],
  timestamp: woof.monotonic_now(),
  namespace: None,
)
woof.emit(event)
```

This is also the v1.x-compatible stepping stone toward v2.0, where every
log call ultimately produces and emits a `LogEvent`.

### Deliverables

- [x] `child(Logger, String) -> Logger`
- [x] `filter_event_sink(fn(LogEvent) -> Bool, EventSink) -> EventSink`
- [x] `emit(LogEvent) -> Nil`
- [x] `level_to_int(Level) -> Int` made public (needed for filter predicates)
- [x] Tests for all four (TDD): 11 new tests, 115 total
- [x] Update guide.md and CHANGELOG
- [x] Internal `emit` renamed to `do_log` to free public name

---

## v1.7: Complete Data Model & Native JSON

**Goal:** finish the typed-fields promise from v1.3.  Make JSON output truly
data-driven instead of stringifying every value.  All additions are
backwards-compatible; existing string-based JSON output is replaced by
structurally-typed output (consumers parsing JSON gain type fidelity).

### Extended `FieldValue`

```gleam
pub type FieldValue {
  FString(String)
  FInt(Int)
  FFloat(Float)
  FBool(Bool)
  FList(List(FieldValue))                     // NEW
  FMap(List(#(String, FieldValue)))           // NEW
  FNull                                        // NEW
}
```

### New constructors

```gleam
pub fn list(key: String, items: List(FieldValue)) -> #(String, FieldValue)
pub fn map(key: String, pairs: List(#(String, FieldValue))) -> #(String, FieldValue)
pub fn null(key: String) -> #(String, FieldValue)
```

Plus raw value helpers (no key) for nested construction:

```gleam
pub fn vstr(s: String) -> FieldValue       // FString(s)
pub fn vint(n: Int) -> FieldValue          // FInt(n)
pub fn vfloat(f: Float) -> FieldValue      // FFloat(f)
pub fn vbool(b: Bool) -> FieldValue        // FBool(b)
pub fn vnull() -> FieldValue               // FNull
```

So nested data reads naturally:

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
])
```

### Native JSON output

`Json` format emits real JSON types: not stringified values:

| FieldValue | Before (v1.6) | After (v1.7) |
| :--- | :--- | :--- |
| `FInt(42)` | `"42"` | `42` |
| `FBool(True)` | `"true"` | `true` |
| `FNull` | (n/a) | `null` |
| `FList([FInt(1), FInt(2)])` | (n/a) | `[1, 2]` |
| `FMap([("k", FInt(1))])` | (n/a) | `{"k": 1}` |

This is a behavioural change to the `Json` formatter but not a typed API
break.  Code that grep-parses JSON strings might be fragile; code that uses
a real JSON parser is unaffected.

### Public format helpers

Expose internal formatting as functions on `LogEvent`, useful for users
writing their own sinks:

```gleam
pub fn format_event_json(event: LogEvent) -> String
pub fn format_event_text(event: LogEvent, colors: ColorMode) -> String
pub fn format_event_compact(event: LogEvent) -> String
```

These take a `LogEvent` directly (not an `Entry`) and become the canonical
format API in v2.0 once `Entry`/`Format` are removed.

### BEAM term mapping update

`woof_ffi.erl` `field_value_to_term/1` extends to handle the new variants:

| FieldValue | Erlang term |
| :--- | :--- |
| `FList(items)` | `list()` of recursively converted terms |
| `FMap(pairs)` | `map()` with binary keys, recursive values |
| `FNull` | `null` (atom) |

### Deliverables

- [x] Add `FList`, `FMap`, `FNull` to `FieldValue`
- [x] Add `list`, `map`, `null` field constructors
- [x] Add `vstr`, `vint`, `vfloat`, `vbool`, `vnull` raw-value helpers
- [x] Native JSON serialisation for all variants (numbers, bools, null, arrays, objects)
- [x] Public `format_event_json` / `format_event_text` / `format_event_compact`
- [x] Erlang FFI: extend `field_value_to_term/1` for new variants
- [x] JS FFI: no change needed (message pre-formatted by Gleam)
- [x] Tests: 35 new tests (22 feature + 13 audit), 155 total

---

## v1.8: OpenTelemetry & Trace Correlation

**Goal:** make woof a credible observability frontend.  Standard trace
correlation, OTLP-compatible output, semantic conventions documentation.
This is the biggest credibility gap vs Rust (`tracing`), Go (`slog`/`zap`),
Java (`log4j2`).

### Trace correlation

Three entry points covering scoped, instanced, and read patterns:

```gleam
/// Scoped: trace_id and span_id are added to every log inside `body`.
pub fn with_trace(
  trace_id: String,
  span_id: String,
  body: fn() -> a,
) -> a

/// Instanced: returns a new Logger that carries trace_id and span_id forever.
pub fn set_trace(
  logger: Logger,
  trace_id: String,
  span_id: String,
) -> Logger

/// Read the current scoped trace, if any.
pub fn current_trace() -> Option(#(String, String))
```

Trace fields appear with the OpenTelemetry-conventional names:
`trace_id`, `span_id`.  Stored as `FString`.

### OTLP-compatible output

New `Format` variant `OtlpJson` (or a separate `format_event_otlp` helper):

```json
{
  "timestamp_unix_nano": 1714003200000000000,
  "severity_number": 9,
  "severity_text": "INFO",
  "body": "User login",
  "attributes": { "user.id": 42, "http.method": "POST" },
  "trace_id": "0af7651916cd43dd8448eb211c80319c",
  "span_id": "b7ad6b7169203331",
  "resource": { "service.name": "api", "service.version": "1.6.0" }
}
```

Severity number mapping (OTel 1..24 scale, 21 levels merged into 8):

| Level | severity_number | severity_text |
| :--- | :-: | :--- |
| Debug | 5 | DEBUG |
| Info | 9 | INFO |
| Notice | 10 | INFO2 |
| Warning | 13 | WARN |
| Error | 17 | ERROR |
| Critical | 18 | ERROR2 |
| Alert | 21 | FATAL |
| Emergency | 24 | FATAL4 |

### Resource attributes

Service-level metadata that should appear on every event:

```gleam
pub fn set_resource(attrs: List(#(String, FieldValue))) -> Nil
pub fn get_resource() -> List(#(String, FieldValue))
```

Equivalent to a "global context for resource attributes": distinct from
event-level `set_global_context` because OTel separates resource from
attributes.

### Semantic conventions doc

`docs/semantic_conventions.md`: document standard field names and when to
use them:

- Service: `service.name`, `service.version`, `service.instance.id`
- HTTP: `http.method`, `http.status_code`, `http.url`, `http.route`
- Errors: `error.type`, `error.message`, `error.stacktrace`
- User: `user.id`, `user.email`
- DB: `db.system`, `db.statement`, `db.operation`

### Choosing the right level guide

`docs/log_levels.md`: the practical guide promised in the original roadmap.
Maps each level to:

- Use case (developer trace vs business event vs paging signal)
- Expected volume per minute (orders of magnitude)
- Where it should land (stdout / centralised log / on-call alert)

### Deliverables

- [ ] `with_trace` (scoped) / `set_trace` (instanced) / `current_trace` (read)
- [ ] `Format.OtlpJson` variant + `format_event_otlp` helper
- [ ] Severity number mapping for OTel
- [ ] `set_resource` / `get_resource` for resource attributes
- [ ] `docs/semantic_conventions.md`
- [ ] `docs/log_levels.md` ("Choosing the right log level")
- [ ] Tests: trace propagation BEAM (process dict) and JS (module var)
- [ ] Tests: OTLP output validation against a sample payload

---

## v1.9: Production Hardening

**Goal:** the features that separate a hobby logger from production-grade
infrastructure.  Sampling, rate limiting, redaction, cardinality control,
and a benchmark suite to back perf claims.

### Composable sink wrappers

All operate on `EventSink`: composable via function composition:

```gleam
/// Probabilistic sampling.  Keep `rate` fraction of events.  rate=0.1 → 10%.
/// Higher levels (Error+) bypass sampling by default; configurable.
pub fn sample_event_sink(
  rate: Float,
  always_keep_above: Level,
  sink: EventSink,
) -> EventSink

/// Token-bucket rate limit.  At most `per_second` events forwarded.
pub fn rate_limit_event_sink(
  per_second: Int,
  sink: EventSink,
) -> EventSink

/// Replace named field values with "<redacted>" before forwarding.
/// Recurses into FMap/FList.
pub fn redact_event_sink(
  keys: List(String),
  sink: EventSink,
) -> EventSink

/// Drop fields beyond `max_fields` per event (cardinality cap).
/// Useful before forwarding to Loki/Datadog where every distinct
/// field-value combination is a separate stream.
pub fn limit_fields_event_sink(
  max_fields: Int,
  sink: EventSink,
) -> EventSink

/// Rename fields by a static mapping (e.g. snake_case normalisation).
pub fn rename_event_sink(
  rules: List(#(String, String)),
  sink: EventSink,
) -> EventSink
```

Composition example:

```gleam
woof.set_event_sink(
  woof.beam_event_sink
  |> woof.redact_event_sink(["password", "credit_card", "ssn"], _)
  |> woof.limit_fields_event_sink(50, _)
  |> woof.sample_event_sink(0.1, woof.Warning, _)
)
```

### Conditional / guarded logging

```gleam
/// Log only if `condition` is True. Body and fields are still lazy.
pub fn log_if(
  condition: Bool,
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
) -> Nil

/// Log only the first N occurrences within a process. Helpful for
/// debug output that would otherwise flood when something goes wrong.
pub fn log_at_most(
  n: Int,
  key: String,
  level: Level,
  message: String,
  fields: List(#(String, FieldValue)),
) -> Nil
```

### Structured error helper

```gleam
pub fn error_with(
  message: String,
  err: a,
  fields: List(#(String, FieldValue)),
) -> Nil
```

Logs at Error level adding `error.type` (from `string.inspect(err)` type
prefix) and `error.message` (from `string.inspect(err)`).  Aligned with
OTel error semantic conventions from v1.8.

### Benchmark suite

`bench/` directory comparing:

- Raw OTP `logger:log/4` (baseline)
- woof `info` at Info level (hot path)
- woof `info` at Warning level (filtered fast-path)
- woof `info` with 0/5/20 fields
- woof `info` through `beam_event_sink` (typed terms) vs `beam_logger_sink` (formatted)
- woof `info` with sampling (`sample_event_sink(0.1)`)

Output: throughput (events/sec) + per-event latency (ns).  Published as
`docs/benchmarks.md` so users can verify claims.

### Documentation

- `docs/production_setup.md`: recommended sink composition for prod
- `docs/cardinality.md`: when fields become labels become costs
- `docs/sink_composition.md`: patterns for combining wrappers

### Deliverables

- [ ] `sample_event_sink` (with seedable RNG for deterministic tests)
- [ ] `rate_limit_event_sink` (token-bucket, per-process state)
- [ ] `redact_event_sink` (recursive into FMap/FList)
- [ ] `limit_fields_event_sink`
- [ ] `rename_event_sink`
- [ ] `log_if`, `log_at_most`
- [ ] `error_with` structured error helper
- [ ] `bench/` suite + `docs/benchmarks.md`
- [ ] `docs/production_setup.md`, `docs/cardinality.md`, `docs/sink_composition.md`
- [ ] Tests (TDD) for every wrapper, including composition

---

## v2.0: The Cleanup

**Goal:** remove the legacy string-fields and Entry/Format paths.  Establish
`LogEvent` + `EventSink` as the only public contracts.  By v1.9 every feature
already exists on the new path; v2.0 just removes the duplicates.

### Removals

| Removed | Replacement (already present by v1.9) |
| :--- | :--- |
| `Entry` type | `LogEvent` |
| `Sink = fn(Entry, String) -> Nil` (legacy) | `EventSink = fn(LogEvent) -> Nil` |
| `set_sink`, `set_sinks` (legacy) | `set_event_sink` becomes `set_sink` |
| `Format` type, `set_format`, `get_format` | sink owns its format |
| `format(Entry, Format)` utility | `format_event_*(LogEvent)` from v1.7 |
| `default_sink(entry, formatted)` | `default_sink(event)` formats internally |
| `beam_logger_sink(entry, formatted)` | superseded by `beam_event_sink` |
| `field(key, value)` | `woof.str(key, value)` |
| `int_field`, `float_field`, `bool_field` | `woof.int`, `woof.float`, `woof.bool` |
| `Entry.fields: List(#(String, String))` | `LogEvent.fields: List(#(String, FieldValue))` |

### Renames (only one identifier per concept)

- `set_event_sink` → `set_sink`
- `clear_event_sink` → `clear_sink`
- `EventSink` → `Sink`
- `set_sinks(List(Sink))` keeps its name
- `filter_event_sink` → `filter_sink`
- `sample_event_sink` → `sample_sink` (and other v1.9 wrappers similarly)

### Additions / promotions

- `LogEvent` is the fully public, documented type (already by v1.3)
- `FieldValue` with all variants is the fully public, documented type (complete by v1.7)
- `Sink = fn(LogEvent) -> Nil` is the only sink signature
- `set_sinks(List(Sink))` is the only dispatch API
- `Logger` (instanced) is the recommended entry point; global API is a thin wrapper
- All 8 levels are official
- OTLP semantic output (from v1.8) is one of the canonical formats
- Sink composition wrappers (from v1.9) are the recommended way to add cross-cutting concerns

### What does NOT change

- The top-level `woof.debug`, `woof.info`, `woof.warning`, `woof.error`, etc. shortcuts stay
- `with_context`, `set_global_context`, `get_global_context`, `append_global_context` stay
- `tap_*`, `log_error`, `time`, `inspect`, `tap_time` stay
- `is_enabled`, `get_level`, `set_level`, `level_from_string`, `set_level_from_env` stay
- `beam_event_sink`, `silent_sink`, `default_sink` stay (single signature)
- `Logger`, `new`, `child`, `set_context`, `append_context`, `log` stay
- All v1.7 → v1.9 additions stay unchanged

### Deliverables

- [ ] Remove `Entry` type and all `Entry`-based code paths
- [ ] Remove `Format` type, `set_format`, `format(Entry, Format)` utility
- [ ] Remove deprecated `field`/`int_field`/`float_field`/`bool_field`
- [ ] Remove legacy `Sink` type alias and rename `EventSink` → `Sink`
- [ ] Remove `set_sink(legacy)` and rename `set_event_sink` → `set_sink`
- [ ] Remove `beam_logger_sink` (legacy, superseded by `beam_event_sink`)
- [ ] Update `default_sink` to format `LogEvent` internally
- [ ] Full documentation rewrite
- [ ] Migration guide from v1.x to v2.0 (`docs/migration_v2_0.md`)
- [ ] Bump gleam.toml to 2.0.0

---

## What is explicitly out of scope

These ideas from the roadmap are noted but not planned:

- `woof.diff(a, b)`: requires structural diffing not available in stdlib
- External sink packages (`woof_loki`, `woof_datadog`): separate repos when there's demand
- Field cardinality sanitizer: a documentation concern, not a library concern
- Transparent / Hybrid BEAM mode flag: the BEAM sink delegates to OTP by default; adding modes adds complexity without clear benefit at this stage

---

## Release criteria

Each version ships when:
1. All deliverables in the checklist are done
2. All existing tests pass
3. New tests cover every new public API
4. README and CHANGELOG are updated
5. `gleam publish` dry-run succeeds
