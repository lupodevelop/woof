import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import woof

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn sep(title: String) -> Nil {
  io.println("")
  io.println(
    "━━━ " <> title <> " " <> string.repeat("━", 60 - string.length(title)),
  )
}

fn note(text: String) -> Nil {
  io.println("  # " <> text)
}

/// Reset woof to pristine defaults between sections.
fn reset() -> Nil {
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Auto,
  ))
  woof.set_global_context([])
  woof.clear_event_sink()
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub fn main() -> Nil {
  io.println("")
  io.println("╔══════════════════════════════════════════════════════╗")
  io.println("║          w o o f   —   dev demo (v1.3.0)             ║")
  io.println("╚══════════════════════════════════════════════════════╝")

  demo_basic_levels()
  demo_field_helpers()
  demo_level_filtering()
  demo_format_text()
  demo_format_compact()
  demo_format_json()
  demo_format_custom()
  demo_configure()
  demo_colors()
  demo_namespaced_logger()
  demo_lazy_logging()
  demo_global_context()
  demo_scoped_context()
  demo_pipeline_tap()
  demo_log_error()
  demo_time()
  demo_format_utility()
  demo_level_name()
  demo_sinks()
  demo_test_sink()

  io.println("")
  io.println("═══════════════════════════════════════════════════════")
  io.println("  Done.")
  io.println("═══════════════════════════════════════════════════════")
  io.println("")
}

// ---------------------------------------------------------------------------
// 1. Basic levels
// ---------------------------------------------------------------------------

fn demo_basic_levels() -> Nil {
  reset()
  sep("1 · Basic levels")
  note("debug / info / warning / error → Text format, colors Auto")

  woof.debug("Cache lookup", [woof.str("key", "user:42")])
  woof.info("Server started", [
    woof.str("host", "0.0.0.0"),
    woof.int("port", 3000),
  ])
  woof.warning("Rate limit approaching", [
    woof.str("endpoint", "/api/search"),
    woof.int("current", 89),
    woof.int("limit", 100),
  ])
  woof.error("Connection lost", [
    woof.str("host", "db-primary"),
    woof.float("retry_in_s", 2.5),
  ])
}

// ---------------------------------------------------------------------------
// 2. Field helpers
// ---------------------------------------------------------------------------

fn demo_field_helpers() -> Nil {
  reset()
  sep("2 · Field helpers")
  note("str / int / float / bool — typed constructors (v1.3)")

  woof.info("Order processed", [
    woof.str("order_id", "ORD-9912"),
    woof.int("amount_cents", 4999),
    woof.float("tax_rate", 22.0),
    woof.bool("express", True),
  ])

  note("Legacy helpers (field/int_field/float_field/bool_field) still work")
  woof.info("Legacy helpers", [
    woof.field("order_id", "ORD-9912"),
    woof.int_field("amount_cents", 4999),
    woof.float_field("tax_rate", 22.0),
    woof.bool_field("express", True),
  ])
}

// ---------------------------------------------------------------------------
// 3. Level filtering (set_level)
// ---------------------------------------------------------------------------

fn demo_level_filtering() -> Nil {
  reset()
  sep("3 · Level filtering — set_level")

  note("set_level(Warning) → debug and info are silently dropped")
  woof.set_level(woof.Warning)
  woof.debug("not printed", [])
  woof.info("not printed either", [])
  woof.warning("this IS printed", [woof.str("reason", "at or above Warning")])
  woof.error("this IS printed too", [])

  note("restore Debug (default) for subsequent sections")
  woof.set_level(woof.Debug)
}

// ---------------------------------------------------------------------------
// 4. Format — Text
// ---------------------------------------------------------------------------

fn demo_format_text() -> Nil {
  reset()
  sep("4 · Format — Text (default)")
  note("Human-readable multi-line output.")

  woof.set_format(woof.Text)
  woof.info("User signed in", [
    woof.str("user_id", "u_7f3a"),
    woof.str("method", "oauth"),
  ])
  woof.error("Disk almost full", [
    woof.int("used_gb", 490),
    woof.int("total_gb", 512),
  ])
}

// ---------------------------------------------------------------------------
// 5. Format — Compact
// ---------------------------------------------------------------------------

fn demo_format_compact() -> Nil {
  reset()
  sep("5 · Format — Compact")
  note("Single-line key=value pairs. Values with spaces are quoted.")

  woof.set_format(woof.Compact)
  woof.info("Request handled", [
    woof.str("method", "GET"),
    woof.str("path", "/api/users"),
    woof.int("status", 200),
    woof.float("ms", 12.4),
  ])
  woof.warning("Slow query detected", [
    woof.str("table", "orders"),
    woof.int("ms", 3200),
  ])

  note("Values containing spaces get quoted automatically")
  woof.info("User logged in", [
    woof.str("name", "John Doe"),
    woof.str("role", "admin user"),
  ])

  note("Empty values get quoted too")
  woof.debug("Probe", [woof.str("optional_tag", "")])
}

