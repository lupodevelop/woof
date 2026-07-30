// Home-made benchmark for the v1.9 sink wrappers - no external benchmarking
// dependency, just a monotonic timer around a tight loop.
//
// Gleam only compiles `src/` and `test/`, so this lives under `test/bench/`
// rather than a plain top-level `bench/` (which the build tool does not
// see). Run it with:
//
//   gleam run -m bench/woof_bench
//   gleam run -m bench/woof_bench --target javascript
//
// It measures the cost of `woof.info` through each v1.9 wrapper against a
// direct sink, so a regression in a wrapper shows up as a duration jump.
// Results in docs/benchmarks.md.

import gleam/int
import gleam/io
import gleam/list
import woof

@external(erlang, "woof_ffi", "monotonic_now")
@external(javascript, "../woof_ffi.mjs", "monotonic_now")
fn monotonic_now() -> Int

const iterations = 100_000

pub fn main() {
  woof.set_sink(woof.silent_sink)
  woof.set_level(woof.Debug)

  run("direct sink (no wrapper)", fn(sink) { sink })
  run("redact_event_sink", fn(sink) {
    woof.redact_event_sink(["password"], sink)
  })
  run("sample_event_sink(1.0)", fn(sink) {
    woof.sample_event_sink(1.0, woof.Error, sink)
  })
  run("consistent_sample_event_sink(1.0)", fn(sink) {
    woof.consistent_sample_event_sink(1.0, "trace_id", woof.Error, sink)
  })
  run("rate_limit_event_sink(1_000_000/s)", fn(sink) {
    woof.rate_limit_event_sink(1_000_000, sink)
  })
  run("batch_event_sink(100, 60_000ms)", fn(_sink) {
    woof.batch_event_sink(100, 60_000, fn(_batch) { Nil })
  })
}

fn run(label: String, wrap: fn(woof.EventSink) -> woof.EventSink) {
  woof.set_event_sink(wrap(fn(_event) { Nil }))

  let start = monotonic_now()
  list.repeat(Nil, iterations)
  |> list.each(fn(_) { woof.info("bench", [woof.str("trace_id", "t1")]) })
  let elapsed_ms = monotonic_now() - start

  let us_per_event = elapsed_ms * 1000 / iterations
  io.println(
    label
    <> ": "
    <> int.to_string(elapsed_ms)
    <> "ms total, ~"
    <> int.to_string(us_per_event)
    <> "us/event",
  )
}
