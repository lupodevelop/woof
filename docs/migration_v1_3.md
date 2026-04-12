# Migrating to woof v1.3

v1.3 introduces typed fields. The change is a single breaking one:
the field list type changed from `List(#(String, String))` to `List(#(String, FieldValue))`.

The compiler will point you to every call site. The fix is always the same pattern.

---

## The one breaking change

**Before (v1.2)**

```gleam
woof.info("Server started", [#("port", "3000")])
```

**After (v1.3)**

```gleam
woof.info("Server started", [woof.str("port", "3000")])
```

Raw `#(String, String)` tuples no longer type-check as field lists.
Use a constructor: `woof.str`, `woof.int`, `woof.float`, or `woof.bool`.

---

## Field helpers — call sites unchanged

If you were already using the field helpers, **call sites do not change**.
Only the return type changed (from `#(String, String)` to `#(String, FieldValue)`).

```gleam
// v1.2 — worked, still works
woof.info("Order processed", [
  woof.field("order_id", "ORD-42"),
  woof.int_field("amount", 4999),
  woof.float_field("tax", 8.5),
  woof.bool_field("express", True),
])
```

No change needed. These helpers are deprecated in favour of the shorter names,
but they are not removed and will not cause compile errors.

---

## Prefer the new names

The old helpers are aliases. Prefer the new constructors for new code:

| Old (kept, deprecated) | New (preferred) |
| :--- | :--- |
| `woof.field("k", v)` | `woof.str("k", v)` |
| `woof.int_field("k", n)` | `woof.int("k", n)` |
| `woof.float_field("k", f)` | `woof.float("k", f)` |
| `woof.bool_field("k", b)` | `woof.bool("k", b)` |

---

## Context and global context

Same pattern — swap raw tuples for constructors.

**Before**

```gleam
woof.set_global_context([#("app", "my-service"), #("env", "production")])
woof.with_context([#("request_id", req.id)], fn() { ... })
```

**After**

```gleam
woof.set_global_context([woof.str("app", "my-service"), woof.str("env", "production")])
woof.with_context([woof.str("request_id", req.id)], fn() { ... })
```

`get_global_context()` now returns `List(#(String, FieldValue))`. If you store or
compare its result, update the type annotation and any comparisons accordingly:

```gleam
// Before
let ctx: List(#(String, String)) = woof.get_global_context()

// After
let ctx: List(#(String, FieldValue)) = woof.get_global_context()
```

---

## Custom formatters — unchanged

If you have a `Custom` formatter, it receives an `Entry` with `fields: List(#(String, String))`.
**Nothing changes here.** `FieldValue` is converted to string before `Entry` is built.

```gleam
// Still works exactly as before
let my_format = fn(entry: woof.Entry) -> String {
  list.map(entry.fields, fn(f) { f.0 <> "=" <> f.1 })
  |> string.join(" ")
}
woof.set_format(woof.Custom(my_format))
```

---

## Custom legacy sinks — unchanged

`Sink = fn(Entry, String) -> Nil` — unchanged.
`Entry.fields` stays `List(#(String, String))`.

```gleam
// Still works exactly as before
woof.set_sink(fn(entry, formatted) {
  send_to_datadog(entry.level, entry.message, entry.fields)
})
```

---

## Bool rendering changed

`FBool(True)` now serialises to `"true"` (lowercase) in the legacy string path.
Previously `bool_field("k", True)` produced `"True"` (capital T).

If you have test assertions or log parsers that check for `"True"` or `"False"`,
update them to `"true"` / `"false"`.

---

## Testing — use test_sink instead of custom sinks

The old pattern (capturing via a custom sink + subject/channel):

```gleam
// Old — v1.2
let subject = process.new_subject()
woof.set_sink(fn(entry, _) { process.send(subject, entry) })
woof.info("something happened", [])
let assert Ok(entry) = process.receive(subject, 0)
entry.message |> should.equal("something happened")
```

The new pattern (typed capture):

```gleam
// New — v1.3
let #(sink, get) = woof.test_sink()
woof.set_sink(woof.silent_sink)
woof.set_event_sink(sink)

woof.info("something happened", [woof.int("code", 42)])

let assert [event] = get()
event.message |> should.equal("something happened")
event.fields  |> should.equal([#("code", woof.FInt(42))])
```

The old approach still works — `Entry` and `Sink` are unchanged.
`test_sink` is strictly better for new tests: no channels, no process boilerplate,
typed fields you can actually assert on.