// ---------------------------------------------------------------------------
// 6. Format — JSON
// ---------------------------------------------------------------------------

fn demo_format_json() -> Nil {
  reset()
  sep("6 · Format — JSON")
  note("One JSON object per line — ideal for log aggregators.")

  woof.set_format(woof.Json)
  woof.info("Payment processed", [
    woof.str("order_id", "ORD-42"),
    woof.int("amount", 4999),
    woof.bool("express", False),
  ])
  woof.error("Payment failed", [
    woof.str("order_id", "ORD-99"),
    woof.str("reason", "Insufficient funds"),
  ])

  note("Reserved keys (level/time/ns/msg) are prefixed '_' to avoid collision")
  woof.info("Collision-safe", [
    woof.str("msg", "user override"),
    woof.str("level", "custom"),
  ])
}

// ---------------------------------------------------------------------------
// 7. Format — Custom
// ---------------------------------------------------------------------------

fn demo_format_custom() -> Nil {
  reset()
  sep("7 · Format — Custom formatter")
  note("fn(Entry) -> String — the lowest-level escape hatch.")

  woof.set_format(
    woof.Custom(fn(entry) {
      let icon = case entry.level {
        woof.Debug -> "🔍"
        woof.Info -> "✅"
        woof.Warning -> "⚠️ "
        woof.Error -> "❌"
      }
      let fields_str =
        list.map(entry.fields, fn(f) { " [" <> f.0 <> "=" <> f.1 <> "]" })
        |> string.join("")
      icon
      <> " ["
      <> woof.level_name(entry.level)
      <> "] "
      <> entry.message
      <> fields_str
    }),
  )

  woof.debug("Inspecting value", [woof.int("x", 42)])
  woof.info("All systems operational", [])
  woof.warning("Response time elevated", [woof.int("p99_ms", 850)])
  woof.error("Database unreachable", [woof.str("host", "pg-primary")])
}

// ---------------------------------------------------------------------------
// 8. configure — set level + format + colors in one call
// ---------------------------------------------------------------------------

fn demo_configure() -> Nil {
  reset()
  sep("8 · configure — set level + format + colors at once")
  note("woof.Config{} sets all three fields atomically")

  woof.configure(woof.Config(
    level: woof.Info,
    format: woof.Compact,
    colors: woof.Never,
  ))
  woof.debug("dropped — below Info", [])
  woof.info("Compact, no-color, Info+", [woof.str("via", "configure")])
  woof.warning("Compact warning too", [])
}

// ---------------------------------------------------------------------------
// 9. Color control — set_colors
// ---------------------------------------------------------------------------

fn demo_colors() -> Nil {
  reset()
  sep("9 · Color control — set_colors")

  woof.set_format(woof.Text)

  note("Always → forces ANSI codes even when piped")
  woof.set_colors(woof.Always)
  woof.info("Forced ANSI colors", [])
  woof.error("Red label regardless of TTY", [])

  note("Never → strips all ANSI codes")
  woof.set_colors(woof.Never)
  woof.info("No colors, clean for CI logs", [])
  woof.warning("Also plain", [])

  note(
    "Auto (default) → colors only when stdout is a TTY and NO_COLOR is unset",
  )
  woof.set_colors(woof.Auto)
  woof.info("Auto color detection", [woof.str("check", "is_tty()")])
}

// ---------------------------------------------------------------------------
// 10. Namespaced loggers — new / log
// ---------------------------------------------------------------------------

fn demo_namespaced_logger() -> Nil {
  reset()
  sep("10 · Namespaced loggers — new / log")
  note("woof.new(\"namespace\") returns an opaque Logger; use woof.log to emit")

  let db = woof.new("database")
  let http = woof.new("http")
  let auth = woof.new("auth")

  db |> woof.log(woof.Info, "Connected", [woof.str("host", "pg-primary")])
  db |> woof.log(woof.Debug, "Query executed", [woof.int("ms", 45)])

  http |> woof.log(woof.Info, "Listening", [woof.int("port", 8080)])
  http |> woof.log(woof.Warning, "Slow response", [woof.int("ms", 1200)])

  auth |> woof.log(woof.Info, "Token validated", [woof.str("alg", "RS256")])
  auth |> woof.log(woof.Error, "Token expired", [woof.str("user_id", "u_99")])
}

