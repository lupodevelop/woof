# woof Roadmap (post v1.6)

The path from v1.6 to v2.0. Four releases that take woof from a "data-driven
logging frontend" to the standard logging library for Gleam.

**Current version:** v1.6.0

## Upcoming releases at a glance

| Version | Theme | Key additions |
| :------ | :---- | :------------ |
| v1.7 | Complete data model | `FList`, `FMap`, `FNull` with native JSON output |
| v1.8 | OpenTelemetry | Trace correlation, OTLP output, semantic conventions |
| v1.9 | Production hardening | Sampling, rate limiting, redaction, cardinality cap, benchmarks |
| v2.0 | Cleanup | Remove `Entry`, `Format`, legacy sink, deprecated field helpers |

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
infrastructure.

* Composable sink wrappers (operate on `EventSink`):
  * `sample_event_sink(rate, always_keep_above, sink)` probabilistic sampling
  * `rate_limit_event_sink(per_second, sink)` token-bucket flood protection
  * `redact_event_sink(keys, sink)` PII / secret masking, recursive
  * `limit_fields_event_sink(max_fields, sink)` cardinality cap
  * `rename_event_sink(rules, sink)` field name normalization
* Conditional logging: `log_if(condition, level, message, fields)` and
  `log_at_most(n, key, level, message, fields)`
* `error_with(message, err, fields)` structured error helper aligned with
  OTel `error.*` conventions
* `bench/` directory with criterion-style benchmarks vs raw OTP
  `logger:log/4`
* New documentation:
  * `docs/production_setup.md`
  * `docs/cardinality.md`
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
* **Cardinality sanitiser as a hard runtime constraint.** Documentation
  plus `limit_fields_event_sink` (v1.9) cover this without policing user
  code.

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
