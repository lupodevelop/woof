# Production setup

Compose redaction, volume controls and batching around a delivery function. The
example below accepts a batch sender supplied by your application; woof does not
include an HTTP exporter.

## A complete pipeline

```gleam
import woof

pub fn setup(deliver: fn(List(woof.LogEvent)) -> Nil) -> Nil {
  woof.prod()
  woof.set_sinks([])
  woof.set_resource([
    woof.str("service.name", "checkout"),
    woof.str("service.version", "1.0.0"),
  ])

  let batched = woof.batch_event_sink(200, 5000, deliver)
  let sampled =
    woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error, batched)
  let limited = woof.rate_limit_event_sink(2000, sampled)
  let protected =
    woof.redact_event_sink(["password", "authorization", "credit_card"], limited)
  woof.set_event_sink(protected)
}
```

Call `setup(send_batch)` at application startup. Build wrappers from the destination
outward; events run through redaction, rate limiting, sampling, then batching.
The sender receives typed events and owns formatting, transport and delivery
failures. `format_event_otlp` includes the configured resource attributes when
formatting an event; `prod()` does not format events inside your custom sender.

`set_sinks([])` disables the independent legacy sink installed by `prod()`. Without
it, the original fields also go to that sink, outside the redaction wrapper.
Redaction matches exact field keys recursively through maps and lists; it does not
scrub free-form messages or substrings inside values.

See [sink_composition.md](sink_composition.md) for construction order and fan-out.

## Sampling and rate limiting

Sampling reduces steady-state volume. `consistent_sample_event_sink` makes the
same decision for events sharing the configured key, such as `trace_id`. Events
missing that key pass through. `sample_event_sink` instead makes an independent
decision for every event below the severity bypass.

Rate limiting protects a destination against bursts. The bucket starts full,
allows an initial burst up to `per_second`, and refills continuously. In this
example it runs before sampling, so sampled-out events can still consume tokens.

Both sampling wrappers always pass events at or above `always_keep_above`. The
example uses `Error`. The rate limiter has no severity bypass: it can still drop
errors during a burst. Sampling also does not preserve events dropped by the
configured minimum level before they reach the pipeline.

## Batching and shared state

Batch thresholds are checked only when an event arrives. A partial batch can stay
buffered indefinitely during idle periods, and it is not flushed automatically on
shutdown. Delivery is synchronous; there is no retry queue or delivery guarantee.

On BEAM, the batch and rate-limit wrappers store state in ETS tables owned by the
process that creates them. The tables disappear when that process exits. Updates
use separate reads and writes, so concurrent callers can overwrite each other's
state. Use a single long-lived calling process for these wrappers; they do not
provide an atomic node-wide rate limit or concurrent batch queue.

`log_at_most` also uses non-atomic shared counter updates on BEAM. Its keys should
be fixed call-site identifiers, not user input, since they are never cleared.

## Scoped metadata and asynchronous work

`with_context` and `with_trace` restore the previous scope on normal return and on
exceptions. Errors propagate to the caller. On BEAM the scope belongs to the
calling process and is not inherited automatically by spawned processes.

On JavaScript these scopes are synchronous module-level state. They do not follow
Promise continuations. Pass a `Logger` with `set_context` and `set_trace` through
asynchronous work instead. `log_lazy` preserves that logger metadata while
deferring both the message and fields until the configured level permits them.

## Related documents

- [sink_composition.md](sink_composition.md): wrapper order and fan-out
- [benchmarks.md](benchmarks.md): recorded v1.9 wrapper measurements
- [semantic_conventions.md](semantic_conventions.md): field naming
