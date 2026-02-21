import gleam/io
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import woof

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Helpers — reset state between tests
// ---------------------------------------------------------------------------

fn reset() {
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Never,
  ))
  woof.set_global_context([])
}

// ---------------------------------------------------------------------------
// Text format
// ---------------------------------------------------------------------------

pub fn text_simple_message_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Server started",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Text)
  |> should.equal("[INFO] 10:30:45 Server started")
}

pub fn text_with_fields_test() {
  let entry =
    woof.Entry(
      level: woof.Warning,
      message: "High memory",
      fields: [#("usage_mb", "1024"), #("threshold", "800")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Text)
  |> should.equal(
    "[WARN] 10:30:45 High memory\n  usage_mb: 1024\n  threshold: 800",
  )
}

pub fn text_with_namespace_test() {
  let entry =
    woof.Entry(
      level: woof.Debug,
      message: "Query executed",
      fields: [#("ms", "45")],
      namespace: Some("database"),
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Text)
  |> should.equal("[DEBUG] 10:30:45 database: Query executed\n  ms: 45")
}

pub fn text_all_levels_test() {
  let make = fn(level) {
    woof.Entry(
      level: level,
      message: "x",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T00:00:00.000Z",
    )
  }

  woof.format(make(woof.Debug), woof.Text)
  |> string.starts_with("[DEBUG]")
  |> should.be_true

  woof.format(make(woof.Info), woof.Text)
  |> string.starts_with("[INFO]")
  |> should.be_true

  woof.format(make(woof.Warning), woof.Text)
  |> string.starts_with("[WARN]")
  |> should.be_true

  woof.format(make(woof.Error), woof.Text)
  |> string.starts_with("[ERROR]")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// JSON format
// ---------------------------------------------------------------------------

pub fn json_simple_message_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Hello",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Json)
  |> should.equal(
    "{\"level\":\"info\",\"time\":\"2026-02-11T10:30:45.123Z\",\"msg\":\"Hello\"}",
  )
}

pub fn json_with_fields_test() {
  let entry =
    woof.Entry(
      level: woof.Error,
      message: "Failed",
      fields: [#("code", "500"), #("reason", "timeout")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Json)
  |> should.equal(
    "{\"level\":\"error\",\"time\":\"2026-02-11T10:30:45.123Z\",\"msg\":\"Failed\",\"code\":\"500\",\"reason\":\"timeout\"}",
  )
}

pub fn json_with_namespace_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Connected",
      fields: [],
      namespace: Some("db"),
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Json)
  |> should.equal(
    "{\"level\":\"info\",\"time\":\"2026-02-11T10:30:45.123Z\",\"ns\":\"db\",\"msg\":\"Connected\"}",
  )
}

pub fn json_escapes_special_chars_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Line1\nLine2",
      fields: [#("data", "has \"quotes\"")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  let output = woof.format(entry, woof.Json)
  // Message newline should be escaped
  output |> string.contains("Line1\\nLine2") |> should.be_true
  // Quotes in field values should be escaped
  output |> string.contains("has \\\"quotes\\\"") |> should.be_true
}

// ---------------------------------------------------------------------------
// Custom format
// ---------------------------------------------------------------------------

pub fn custom_formatter_test() {
  let formatter = fn(entry: woof.Entry) -> String {
    "CUSTOM[" <> woof.level_name(entry.level) <> "] " <> entry.message
  }

  let entry =
    woof.Entry(
      level: woof.Warning,
      message: "watch out",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Custom(formatter))
  |> should.equal("CUSTOM[warning] watch out")
}

// ---------------------------------------------------------------------------
// level_name
// ---------------------------------------------------------------------------

pub fn level_name_test() {
  woof.level_name(woof.Debug) |> should.equal("debug")
  woof.level_name(woof.Info) |> should.equal("info")
  woof.level_name(woof.Warning) |> should.equal("warning")
  woof.level_name(woof.Error) |> should.equal("error")
}

// ---------------------------------------------------------------------------
// Level filtering
// ---------------------------------------------------------------------------

pub fn level_filtering_drops_below_minimum_test() {
  reset()

  // Use a custom formatter that records calls via assertion.
  // If debug or info were emitted, the formatter would run and we'd see it.
  // We set level to Warning, so only warning + error should fire.
  let call_count = fn(entry: woof.Entry) -> String {
    // This should only be called for warning and error.
    case entry.level {
      woof.Warning | woof.Error -> ""
      _ -> {
        // If we get here, a below-level message leaked through.
        panic as "Unexpected log emission below minimum level"
      }
    }
  }

  woof.configure(woof.Config(
    level: woof.Warning,
    format: woof.Custom(call_count),
    colors: woof.Never,
  ))
  woof.debug("should not appear", [])
  woof.info("should not appear", [])
  woof.warning("should appear", [])
  woof.error("should appear", [])

  reset()
}

// ---------------------------------------------------------------------------
// Namespace
// ---------------------------------------------------------------------------

pub fn namespace_included_in_entry_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.namespace |> should.equal(Some("http"))
      entry.message |> should.equal("Request received")
      ""
    }),
    colors: woof.Never,
  ))

  let log = woof.new("http")
  log |> woof.log(woof.Info, "Request received", [])

  reset()
}

