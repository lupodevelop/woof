# Composing sink wrappers

The v1.9 sink wrappers all share the same shape - `EventSink -> EventSink`
(`batch_event_sink` is the one exception, see below) - so they compose with
`|>` like anything else in Gleam. The order you stack them in changes what
each wrapper actually sees, and getting it wrong quietly breaks the
guarantee each one is supposed to provide.

## The rule: redact first, batch last

```gleam
woof.set_event_sink(
  base_sink
  |> woof.redact_event_sink(["password", "token"])
  |> woof.rate_limit_event_sink(1000)
  |> woof.consistent_sample_event_sink(0.1, "trace_id", woof.Error)
  |> woof.batch_event_sink(100, 5000)
)
```

**`redact_event_sink` goes first (closest to the source).** It has to see
every field before anything else has a chance to drop the event. If it ran
after sampling, an event that got sampled out never reaches redaction - not
a problem in itself, but an event that *does* survive sampling and skips
redaction because of ordering is a leaked secret. Put it where it always
runs.

**Rate limiting and sampling go in the middle.** They decide what survives.
Order between the two matters less, but rate-limiting first is usually
right: it protects against bursts regardless of what sampling would have
kept, and it's cheap (integer math) compared to hashing for
`consistent_sample_event_sink`.

**`batch_event_sink` goes last.** It should only ever buffer events that
already passed every other filter - batching before sampling means you
spend buffer space (and, if the batch flushes, delivery cost) on events
that get thrown away a step later. It also means the buffered batch inside
`batch_event_sink` only ever holds events worth delivering.

## `batch_event_sink` breaks the chain

Every other wrapper takes and returns an `EventSink`
(`fn(LogEvent) -> Nil`), so they compose freely with `|>`. `batch_event_sink`
does not: it wraps a **batch sink**, `fn(List(LogEvent)) -> Nil`, because
the entire point is delivering many events in one call instead of one call
per event. That means it has to be the last step in the pipeline - it turns
"one event in" into "many events, eventually" and there is nothing
meaningful to stack after it that still speaks `EventSink`.

```gleam
// batch_event_sink's own `sink` argument sees a List(LogEvent), not one:
woof.batch_event_sink(100, 5000, fn(events: List(woof.LogEvent)) {
  send_to_log_backend(events)
})
```

## Why not check this at compile time

Gleam's type system enforces that every wrapper except `batch_event_sink`
composes with `|>` - a type error catches "used the wrong sink shape". It
does not catch "sampled before redacting" - that is a logical ordering
mistake within functions that all type-check fine. There is no free way to
encode "must run before that other one" in the type system without turning
every wrapper into its own type, which is not worth it for five functions.
Get the order right by following the rule above, not by relying on the
compiler.

See [production_setup.md](production_setup.md) for a complete pipeline
walked through end to end.
