# Production setup

The v1.9 wrappers exist to answer four questions that only come up once a
service is handling real traffic: what does storage cost, what happens
during a burst, what happens if a secret ends up in a field, and what does
a backend charge per delivery. This walks through wiring them up together.

## A complete pipeline

```gleam
import woof

pub fn main() {
  woof.prod()
  woof.set_resource([
    woof.str("service.name", "checkout"),
    woof.str("service.version", "1.9.0"),
  ])

  woof.set_event_sink(
    otlp_http_sink
    |> woof.redact_event_sink(["password", "authorization", "credit_card"])
    |> woof.rate_limit_event_sink(2000)
    |> woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error)
    |> woof.batch_event_sink(200, 5000),
  )
}
```

See [sink_composition.md](sink_composition.md) for why this order - redact
first, batch last - is the one that matters.

## Sampling vs. rate limiting - they solve different problems

These get reached for interchangeably because both "reduce the number of
events that go out," but they answer different questions and neither
substitutes for the other:

- **Rate limiting** (`rate_limit_event_sink`) is about *protecting your
  infrastructure* from a burst. It has no idea what the events mean - it
  just caps throughput. Use it when a bug, retry storm, or traffic spike
  could otherwise flood the sink. It is reactive: it only drops once you're
  over the limit, and what it drops depends on arrival order, not
  importance.

- **Sampling** (`sample_event_sink`, `consistent_sample_event_sink`) is
  about *reducing steady-state volume* while keeping a statistically
  representative slice. It runs all the time, not just during a spike. Use
  it when the normal volume itself is too expensive to store in full, but
  you still want to see typical behavior, not just what happened to be
  under the rate cap.

A production setup usually wants both: sampling to control the everyday
cost, rate limiting as a backstop for the moments sampling alone can't
handle (a burst so large that even the sampled fraction is too much).

Between the two sampling wrappers: reach for
`consistent_sample_event_sink` whenever the events being sampled are part
of a larger unit - a trace, a request, a job - because independent
per-event sampling (`sample_event_sink`) will otherwise show you half a
trace with no way to tell what's missing. Use `sample_event_sink` for
standalone events with no such grouping key.

## What always bypasses sampling and rate limiting

Both sampling wrappers take an `always_keep_above` level - events at or
above it are never dropped, regardless of rate. Set this to `woof.Error`
or higher in production: errors are exactly the events you cannot afford
to lose to a coin flip.

`rate_limit_event_sink` has no such bypass - a large enough burst drops
everything indiscriminately, including errors, because dropping is the
entire point of a hard cap. Size `per_second` generously enough that
normal error volume never gets anywhere near it.

## Related documents

- [sink_composition.md](sink_composition.md) - composition order and why
- [benchmarks.md](benchmarks.md) - measured overhead per wrapper
- [semantic_conventions.md](semantic_conventions.md) - field naming used by
  `error_with` and friends
