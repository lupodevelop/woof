# woof Roadmap

Released features, the v1.10 release scope, and planned v2.0 cleanup.

**Current version:** v1.10.0

## Releases at a glance

| Version | Theme | Key additions | Status |
| :------ | :---- | :------------ | :----- |
| v1.7 | Complete data model | `FList`, `FMap`, `FNull` with native JSON output | shipped |
| v1.7.1 | Robustness patch | NaN/Inf JSON safety, ANSI strip in Text, sink crash isolation | shipped |
| v1.8 | OpenTelemetry | Trace correlation, OTLP output, semantic conventions | shipped |
| v1.9 | Production hardening | Sampling, rate limiting, redaction, batching, benchmarks | shipped |
| v1.10 | Compatible improvements | Typed fan-out, lazy instance logging, JSON/redaction fixes, exception-safe scopes | release preparation |
| v2.0 | Cleanup | Remove `Entry`, `Format`, legacy sink, deprecated field helpers | planned |

## v1.7: Complete Data Model and Native JSON

Finishes the typed-fields promise from v1.3. JSON output becomes truly
data-driven instead of stringifying every value.

* New `FieldValue` variants: `FList(List(FieldValue))`,
  `FMap(List(#(String, FieldValue)))`, `FNull`
* New constructors: `woof.list`, `woof.map`, `woof.null`, plus raw-value
  helpers `vstr`, `vint`, `vfloat`, `vbool`, `vnull` for nested construction
* JSON formatter emits real types (`42`, `true`, `null`, nested arrays and
  objects) instead of stringified values
* Public format helpers: `format_event_json`, `format_event_text`,
  `format_event_compact` for users writing custom sinks
* Erlang FFI extension mapping new variants to native Erlang terms

Backwards-compatible at the Gleam API level.

## v1.8: OpenTelemetry and Trace Correlation

Closes the biggest credibility gap versus mature loggers in other ecosystems
(Rust `tracing`, Go `slog`, Java `log4j2`).

* `with_trace(trace_id, span_id, body)` for scoped trace propagation
* `set_trace(logger, trace_id, span_id) -> Logger` for instanced propagation
* `current_trace() -> Option(#(String, String))` to read the active trace
* New `Format.OtlpJson` producing OpenTelemetry-shaped output
  (`severity_number`, `severity_text`, `body`, `attributes`, `trace_id`,
  `span_id`, `resource`)
* `set_resource` / `get_resource` for OTel resource attributes
  (`service.name`, `service.version`, etc.)
* New documentation:
  * `docs/semantic_conventions.md` covering standard field names
  * `docs/log_levels.md` "choosing the right log level"

## v1.9: Production Hardening

The features that separate a hobby logger from production-grade
infrastructure. Trimmed from the initial draft after review: `log_if` and
`rename_event_sink` were cut (both are a few lines the caller can write
directly - not worth a maintained API), and `limit_fields_event_sink` was
moved to "Out of scope" pending a concrete use case (see below).

* Composable sink wrappers (operate on `EventSink`):
  * `sample_event_sink(rate, always_keep_above, sink)` probabilistic sampling
  * `consistent_sample_event_sink(rate, key_field, always_keep_above, sink)`
    trace-coherent sampling: deterministic by hashing `key_field`
    (FNV-1a, denominator 10_000), so every log line tied to a trace
    stays together as a group
  * `rate_limit_event_sink(per_second, sink)` token-bucket flood protection
  * `redact_event_sink(keys, sink)` PII / secret masking, recursive
  * `batch_event_sink(max_size, max_interval_ms, sink)` groups events into
    a `fn(List(LogEvent)) -> Nil` batch sink, flushed by size or time -
    turns N per-event deliveries into one call, for backends that charge
    or add latency per request
* `log_at_most(n, key, level, message, fields)` caps a log line to the
  first `n` calls sharing `key`, for the rest of the process lifetime
* `error_with(message, err, fields)` structured error helper aligned with
  OTel `error.*` conventions
* `test/bench/woof_bench.gleam` - criterion-style benchmark vs a direct
  sink for every wrapper above (lives under `test/`, not a top-level
  `bench/`, since Gleam only compiles `src/` and `test/`)
* New documentation:
  * `docs/production_setup.md`
  * `docs/sink_composition.md`
  * `docs/benchmarks.md`

## v1.10: Compatible Improvements

* `fanout_event_sink(List(EventSink)) -> EventSink`: synchronous typed fan-out
  with ordered delivery and failure isolation per destination.