// ---------------------------------------------------------------------------
// 11. Lazy evaluation — *_lazy variants
// ---------------------------------------------------------------------------

fn demo_lazy_logging() -> Nil {
  reset()
  sep("11 · Lazy evaluation — *_lazy")
  note("The message builder fn() is only called if the level is enabled")

  note("With set_level(Info), debug_lazy builder is NEVER executed")
  woof.set_level(woof.Info)
  woof.debug_lazy(fn() { "this fn is never called" }, [])

  note("info_lazy, warning_lazy, error_lazy DO execute since Info is enabled")
  woof.info_lazy(fn() { "Lazy info: " <> "computed only now" }, [
    woof.str("src", "info_lazy"),
  ])
  woof.warning_lazy(fn() { "Lazy warning" }, [woof.str("src", "warning_lazy")])
  woof.error_lazy(fn() { "Lazy error" }, [woof.str("src", "error_lazy")])

  woof.set_level(woof.Debug)
}

// ---------------------------------------------------------------------------
// 12. Global context — set_global_context
// ---------------------------------------------------------------------------

fn demo_global_context() -> Nil {
  reset()
  sep("12 · Global context — set_global_context")
  note("Fields set here appear on EVERY subsequent log message")

  woof.set_global_context([
    woof.str("app", "woof-demo"),
    woof.str("version", "1.3.0"),
    woof.str("environment", "dev"),
  ])

  woof.info("Application boot complete", [])
  woof.debug("Running health checks", [woof.str("check", "db")])
  woof.warning("Config file not found, using defaults", [])

  note("Overwrite global context")
  woof.set_global_context([
    woof.str("app", "woof-demo"),
    woof.str("region", "eu-west-1"),
  ])
  woof.info("Context replaced", [])

  note("Clear global context for next sections")
  woof.set_global_context([])
}

// ---------------------------------------------------------------------------
// 13. Scoped context — with_context
// ---------------------------------------------------------------------------

fn demo_scoped_context() -> Nil {
  reset()
  sep("13 · Scoped context — with_context")
  note("Fields scoped to the callback; previous context is restored after")

  woof.set_global_context([woof.str("app", "woof-demo")])

  use <- woof.with_context([woof.str("request_id", "req-7f3a")])
  woof.info("Handling request", [])

  use <- woof.with_context([woof.str("step", "validation")])
  woof.debug("Validating payload", [woof.str("schema", "order_v2")])

  woof.info("Validation passed", [])
  woof.info("Sending response", [woof.int("status", 200)])

  note("Outside both contexts — only global 'app' field remains")
  woof.set_global_context([])
}

// ---------------------------------------------------------------------------
// 14. Pipeline helpers — tap_debug / tap_info / tap_warning / tap_error
// ---------------------------------------------------------------------------

fn demo_pipeline_tap() -> Nil {
  reset()
  sep("14 · Pipeline helpers — tap_*")
  note("tap_* logs and passes the value through unchanged (pipeline-friendly)")

  let ids = [1, 2, 3, 4, 5]

  let _processed =
    ids
    |> woof.tap_debug("Processing ID list", [woof.int("count", 5)])
    |> list.filter(fn(x) { x > 2 })
    |> woof.tap_info("After filter", [woof.int("remaining", 3)])
    |> list.map(fn(x) { x * 10 })
    |> woof.tap_warning("Values amplified", [woof.str("note", "×10")])

  let ok_r: Result(Int, String) = Ok(42)
  let _ = ok_r |> woof.tap_error("This won't print (Ok)", [])

  let failed: Result(Int, String) = Error("boom")
  let _ = failed |> woof.tap_error("Processing error on Error value", [])
  Nil
}

// ---------------------------------------------------------------------------
// 15. Result logging — log_error
// ---------------------------------------------------------------------------

fn demo_log_error() -> Nil {
  reset()
  sep("15 · log_error")
  note(
    "Logs at Error level only when the Result is Error; passes through unchanged",
  )

  let ok_val: Result(String, String) = Ok("data")
  let err_val: Result(String, String) = Error("not found")

  ok_val
  |> woof.log_error("Fetch failed", [])
  |> result.unwrap("default")
  |> fn(v) { woof.info("Ok path result: " <> v, []) }

  err_val
  |> woof.log_error("Fetch failed", [woof.str("resource", "/users/99")])
  |> result.unwrap("default")
  |> fn(v) { woof.info("Error path fell back to: " <> v, []) }
}

// ---------------------------------------------------------------------------
// 16. Timing — time
// ---------------------------------------------------------------------------

