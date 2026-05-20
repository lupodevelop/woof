# Semantic Conventions

Structured logs are only as useful as the field names are consistent. If one
service writes `user_id` and another writes `userId` and a third writes `uid`,
no query spans all three. This page lists the field names woof recommends so a
whole codebase, and ideally a whole organisation, stays queryable.

The names follow the [OpenTelemetry semantic
conventions](https://opentelemetry.io/docs/specs/semconv/). woof does not
enforce them. They are a convention, not a constraint. Use `woof.str`,
`woof.int`, and the other typed constructors with these keys.

## Resource attributes

Resource attributes describe the service itself, not any single event. Set
them once at startup with `woof.set_resource`. The `OtlpJson` format emits
them under a `resource` object.

| Key | Meaning | Example |
| :-- | :------ | :------ |
| `service.name` | Logical name of the service | `"checkout"` |
| `service.version` | Running version | `"1.8.0"` |
| `service.instance.id` | Unique instance, pod, or host id | `"pod-7f3a"` |
| `deployment.environment` | Deployment stage | `"production"` |

```gleam
woof.set_resource([
  woof.str("service.name", "checkout"),
  woof.str("service.version", "1.8.0"),
  woof.str("deployment.environment", "production"),
])
```

## Event attributes

Event attributes describe one log event. Pass them as inline fields, or attach
them with `set_context` / `with_context`.

### HTTP

| Key | Type | Example |
| :-- | :--- | :------ |
| `http.request.method` | string | `"POST"` |
| `http.response.status_code` | int | `200` |
| `http.route` | string | `"/users/:id"` |
| `url.path` | string | `"/users/42"` |
| `url.full` | string | `"https://api.example.com/users/42"` |

### Errors

| Key | Type | Example |
| :-- | :--- | :------ |
| `error.type` | string | `"timeout"` |
| `error.message` | string | `"connection reset by peer"` |
| `error.stack` | string | a captured stack trace |

### User

| Key | Type | Example |
| :-- | :--- | :------ |
| `user.id` | string or int | `"u_8812"` |
| `user.email` | string | `"a@example.com"` |

Treat `user.email` as personal data. Redaction helpers arrive in v1.9; until
then, avoid logging it where it is not needed.

### Database

| Key | Type | Example |
| :-- | :--- | :------ |
| `db.system` | string | `"postgresql"` |
| `db.operation` | string | `"SELECT"` |
| `db.statement` | string | `"SELECT * FROM users WHERE id = $1"` |

## Trace correlation

`trace_id` and `span_id` tie a log line to a distributed trace. woof writes
both when you use `with_trace` or `set_trace`, so you rarely set them by hand.

| Key | Type | Meaning |
| :-- | :--- | :------ |
| `trace_id` | string | Identifies the whole trace |
| `span_id` | string | Identifies the span the log belongs to |

```gleam
woof.with_trace(trace_id, span_id, fn() {
  woof.info("payment captured", [woof.int("amount_cents", 4200)])
})
```

In `OtlpJson` output these two fields are promoted to top-level keys instead
of being left inside `attributes`.

## A worked example

```gleam
woof.set_resource([
  woof.str("service.name", "checkout"),
  woof.str("service.version", "1.8.0"),
])

woof.with_trace(trace_id, span_id, fn() {
  woof.info("order placed", [
    woof.str("http.request.method", "POST"),
    woof.int("http.response.status_code", 201),
    woof.str("user.id", "u_8812"),
    woof.int("order.total_cents", 9900),
  ])
})
```

## Related documents

* [guide.md](guide.md): full library reference
* [log_levels.md](log_levels.md): choosing the right log level
