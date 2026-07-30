# woof Roadmap (post v1.6)

The path from v1.6 to v2.0. Four releases that take woof from a "data-driven
logging frontend" to the standard logging library for Gleam.

**Current version:** v1.9.0

## Upcoming releases at a glance

| Version | Theme | Key additions | Status |
| :------ | :---- | :------------ | :----- |
| v1.7 | Complete data model | `FList`, `FMap`, `FNull` with native JSON output | shipped |
| v1.7.1 | Robustness patch | NaN/Inf JSON safety, ANSI strip in Text, sink crash isolation | shipped |
| v1.8 | OpenTelemetry | Trace correlation, OTLP output, semantic conventions | shipped |
| v1.9 | Production hardening | Sampling, rate limiting, redaction, batching, benchmarks | shipped |
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
* All v1.7 to v1.9 additions

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
  in the last 1.x release. Reconsider as a v1.9.x patch or a separate
  plugin package once there is concrete demand.

## Release criteria

Every release ships when:

1. All deliverables planned for the release are complete
2. Tests pass on both BEAM and JavaScript targets
3. Every new public API has TDD tests
4. README, CHANGELOG, and guide are updated
5. `gleam publish --dry-run` succeeds

## Related documents

* [CHANGELOG.md](CHANGELOG.md): release history
* [docs/guide.md](docs/guide.md): full library reference
* [README.md](README.md): quick start and overview