* `log_lazy(Logger, Level, fn() -> #(String, List(#(String, FieldValue)))) -> Nil`:
  defer message and field construction, preserving logger context and trace.
* Escape all JSON control characters and redact matching keys through nested
  lists and maps.
* Restore scoped context and traces when callbacks raise, without swallowing
  exceptions.
* Correct production examples and document batching, redaction and async scope
  boundaries. Existing public APIs, signatures and defaults are preserved.

Follow-ups remain separate: atomic shared state and ETS ownership for BEAM sink
wrappers, explicit batch flushing, and typed JSON parity for `emit` on legacy sinks.
The 1.10 changes do not resolve those limitations.

## v2.0: The Cleanup

By v1.9 every feature already exists on the typed `LogEvent` path. v2.0
removes the duplicated legacy paths.

**Removed:**

* `Entry` type and `fn(Entry, String) -> Nil` legacy sink signature
* `Format` type, `set_format`, `get_format`, `format(Entry, Format)`
  (formatting moves into the sink)
* Deprecated field helpers: `field`, `int_field`, `float_field`, `bool_field`
* `beam_logger_sink` (superseded by `beam_event_sink`)

**Renamed** (one identifier per concept):

* `EventSink` becomes `Sink`
* `set_event_sink` becomes `set_sink`
* `clear_event_sink` becomes `clear_sink`
* `filter_event_sink` becomes `filter_sink` (and other v1.9 wrappers
  similarly)

**Unchanged** (stable across the cleanup):

* All eight log shortcut functions (`debug`, `info`, ..., `emergency`)
* All context APIs (`with_context`, `set_global_context`, instanced `Logger`)
* All pipeline helpers (`tap_*`, `log_error`, `time`, `inspect`, `tap_time`)
* Typed event helpers added in v1.7 through v1.10, subject to the sink renames above

**Architectural follow-ups (carried over from audit):**

* **JS FFI typed-field handling.** Currently `beam_event_log` on JavaScript
  ignores the `fields` argument and routes the pre-formatted message to
  `console.*`. With the unified `Sink = fn(LogEvent) -> Nil` contract the
  JS sink can pattern-match on `FieldValue` and emit structured objects
  via `console.dir` or similar.
* **Custom formatter access to typed values.** Today `Custom(fn(Entry))`
  receives only stringified fields (Entry-based path). Removing `Entry`
  in v2.0 lets custom formatters operate directly on `LogEvent`, gaining
  full type fidelity.

A migration guide will ship as `docs/migration_v2_0.md`.

## Out of scope

Considered and intentionally excluded:

* **`woof.diff(a, b)` structural diff helper.** Needs a structural
  comparison API not in `gleam_stdlib`. Reconsider when stdlib gains one.
* **External sink packages** (`woof_loki`, `woof_datadog`, `woof_otlp`).
  Belong in separate repositories when there is community demand. The v1.9
  sink composition primitives are sufficient to build them.
* **Transparent / Hybrid BEAM mode flag.** The BEAM sink already delegates
  to OTP by default; an extra mode adds complexity without clear benefit.
* **`limit_fields_event_sink(max_fields, sink)` cardinality cap.** Drafted
  for v1.9, then cut: field-count cardinality is primarily a *metrics*
  cost problem (unique label combinations multiply storage), less clearly
  one for logs, where the fields that matter vary per event by design.
  Reconsider if a concrete production case shows uncapped field counts
  causing real cost or noise - not before.
* **Sharded fan-out (`shard_event_sink`) and full consistent-hashing
  ring with virtual nodes.** v1.9 ships `consistent_sample_event_sink`
  for trace-coherent sampling, which is the strong, demanded use case.
  Multi-sink fan-out by hashed key is niche, has weaker semantics under
  resize (plain mod-N is not consistent hashing), and pins API surface
  without demonstrated demand. Reconsider as a separate
  plugin package once there is concrete demand.

## Release criteria

Every release ships when:

1. All deliverables planned for the release are complete
2. Tests pass on both BEAM and JavaScript targets
3. Every new public API has TDD tests
4. README, CHANGELOG, and guide are updated
5. `gleam docs build` and `gleam export hex-tarball` succeed locally

## Related documents

* [CHANGELOG.md](CHANGELOG.md): release history
* [docs/guide.md](docs/guide.md): full library reference
* [README.md](README.md): quick start and overview
