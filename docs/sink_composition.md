# Composing sink wrappers

An `EventSink` receives one typed `LogEvent`. Filtering, redaction, sampling and
rate limiting wrap one `EventSink` and return another. Batching instead wraps a
function that receives `List(LogEvent)` and returns an `EventSink`.

## Build from the destination outward

```gleam
import woof

pub fn pipeline(deliver: fn(List(woof.LogEvent)) -> Nil) -> woof.EventSink {
  let batched = woof.batch_event_sink(100, 5000, deliver)
  let sampled =
    woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error, batched)
  let limited = woof.rate_limit_event_sink(1000, sampled)
  woof.redact_event_sink(["password", "token"], limited)
}
```

The last wrapper constructed receives the event first. This example runs:

```text
event → redact → rate limit → sample → batch → deliver
```

Redaction runs before buffering or delivery. The rate limiter caps incoming
volume, including events sampling might later drop. Sampling then reduces the
events that reach the batch buffer. Reverse the two volume controls if the cap
should apply only to the sampled traffic.

Putting sampling before redaction does not itself leak surviving events: they
still pass through the redaction wrapper. What matters is that every destination
that needs masking is downstream of redaction.

Use explicit arguments as above. These wrappers take the sink last, so an ordinary
`sink |> woof.redact_event_sink(keys)` inserts it into the wrong argument. A pipe
requires an explicit placeholder: `sink |> woof.redact_event_sink(keys, _)`.

## Batch the destination first

`batch_event_sink` consumes `fn(List(LogEvent)) -> Nil` and returns
`fn(LogEvent) -> Nil`. Construct it from the batch delivery function, then place
other event wrappers around the result. It cannot consume an already wrapped
per-event sink.

Batches flush when an incoming event reaches the size or elapsed-time threshold.
There is no background timer, explicit flush API or automatic shutdown delivery.
See [production_setup.md](production_setup.md) for lifecycle and concurrency limits.

## Share redaction across destinations

`fanout_event_sink` forwards an event to each destination synchronously, in list
order. Each destination is isolated from failures in the others; a slow sink
still delays subsequent sinks. An empty list discards events.

```gleam
let destinations = woof.fanout_event_sink([woof.beam_event_sink, audit_sink])
let protected = woof.redact_event_sink(["password", "token"], destinations)
woof.set_sinks([])
woof.set_event_sink(protected)
```

Redaction outside fan-out masks every branch. Wrapping just one branch masks only
that branch. Typed event sinks and legacy sinks are independent: `set_event_sink`
does not disable the default output or the legacy sink installed by `prod()`.
Use `set_sinks([])` when the protected pipeline should be the only output.