fn demo_time() -> Nil {
  reset()
  sep("16 · Timing — time")
  note("Wraps a block, logs '<label> completed' with duration_ms at Info level")

  let _rows =
    woof.time("database query", fn() {
      // Simulate a query
      ["row-1", "row-2", "row-3"]
    })

  let _response = woof.time("http request", fn() { Ok("200 OK") })

  note("time also works as a use expression")
  use <- woof.time("inline block")
  woof.debug("Inside timed block", [])
}

// ---------------------------------------------------------------------------
// 17. woof.format/2 utility — format without emitting
// ---------------------------------------------------------------------------

fn demo_format_utility() -> Nil {
  reset()
  sep("17 · format/2 — format an Entry without emitting it")
  note(
    "Entry takes pre-serialised string fields — useful for custom formatters",
  )

  // Entry.fields is List(#(String, String)) — plain strings, always.
  // Use string values directly when constructing Entry for format testing.
  let entry =
    woof.Entry(
      level: woof.Warning,
      message: "Disk space low",
      fields: [#("free_gb", "10"), #("total_gb", "512")],
      namespace: None,
      timestamp: "2026-03-03T15:00:00.000Z",
    )

  let text_line = woof.format(entry, woof.Text)
  let compact_line = woof.format(entry, woof.Compact)
  let json_line = woof.format(entry, woof.Json)

  io.println("  text   → " <> text_line)
  io.println("  compact→ " <> compact_line)
  io.println("  json   → " <> json_line)
}

// ---------------------------------------------------------------------------
// 18. level_name/1 utility
// ---------------------------------------------------------------------------

fn demo_level_name() -> Nil {
  reset()
  sep("18 · level_name/1")
  note("Returns the lowercase string representation of a Level")

  let levels = [woof.Debug, woof.Info, woof.Warning, woof.Error]

  list.each(levels, fn(l) {
    io.println(
      "  woof.level_name("
      <> woof.level_name(l)
      <> ") → \""
      <> woof.level_name(l)
      <> "\"",
    )
  })
}

// ---------------------------------------------------------------------------
// 19. Sinks — default_sink / beam_logger_sink / custom sinks
// ---------------------------------------------------------------------------

fn demo_sinks() -> Nil {
  reset()
  sep("19 · Sinks — default_sink / beam_logger_sink / custom")

  note("default_sink → io.println (the default, output is what you see here)")
  woof.set_sink(woof.default_sink)
  woof.info("Using default_sink", [woof.str("target", "stdout")])
  woof.debug("Still the same beautiful output", [])

  note(
    "beam_logger_sink → routes through OTP logger (output appears via BEAM handler)",
  )
  woof.set_sink(woof.beam_logger_sink)
  woof.info("Routed through OTP logger", [
    woof.str("domain", "[woof]"),
    woof.str("handler", "default"),
  ])
  woof.warning("BEAM logger owns format and routing now", [])

  note(
    "custom sink — receives both the structured Entry and the formatted string",
  )
  reset()
  woof.set_format(woof.Json)
  woof.set_sink(fn(entry, formatted) {
    io.println(
      "  level  → "
      <> woof.level_name(entry.level)
      <> " | msg → "
      <> entry.message,
    )
    io.println("  fields → " <> string.inspect(entry.fields))
    io.println("  fmt    → " <> formatted)
    io.println("")
  })
  woof.info("Custom sink sees everything", [
    woof.str("key", "value"),
    woof.int("count", 3),
  ])
  woof.error("Error through custom sink", [woof.str("code", "ERR_42")])

  note("restore default_sink for a clean finish")
  reset()
  woof.set_sink(woof.default_sink)
  woof.info("Back to default_sink", [])
}

// ---------------------------------------------------------------------------
// 20. test_sink — capture LogEvents for inspection (v1.3)
// ---------------------------------------------------------------------------

fn demo_test_sink() -> Nil {
  reset()
  sep("20 · test_sink — capture typed LogEvents (v1.3)")
  note("test_sink() returns a typed EventSink plus a get() function")
  note("Fields keep their original types through the entire pipeline")

  let #(sink, get) = woof.test_sink()
  woof.set_sink(woof.silent_sink)
  woof.set_event_sink(sink)

  woof.info("User signed in", [
    woof.str("user_id", "u_abc"),
    woof.int("attempt", 1),
    woof.bool("mfa", True),
  ])
  woof.error("Payment failed", [
    woof.str("order_id", "ORD-42"),
    woof.int("amount", 4999),
  ])

  let events = get()

  list.each(events, fn(e) {
    io.println(
      "  captured → level=" <> woof.level_name(e.level) <> " msg=" <> e.message,
    )
    list.each(e.fields, fn(f) {
      let #(k, v) = f
      io.println("    " <> k <> ": " <> string.inspect(v))
    })
  })

  reset()
}
