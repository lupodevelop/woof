# Choosing the Right Log Level

woof has eight levels, the same scale as the OTP logger and syslog. More
levels are only useful if each one has a clear job. This page gives each level
a job: when to use it, how much of it to expect, and where it should land.

## The eight levels

| Level | Use it for | Volume | Where it should land |
| :---- | :--------- | :----- | :------------------- |
| `Debug` | Developer traces, variable dumps | High, bursty | Local stdout, off in production |
| `Info` | Normal application flow | Steady | Centralised log store |
| `Notice` | Significant events that are not problems | Low | Centralised log store |
| `Warning` | Recoverable anomalies | Low | Centralised log store, dashboards |
| `Error` | A request or job failed | Low | Centralised log store, error tracker |
| `Critical` | A subsystem is degraded | Rare | Error tracker, on-call dashboard |
| `Alert` | A human must act now | Very rare | Pager |
| `Emergency` | The system is unusable | Almost never | Pager, incident channel |

## How to decide

Ask two questions in order.

**1. Did something fail?**

If nothing failed, the event is `Debug`, `Info`, or `Notice`.

* `Debug` is for you, while developing. It can be noisy. It is silenced in
  production by setting the level to `Info` or higher.
* `Info` is the running record of normal behaviour: a request served, a job
  finished, a cache warmed.
* `Notice` is for events that are normal but worth finding later: a config
  reload, a successful deploy, a scheduled task that completed.

**2. Does a human need to act, and how fast?**

If something failed, the level depends on urgency, not on how bad it feels.

* `Warning`: the system handled it. A retry succeeded, a fallback was used, a
  deprecated path was hit. Worth watching as a trend, not worth waking anyone.
* `Error`: one unit of work failed and will not be retried. A request returned
  500, a job was dropped. The user is affected, the system is not.
* `Critical`: a whole subsystem is degraded. The database pool is exhausted,
  a dependency is down. Many requests are failing.
* `Alert`: automated recovery is not enough and a human must act now.
* `Emergency`: the service is doing nothing useful at all.

## Volume is a signal

If a level appears far more often than the table suggests, the level is
probably wrong.

* Thousands of `Error` lines a minute usually means one `Critical` condition.
  Log the condition once at `Critical`, not the symptom thousands of times at
  `Error`.
* A steady stream of `Warning` that nobody reads is noise. Either it is
  actually `Info`, or the underlying problem should be fixed.

## Setting the level

The default level is `Debug`, which prints everything. In production, raise it:

```gleam
// Explicit:
woof.set_level(woof.Info)

// From the environment, so deploys can change it without a rebuild:
let _ = woof.set_level_from_env("LOG_LEVEL")
```

`woof.prod()` sets the level to `Info` as part of its preset.

## Related documents

* [guide.md](guide.md): full library reference
* [semantic_conventions.md](semantic_conventions.md): standard field names