pub fn no_namespace_for_plain_calls_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.namespace |> should.equal(None)
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("plain message", [])

  reset()
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

pub fn with_context_adds_fields_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("request_id", "abc"), #("inline", "123")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.with_context([#("request_id", "abc")], fn() {
    woof.info("test", [#("inline", "123")])
  })

  reset()
}

pub fn nested_context_accumulates_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("outer", "1"), #("inner", "2"), #("field", "3")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.with_context([#("outer", "1")], fn() {
    woof.with_context([#("inner", "2")], fn() {
      woof.info("nested", [#("field", "3")])
    })
  })

  reset()
}

pub fn context_restored_after_callback_test() {
  reset()

  // First: log inside with_context — should have the ctx field.
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      case entry.message {
        "inside" -> entry.fields |> should.equal([#("temp", "value")])
        "outside" -> entry.fields |> should.equal([])
        _ -> Nil
      }
      ""
    }),
    colors: woof.Never,
  ))

  woof.with_context([#("temp", "value")], fn() { woof.info("inside", []) })

  // After the callback returns, context should be empty again.
  woof.info("outside", [])

  reset()
}

// ---------------------------------------------------------------------------
// Global context
// ---------------------------------------------------------------------------

pub fn global_context_included_in_every_message_test() {
  reset()

  woof.set_global_context([#("app", "test-suite")])

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("app", "test-suite"), #("key", "val")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("msg", [#("key", "val")])

  reset()
}

pub fn global_and_scoped_context_merge_test() {
  reset()

  woof.set_global_context([#("app", "svc")])

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("app", "svc"), #("req", "1"), #("inline", "x")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.with_context([#("req", "1")], fn() {
    woof.info("merged", [#("inline", "x")])
  })

  reset()
}

// ---------------------------------------------------------------------------
// Compact format
// ---------------------------------------------------------------------------

pub fn compact_simple_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Server started",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Compact)
  |> should.equal("INFO 2026-02-11T10:30:45.123Z Server started")
}

pub fn compact_with_fields_test() {
  let entry =
    woof.Entry(
      level: woof.Warning,
      message: "High memory",
      fields: [#("usage_mb", "1024"), #("threshold", "800")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Compact)
  |> should.equal(
    "WARN 2026-02-11T10:30:45.123Z High memory usage_mb=1024 threshold=800",
  )
}

pub fn compact_with_namespace_test() {
  let entry =
    woof.Entry(
      level: woof.Debug,
      message: "Query done",
      fields: [#("ms", "12")],
      namespace: Some("db"),
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Compact)
  |> should.equal("DEBUG 2026-02-11T10:30:45.123Z ns=db Query done ms=12")
}

// ---------------------------------------------------------------------------
// Lazy evaluation
// ---------------------------------------------------------------------------

pub fn lazy_skips_evaluation_when_level_disabled_test() {
  reset()
  woof.set_level(woof.Error)

  // If the thunk ran, it would panic — proving that lazy skips evaluation.
  woof.debug_lazy(fn() { panic as "debug_lazy thunk should not run" }, [])
  woof.info_lazy(fn() { panic as "info_lazy thunk should not run" }, [])
  woof.warning_lazy(fn() { panic as "warning_lazy thunk should not run" }, [])

  reset()
}

pub fn lazy_evaluates_when_level_enabled_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.message |> should.equal("computed")
      ""
    }),
    colors: woof.Never,
  ))

  woof.debug_lazy(fn() { "computed" }, [])

  reset()
}

// ---------------------------------------------------------------------------
// tap helpers
// ---------------------------------------------------------------------------

pub fn tap_info_passes_value_through_test() {
  reset()

  // Use Custom to swallow output so we don't pollute test stdout.
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(_) { "" }),
    colors: woof.Never,
  ))

  let result =
    42
    |> woof.tap_info("got value", [])

  result |> should.equal(42)

  reset()
}

