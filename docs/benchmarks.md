# Benchmarks

`test/bench/woof_bench.gleam` measures the per-event cost of `woof.info`
through each v1.9 sink wrapper against a direct sink, so a future
regression in a wrapper shows up as a duration jump. No benchmarking
dependency - a monotonic timer around a tight loop (100,000 iterations).

Gleam only compiles `src/` and `test/`, so the benchmark lives under
`test/bench/` rather than a plain top-level `bench/`, which the build tool
does not see. Run it with:

```sh
gleam run -m bench/woof_bench                    # Erlang target
gleam run -m bench/woof_bench --target javascript # JavaScript target
```

## Results

Measured on a development machine (Erlang/OTP 28, Node.js 25), 100,000
events per row. Absolute numbers vary by machine - what matters is the
relative cost between rows and whether it changes release to release.

### Erlang target

| Wrapper | Total | Per event |
| :--- | ---: | ---: |
| direct sink (no wrapper) | 571ms | ~5us |
| `redact_event_sink` | 558ms | ~5us |
| `sample_event_sink(1.0)` | 565ms | ~5us |
| `consistent_sample_event_sink(1.0)` | 543ms | ~5us |
| `rate_limit_event_sink(1_000_000/s)` | 554ms | ~5us |
| `batch_event_sink(100, 60_000ms)` | 1114ms | ~11us |

### JavaScript target (Node.js)

| Wrapper | Total | Per event |
| :--- | ---: | ---: |
| direct sink (no wrapper) | 409ms | ~4us |
| `redact_event_sink` | 358ms | ~3us |
| `sample_event_sink(1.0)` | 366ms | ~3us |
| `consistent_sample_event_sink(1.0)` | 438ms | ~4us |
| `rate_limit_event_sink(1_000_000/s)` | 378ms | ~3us |
| `batch_event_sink(100, 60_000ms)` | 394ms | ~3us |

## Reading these numbers

- `redact_event_sink`, `sample_event_sink`, `consistent_sample_event_sink`,
  and `rate_limit_event_sink` all sit within noise of the direct sink - the
  extra work per event (a list scan, a hash, a float comparison) is small
  next to everything else `woof.info` already does (context merge,
  formatting, field serialisation).
- `batch_event_sink` costs more on the Erlang target because every call
  allocates a fresh ETS-backed `Box` read/write for the buffer instead of a
  handful of arithmetic ops - still a small multiple, not an order of
  magnitude, and the cost buys fewer downstream deliveries in exchange.
- These numbers measure wrapper overhead in isolation, not a realistic
  pipeline. Composing several wrappers (see
  [production_setup.md](production_setup.md)) adds their costs roughly
  linearly - none of them do enough work to interact with each other.