pub fn tap_debug_passes_value_through_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(_) { "" }),
    colors: woof.Never,
  ))

  let result =
    "hello"
    |> woof.tap_debug("got value", [])

  result |> should.equal("hello")

  reset()
}

// ---------------------------------------------------------------------------
// log_error helper
// ---------------------------------------------------------------------------

pub fn log_error_passes_ok_through_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(_) { panic as "log_error should not emit for Ok" }),
    colors: woof.Never,
  ))

  let res: Result(Int, String) = Ok(42)
  res
  |> woof.log_error("should not fire", [])
  |> should.equal(Ok(42))

  reset()
}

pub fn log_error_logs_and_passes_error_through_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.level |> should.equal(woof.Error)
      entry.message |> should.equal("fetch failed")
      ""
    }),
    colors: woof.Never,
  ))

  let res: Result(Int, String) = Error("timeout")
  res
  |> woof.log_error("fetch failed", [])
  |> should.equal(Error("timeout"))

  reset()
}

// ---------------------------------------------------------------------------
// time helper
// ---------------------------------------------------------------------------

pub fn time_returns_body_result_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      // Should contain the label and a duration_ms field.
      entry.message
      |> string.starts_with("work completed")
      |> should.be_true
      entry.fields
      |> should.not_equal([])
      ""
    }),
    colors: woof.Never,
  ))

  let result = woof.time("work", fn() { 1 + 1 })
  result |> should.equal(2)

  reset()
}

// ---------------------------------------------------------------------------
// Field helpers
// ---------------------------------------------------------------------------

pub fn field_helper_string_test() {
  woof.field("key", "value")
  |> should.equal(#("key", "value"))
}

pub fn field_helper_int_test() {
  woof.int_field("status", 200)
  |> should.equal(#("status", "200"))
}

pub fn field_helper_float_test() {
  woof.float_field("duration", 12.5)
  |> should.equal(#("duration", "12.5"))
}

pub fn field_helper_bool_test() {
  woof.bool_field("cached", True)
  |> should.equal(#("cached", "True"))

  woof.bool_field("cached", False)
  |> should.equal(#("cached", "False"))
}

pub fn field_helpers_in_log_call_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([
        #("path", "/api"),
        #("status", "200"),
        #("ms", "12.5"),
        #("cached", "True"),
      ])
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("Request", [
    woof.field("path", "/api"),
    woof.int_field("status", 200),
    woof.float_field("ms", 12.5),
    woof.bool_field("cached", True),
  ])

  reset()
}

// ---------------------------------------------------------------------------
// Visual demo — prints real output to the terminal
// ---------------------------------------------------------------------------

pub fn visual_demo_test() {
  // This test prints real log output so you can see what woof looks like.
  // It's a normal test — it always passes — but the side effect is visible
  // in the terminal when you run `gleam test`.

  let separator = fn(title: String) {
    io.println("")
    io.println("━━━ " <> title <> " ━━━")
    io.println("")
  }

  // ── Text format with colors ──────────────────────────────────────────
  separator("Text format with ANSI colors")

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Always,
  ))

  woof.debug("Cache lookup", [#("key", "user:42")])
  woof.info("Server started", [
    woof.field("host", "0.0.0.0"),
    woof.int_field("port", 3000),
  ])
  woof.warning("Rate limit approaching", [
    woof.field("endpoint", "/api/search"),
    woof.int_field("current", 89),
    woof.int_field("limit", 100),
  ])
  woof.error("Connection lost", [
    woof.field("host", "db-primary"),
    woof.float_field("retry_in_s", 2.5),
  ])

  // ── Text format without colors ───────────────────────────────────────
  separator("Text format (no colors)")

  woof.set_colors(woof.Never)

  woof.info("Plain text output", [#("format", "text")])
  woof.error("Something went wrong", [#("code", "ERR_TIMEOUT")])

  // ── JSON format ──────────────────────────────────────────────────────
  separator("JSON format")

  woof.set_format(woof.Json)

  woof.info("User signed in", [
    woof.field("user_id", "u_abc123"),
    woof.field("method", "oauth"),
  ])
  woof.error("Payment failed", [
    woof.field("order_id", "ORD-42"),
    woof.int_field("amount", 4999),
  ])

  // ── Compact format ───────────────────────────────────────────────────
  separator("Compact format")

  woof.set_format(woof.Compact)

  woof.info("Request handled", [
    woof.field("method", "GET"),
    woof.field("path", "/api/users"),
    woof.int_field("status", 200),
    woof.float_field("ms", 12.4),
  ])
  woof.warning("Slow query", [
    woof.field("table", "orders"),
    woof.int_field("ms", 3200),
  ])

  // ── Namespaced logger ────────────────────────────────────────────────
  separator("Namespaced logger (Text + colors)")

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Always,
  ))

  let db = woof.new("database")
  let http = woof.new("http")

  db |> woof.log(woof.Info, "Connected", [#("host", "localhost")])
  db |> woof.log(woof.Debug, "Query executed", [woof.int_field("ms", 45)])
  http |> woof.log(woof.Info, "Listening", [woof.int_field("port", 8080)])
  http
  |> woof.log(woof.Warning, "Slow response", [woof.int_field("ms", 1200)])

  // ── Context ──────────────────────────────────────────────────────────
  separator("Scoped + global context")

  woof.set_global_context([woof.field("app", "woof-demo")])

  woof.with_context([woof.field("request_id", "req-7f3a")], fn() {
    woof.info("Processing payment", [woof.int_field("amount", 42)])
    woof.with_context([woof.field("step", "validation")], fn() {
      woof.debug("Validating card", [woof.field("type", "visa")])
    })
  })

  woof.set_global_context([])

  // ── Custom formatter ─────────────────────────────────────────────────
  separator("Custom formatter")

  let emoji_format = fn(entry: woof.Entry) -> String {
    let icon = case entry.level {
      woof.Debug -> "🔍"
      woof.Info -> "✅"
      woof.Warning -> "⚠️"
      woof.Error -> "❌"
    }
    icon <> " " <> entry.message
  }

  woof.set_format(woof.Custom(emoji_format))

  woof.debug("Looking around...", [])
  woof.info("All good", [])
  woof.warning("Heads up", [])
  woof.error("Oops", [])

  io.println("")
  io.println("━━━ End of visual demo ━━━")
  io.println("")

  // Clean up
  reset()
}
