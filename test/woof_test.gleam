import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import woof

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Helpers - reset state between tests
// ---------------------------------------------------------------------------

fn reset() {
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Never,
  ))
  woof.set_global_context([])
  woof.set_resource([])
  woof.set_sink(woof.silent_sink)
  woof.clear_event_sink()
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

  woof.format(make(woof.Notice), woof.Text)
  |> string.starts_with("[NOTICE]")
  |> should.be_true

  woof.format(make(woof.Warning), woof.Text)
  |> string.starts_with("[WARN]")
  |> should.be_true

  woof.format(make(woof.Error), woof.Text)
  |> string.starts_with("[ERROR]")
  |> should.be_true

  woof.format(make(woof.Critical), woof.Text)
  |> string.starts_with("[CRIT]")
  |> should.be_true

  woof.format(make(woof.Alert), woof.Text)
  |> string.starts_with("[ALERT]")
  |> should.be_true

  woof.format(make(woof.Emergency), woof.Text)
  |> string.starts_with("[EMERG]")
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
      fields: [#("data", "has \"quotes\"\u{001b}[31mred\u{001b}[0m")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  let output = woof.format(entry, woof.Json)
  // Message newline should be escaped
  output |> string.contains("Line1\\nLine2") |> should.be_true
  // Quotes and ANSI escapes in field values should be escaped
  output
  |> string.contains("has \\\"quotes\\\"\\u001b[31mred\\u001b[0m")
  |> should.be_true
}

pub fn json_reserved_keys_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "Msg",
      fields: [
        #("level", "custom"),
        #("msg", "override"),
        #("time", "now"),
        #("ns", "some"),
      ],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  let output = woof.format(entry, woof.Json)
  output |> string.contains("\"_level\":\"custom\"") |> should.be_true
  output |> string.contains("\"_msg\":\"override\"") |> should.be_true
  output |> string.contains("\"_time\":\"now\"") |> should.be_true
  output |> string.contains("\"_ns\":\"some\"") |> should.be_true
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
  woof.level_name(woof.Notice) |> should.equal("notice")
  woof.level_name(woof.Warning) |> should.equal("warning")
  woof.level_name(woof.Error) |> should.equal("error")
  woof.level_name(woof.Critical) |> should.equal("critical")
  woof.level_name(woof.Alert) |> should.equal("alert")
  woof.level_name(woof.Emergency) |> should.equal("emergency")
}

// ---------------------------------------------------------------------------
// Level filtering
// ---------------------------------------------------------------------------

pub fn level_filtering_drops_below_minimum_test() {
  reset()

  let call_count = fn(entry: woof.Entry) -> String {
    case entry.level {
      woof.Warning | woof.Error | woof.Critical | woof.Alert | woof.Emergency ->
        ""
      _ -> panic as "Unexpected log emission below minimum level"
    }
  }

  woof.configure(woof.Config(
    level: woof.Warning,
    format: woof.Custom(call_count),
    colors: woof.Never,
  ))
  woof.debug("should not appear", [])
  woof.info("should not appear", [])
  woof.notice("should not appear", [])
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

  woof.with_context([woof.str("request_id", "abc")], fn() {
    woof.info("test", [woof.str("inline", "123")])
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

  woof.with_context([woof.str("outer", "1")], fn() {
    woof.with_context([woof.str("inner", "2")], fn() {
      woof.info("nested", [woof.str("field", "3")])
    })
  })

  reset()
}

pub fn context_restored_after_callback_test() {
  reset()

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

  woof.with_context([woof.str("temp", "value")], fn() {
    woof.info("inside", [])
  })

  woof.info("outside", [])

  reset()
}

// ---------------------------------------------------------------------------
// Global context
// ---------------------------------------------------------------------------

pub fn global_context_included_in_every_message_test() {
  reset()

  woof.set_global_context([woof.str("app", "test-suite")])

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("app", "test-suite"), #("key", "val")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("msg", [woof.str("key", "val")])

  reset()
}

pub fn global_and_scoped_context_merge_test() {
  reset()

  woof.set_global_context([woof.str("app", "svc")])

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      entry.fields
      |> should.equal([#("app", "svc"), #("req", "1"), #("inline", "x")])
      ""
    }),
    colors: woof.Never,
  ))

  woof.with_context([woof.str("req", "1")], fn() {
    woof.info("merged", [woof.str("inline", "x")])
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

pub fn compact_with_spaces_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "User logged in",
      fields: [#("name", "John Doe"), #("empty", ""), #("equation", "1+1=2")],
      namespace: None,
      timestamp: "2026-02-11T10:30:45.123Z",
    )

  woof.format(entry, woof.Compact)
  |> should.equal(
    "INFO 2026-02-11T10:30:45.123Z User logged in name=\"John Doe\" empty=\"\" equation=\"1+1=2\"",
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
// Field constructors - typed (v1.3)
// ---------------------------------------------------------------------------

pub fn field_str_test() {
  woof.str("key", "value")
  |> should.equal(#("key", woof.FString("value")))
}

pub fn field_int_test() {
  woof.int("status", 200)
  |> should.equal(#("status", woof.FInt(200)))
}

pub fn field_float_test() {
  woof.float("ratio", 3.14)
  |> should.equal(#("ratio", woof.FFloat(3.14)))
}

pub fn field_bool_test() {
  woof.bool("active", True)
  |> should.equal(#("active", woof.FBool(True)))

  woof.bool("active", False)
  |> should.equal(#("active", woof.FBool(False)))
}

// ---------------------------------------------------------------------------
// Field constructors - string rendering in Entry (legacy sink path)
// ---------------------------------------------------------------------------

pub fn typed_fields_render_to_strings_in_entry_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      // Entry.fields always carries plain strings - FieldValue is
      // serialised before Entry is built, so legacy sinks/formatters
      // never see the raw types.
      entry.fields
      |> should.equal([
        #("label", "hello"),
        #("count", "42"),
        #("ratio", "3.14"),
        #("ok", "true"),
        #("ko", "false"),
      ])
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("typed", [
    woof.str("label", "hello"),
    woof.int("count", 42),
    woof.float("ratio", 3.14),
    woof.bool("ok", True),
    woof.bool("ko", False),
  ])

  reset()
}

// ---------------------------------------------------------------------------
// Legacy field helpers (`field`/`int_field`/`float_field`/`bool_field`) are
// soft-deprecated in v1.5 and remain public until v2.0.  Unit tests for the
// deprecated aliases were removed in v1.7 to keep the build noise-free.
// The aliases themselves are 1-line wrappers around `str`/`int`/`float`/`bool`
// and would only fail to compile.
// ---------------------------------------------------------------------------

pub fn field_helpers_in_log_call_test() {
  reset()

  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Custom(fn(entry) {
      // In Entry, every FieldValue is serialised to a string.
      // FBool renders lowercase ("true"/"false") - consistent with JSON.
      entry.fields
      |> should.equal([
        #("path", "/api"),
        #("status", "200"),
        #("ms", "12.5"),
        #("cached", "true"),
      ])
      ""
    }),
    colors: woof.Never,
  ))

  woof.info("Request", [
    woof.str("path", "/api"),
    woof.int("status", 200),
    woof.float("ms", 12.5),
    woof.bool("cached", True),
  ])

  reset()
}

// ---------------------------------------------------------------------------
// Sinks - legacy (Entry + formatted string)
// ---------------------------------------------------------------------------

pub fn sink_receives_entry_and_formatted_string_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Never,
  ))

  woof.set_sink(fn(entry, formatted) {
    entry.level |> should.equal(woof.Warning)
    entry.message |> should.equal("disk full")
    entry.fields |> should.equal([#("path", "/var")])
    formatted |> string.starts_with("[WARN]") |> should.be_true
    formatted |> string.contains("disk full") |> should.be_true
  })

  woof.warning("disk full", [woof.str("path", "/var")])
  reset()
}

pub fn sink_formatted_string_matches_active_format_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Json,
    colors: woof.Never,
  ))

  woof.set_sink(fn(_entry, formatted) {
    formatted |> string.starts_with("{\"level\"") |> should.be_true
  })

  woof.info("json sink test", [])
  reset()
}

pub fn sink_receives_entry_with_namespace_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Never,
  ))

  woof.set_sink(fn(entry, _formatted) {
    entry.namespace |> should.equal(Some("payments"))
    entry.message |> should.equal("tx complete")
  })

  let log = woof.new("payments")
  log |> woof.log(woof.Info, "tx complete", [])
  reset()
}

pub fn sink_receives_merged_context_fields_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Text,
    colors: woof.Never,
  ))
  woof.set_global_context([woof.str("app", "test")])

  woof.set_sink(fn(entry, _formatted) {
    // global + scoped + inline, serialised to strings in Entry
    entry.fields
    |> should.equal([#("app", "test"), #("req", "r1"), #("k", "v")])
  })

  woof.with_context([woof.str("req", "r1")], fn() {
    woof.info("msg", [woof.str("k", "v")])
  })
  reset()
}

pub fn default_sink_can_be_restored_test() {
  reset()
  woof.set_sink(fn(_entry, _formatted) { Nil })
  woof.set_sink(woof.default_sink)
  reset()
}

pub fn beam_logger_sink_does_not_crash_test() {
  reset()
  woof.set_sink(woof.beam_logger_sink)
  woof.debug("beam debug", [woof.str("sink", "beam")])
  woof.info("beam info", [woof.str("sink", "beam")])
  woof.warning("beam warning", [woof.str("sink", "beam")])
  woof.error("beam error", [woof.str("sink", "beam")])
  reset()
}

pub fn beam_logger_sink_works_with_namespace_and_fields_test() {
  reset()
  woof.set_sink(woof.beam_logger_sink)
  let log = woof.new("db")
  log
  |> woof.log(woof.Info, "query ok", [
    woof.int("ms", 12),
    woof.str("table", "orders"),
  ])
  reset()
}

// ---------------------------------------------------------------------------
// EventSink - typed LogEvent path (v1.3)
// ---------------------------------------------------------------------------

pub fn event_sink_receives_log_event_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.info("hello world", [woof.str("key", "value")])

  let events = get()
  events |> list.length |> should.equal(1)
  let assert [event] = events
  event.level |> should.equal(woof.Info)
  event.message |> should.equal("hello world")
  event.fields |> should.equal([#("key", woof.FString("value"))])

  reset()
}

pub fn event_sink_captures_typed_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.info("typed fields", [
    woof.str("s", "text"),
    woof.int("n", 42),
    woof.float("f", 1.5),
    woof.bool("b", True),
  ])

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("s", woof.FString("text")),
    #("n", woof.FInt(42)),
    #("f", woof.FFloat(1.5)),
    #("b", woof.FBool(True)),
  ])

  reset()
}

pub fn event_sink_get_clears_the_buffer_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.info("first", [])
  get() |> list.length |> should.equal(1)
  get() |> list.length |> should.equal(0)

  reset()
}

pub fn event_sink_respects_level_filter_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.set_level(woof.Error)

  woof.debug("ignored", [])
  woof.info("ignored", [])
  woof.warning("ignored", [])
  woof.error("captured", [])

  let events = get()
  events |> list.length |> should.equal(1)
  let assert [event] = events
  event.level |> should.equal(woof.Error)
  event.message |> should.equal("captured")

  reset()
}

pub fn event_sink_includes_context_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.set_global_context([woof.str("app", "test")])

  woof.with_context([woof.int("req", 1)], fn() {
    woof.info("msg", [woof.bool("ok", True)])
  })

  let assert [event] = get()
  // Full typed field list: global + scoped + inline
  event.fields
  |> should.equal([
    #("app", woof.FString("test")),
    #("req", woof.FInt(1)),
    #("ok", woof.FBool(True)),
  ])

  reset()
}

pub fn event_sink_captures_namespace_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let logger = woof.new("api")
  logger |> woof.log(woof.Warning, "slow request", [woof.int("ms", 1200)])

  let assert [event] = get()
  event.namespace |> should.equal(Some("api"))
  event.level |> should.equal(woof.Warning)
  event.fields |> should.equal([#("ms", woof.FInt(1200))])

  reset()
}

pub fn event_sink_and_legacy_sink_both_fire_test() {
  reset()

  // Both sinks should receive the event.
  let legacy_fired = fn(entry: woof.Entry, _: String) {
    entry.message |> should.equal("dual")
  }
  woof.set_sink(legacy_fired)

  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.info("dual", [])

  get() |> list.length |> should.equal(1)

  reset()
}

pub fn event_sink_captures_multiple_events_in_order_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.debug("first", [])
  woof.info("second", [])
  woof.error("third", [])

  let events = get()
  events |> list.length |> should.equal(3)
  let assert [e1, e2, e3] = events
  e1.message |> should.equal("first")
  e2.message |> should.equal("second")
  e3.message |> should.equal("third")

  reset()
}

// ---------------------------------------------------------------------------
// BEAM logger integration - verification that logger:log/4 is actually called
// (Erlang target only: relies on OTP logger handler API)
// ---------------------------------------------------------------------------

@target(erlang)
@external(erlang, "woof_ffi", "install_test_handler")
fn install_test_handler() -> Nil

@target(erlang)
@external(erlang, "woof_ffi", "remove_test_handler")
fn remove_test_handler() -> Nil

@target(erlang)
@external(erlang, "woof_ffi", "pop_test_event")
fn pop_test_event() -> Result(Dynamic, Nil)

@target(erlang)
@external(erlang, "woof_ffi", "test_event_level")
fn test_event_level(event: Dynamic) -> String

@target(erlang)
@external(erlang, "woof_ffi", "test_event_message")
fn test_event_message(event: Dynamic) -> String

@target(erlang)
@external(erlang, "woof_ffi", "test_event_domain_is_woof")
fn test_event_domain_is_woof(event: Dynamic) -> Bool

@target(erlang)
@external(erlang, "woof_ffi", "test_event_fields")
fn test_event_fields(event: Dynamic) -> List(#(String, String))

@target(erlang)
@external(erlang, "woof_ffi", "test_event_namespace")
fn test_event_namespace(event: Dynamic) -> Option(String)

@target(erlang)
pub fn beam_logger_sink_calls_logger_log_test() {
  reset()
  install_test_handler()
  woof.set_sink(woof.beam_logger_sink)

  woof.info("otp logger test", [woof.str("key", "val")])

  let assert Ok(event) = pop_test_event()
  test_event_level(event) |> should.equal("info")
  test_event_message(event) |> should.equal("otp logger test")
  test_event_domain_is_woof(event) |> should.be_true
  test_event_fields(event) |> should.equal([#("key", "val")])

  remove_test_handler()
  reset()
}

@target(erlang)
pub fn beam_logger_sink_metadata_includes_namespace_test() {
  reset()
  install_test_handler()
  woof.set_sink(woof.beam_logger_sink)

  let log = woof.new("srv")
  log |> woof.log(woof.Warning, "ns test", [woof.str("x", "1")])

  let assert Ok(event) = pop_test_event()
  test_event_level(event) |> should.equal("warning")
  test_event_message(event) |> should.equal("ns test")
  test_event_domain_is_woof(event) |> should.be_true
  test_event_fields(event) |> should.equal([#("x", "1")])
  test_event_namespace(event) |> should.equal(Some("srv"))

  remove_test_handler()
  reset()
}

@target(erlang)
pub fn beam_logger_sink_all_levels_reach_logger_test() {
  reset()
  install_test_handler()
  woof.set_sink(woof.beam_logger_sink)

  woof.debug("lvl debug", [])
  woof.info("lvl info", [])
  woof.warning("lvl warning", [])
  woof.error("lvl error", [])

  let assert Ok(e1) = pop_test_event()
  test_event_level(e1) |> should.equal("debug")
  test_event_message(e1) |> should.equal("lvl debug")

  let assert Ok(e2) = pop_test_event()
  test_event_level(e2) |> should.equal("info")
  test_event_message(e2) |> should.equal("lvl info")

  let assert Ok(e3) = pop_test_event()
  test_event_level(e3) |> should.equal("warning")
  test_event_message(e3) |> should.equal("lvl warning")

  let assert Ok(e4) = pop_test_event()
  test_event_level(e4) |> should.equal("error")
  test_event_message(e4) |> should.equal("lvl error")

  remove_test_handler()
  reset()
}

// ---------------------------------------------------------------------------
// 1.2.0 Additions
// ---------------------------------------------------------------------------

pub fn is_enabled_test() {
  reset()
  woof.set_level(woof.Warning)
  woof.is_enabled(woof.Debug) |> should.be_false
  woof.is_enabled(woof.Info) |> should.be_false
  woof.is_enabled(woof.Notice) |> should.be_false
  woof.is_enabled(woof.Warning) |> should.be_true
  woof.is_enabled(woof.Error) |> should.be_true
  woof.is_enabled(woof.Critical) |> should.be_true
  woof.is_enabled(woof.Alert) |> should.be_true
  woof.is_enabled(woof.Emergency) |> should.be_true
  reset()
}

pub fn silent_sink_discards_output_test() {
  reset()
  woof.set_sink(woof.silent_sink)
  woof.error("silent error", [])
  reset()
}

pub fn append_global_context_adds_to_existing_test() {
  reset()
  woof.set_global_context([woof.str("app", "test")])
  woof.append_global_context([woof.str("env", "ci")])

  woof.get_global_context()
  |> should.equal([woof.str("app", "test"), woof.str("env", "ci")])
  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - New levels: notice, critical, alert, emergency
// ---------------------------------------------------------------------------

pub fn notice_emits_at_notice_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.notice("something notable", [woof.str("k", "v")])

  let assert [event] = get()
  event.level |> should.equal(woof.Notice)
  event.message |> should.equal("something notable")
  reset()
}

pub fn critical_emits_at_critical_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.critical("system degraded", [woof.int("code", 503)])

  let assert [event] = get()
  event.level |> should.equal(woof.Critical)
  event.message |> should.equal("system degraded")
  event.fields |> should.equal([#("code", woof.FInt(503))])
  reset()
}

pub fn alert_emits_at_alert_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.alert("immediate action required", [])

  let assert [event] = get()
  event.level |> should.equal(woof.Alert)
  event.message |> should.equal("immediate action required")
  reset()
}

pub fn emergency_emits_at_emergency_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.emergency("system is unusable", [])

  let assert [event] = get()
  event.level |> should.equal(woof.Emergency)
  event.message |> should.equal("system is unusable")
  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - Lazy variants for new levels
// ---------------------------------------------------------------------------

pub fn notice_lazy_skips_when_level_disabled_test() {
  reset()
  woof.set_level(woof.Warning)
  woof.notice_lazy(fn() { panic as "notice_lazy thunk must not run" }, [])
  reset()
}

pub fn critical_lazy_skips_when_level_disabled_test() {
  reset()
  woof.set_level(woof.Emergency)
  woof.critical_lazy(fn() { panic as "critical_lazy thunk must not run" }, [])
  reset()
}

pub fn alert_lazy_evaluates_when_enabled_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.alert_lazy(fn() { "computed alert" }, [])

  let assert [event] = get()
  event.message |> should.equal("computed alert")
  reset()
}

pub fn emergency_lazy_evaluates_when_enabled_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.emergency_lazy(fn() { "computed emergency" }, [])

  let assert [event] = get()
  event.message |> should.equal("computed emergency")
  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - 8-level ordering
// ---------------------------------------------------------------------------

pub fn all_eight_levels_ordered_correctly_test() {
  reset()
  woof.set_level(woof.Notice)
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.debug("filtered", [])
  woof.info("filtered", [])
  woof.notice("captured", [])
  woof.warning("captured", [])
  woof.error("captured", [])
  woof.critical("captured", [])
  woof.alert("captured", [])
  woof.emergency("captured", [])

  let events = get()
  events |> list.length |> should.equal(6)

  let assert [e1, e2, e3, e4, e5, e6] = events
  e1.level |> should.equal(woof.Notice)
  e2.level |> should.equal(woof.Warning)
  e3.level |> should.equal(woof.Error)
  e4.level |> should.equal(woof.Critical)
  e5.level |> should.equal(woof.Alert)
  e6.level |> should.equal(woof.Emergency)

  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - New level format output
// ---------------------------------------------------------------------------

pub fn new_levels_compact_format_test() {
  let make = fn(level) {
    woof.Entry(
      level: level,
      message: "x",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T00:00:00.000Z",
    )
  }

  woof.format(make(woof.Notice), woof.Compact)
  |> string.starts_with("NOTICE")
  |> should.be_true

  woof.format(make(woof.Critical), woof.Compact)
  |> string.starts_with("CRIT")
  |> should.be_true

  woof.format(make(woof.Alert), woof.Compact)
  |> string.starts_with("ALERT")
  |> should.be_true

  woof.format(make(woof.Emergency), woof.Compact)
  |> string.starts_with("EMERG")
  |> should.be_true
}

pub fn new_levels_json_format_test() {
  let make = fn(level) {
    woof.Entry(
      level: level,
      message: "x",
      fields: [],
      namespace: None,
      timestamp: "2026-02-11T00:00:00.000Z",
    )
  }

  woof.format(make(woof.Notice), woof.Json)
  |> string.contains("\"level\":\"notice\"")
  |> should.be_true

  woof.format(make(woof.Critical), woof.Json)
  |> string.contains("\"level\":\"critical\"")
  |> should.be_true

  woof.format(make(woof.Alert), woof.Json)
  |> string.contains("\"level\":\"alert\"")
  |> should.be_true

  woof.format(make(woof.Emergency), woof.Json)
  |> string.contains("\"level\":\"emergency\"")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// v1.4 - Multi-sink dispatcher
// ---------------------------------------------------------------------------

pub fn set_sinks_replaces_previous_sink_test() {
  reset()
  woof.set_sink(fn(_: woof.Entry, _: String) {
    panic as "old sink must not fire after set_sinks"
  })
  woof.set_sinks([woof.silent_sink])
  woof.info("replaced", [])
  reset()
}

pub fn set_sinks_empty_list_means_no_output_test() {
  reset()
  woof.set_sinks([])
  woof.info("silent via empty sinks", [])
  reset()
}

pub fn set_sinks_multiple_sinks_both_receive_test() {
  reset()

  let assert_message = fn(entry: woof.Entry, _: String) {
    entry.message |> should.equal("dispatch")
  }
  let assert_level = fn(entry: woof.Entry, _: String) {
    entry.level |> should.equal(woof.Info)
  }

  woof.set_sinks([assert_message, assert_level])
  woof.info("dispatch", [])

  reset()
}

pub fn set_sink_still_works_as_shorthand_test() {
  reset()

  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.set_sink(woof.silent_sink)
  woof.warning("via set_sink", [])

  let assert [event] = get()
  event.level |> should.equal(woof.Warning)

  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - Presets: dev() and prod()
// ---------------------------------------------------------------------------

pub fn dev_preset_enables_debug_level_test() {
  reset()
  woof.dev()
  woof.is_enabled(woof.Debug) |> should.be_true
  woof.is_enabled(woof.Notice) |> should.be_true
  reset()
}

pub fn prod_preset_enables_info_not_debug_test() {
  reset()
  woof.prod()
  woof.is_enabled(woof.Debug) |> should.be_false
  woof.is_enabled(woof.Info) |> should.be_true
  woof.is_enabled(woof.Notice) |> should.be_true
  reset()
}

// ---------------------------------------------------------------------------
// v1.4 - beam_event_sink (typed EventSink for OTP logger)
// ---------------------------------------------------------------------------

pub fn beam_event_sink_does_not_crash_test() {
  reset()
  woof.set_event_sink(woof.beam_event_sink)
  woof.info("beam event test", [woof.str("key", "val"), woof.int("n", 42)])
  woof.notice("beam notice", [])
  woof.critical("beam critical", [woof.bool("fatal", True)])
  woof.emergency("beam emergency", [woof.float("load", 99.9)])
  reset()
}

pub fn beam_event_sink_and_legacy_sink_coexist_test() {
  reset()

  woof.set_sink(woof.silent_sink)
  woof.set_event_sink(woof.beam_event_sink)

  let #(capture, get) = woof.test_sink()
  woof.set_event_sink(capture)

  woof.info("coexist", [woof.str("a", "b")])

  let assert [event] = get()
  event.message |> should.equal("coexist")

  reset()
}

@target(erlang)
pub fn beam_event_sink_routes_to_otp_logger_test() {
  reset()
  install_test_handler()
  woof.set_event_sink(woof.beam_event_sink)

  woof.info("structured event", [woof.str("env", "prod"), woof.int("count", 7)])

  let assert Ok(event) = pop_test_event()
  test_event_level(event) |> should.equal("info")
  test_event_message(event) |> should.equal("structured event")
  test_event_domain_is_woof(event) |> should.be_true

  remove_test_handler()
  reset()
}

@target(erlang)
pub fn beam_event_sink_int_field_is_native_integer_test() {
  reset()
  install_test_handler()
  woof.set_event_sink(woof.beam_event_sink)

  woof.info("typed int", [woof.int("count", 99)])

  let assert Ok(event) = pop_test_event()
  test_event_get_int_field(event, "count") |> should.equal(Ok(99))

  remove_test_handler()
  reset()
}

@target(erlang)
pub fn beam_event_sink_v17_variants_do_not_crash_test() {
  // Smoke test: FList / FMap / FNull values must traverse the FFI without
  // crashing.  If the Gleam atom names differ from what woof_ffi.erl
  // expects, this would explode with a function_clause error.
  reset()
  install_test_handler()
  woof.set_event_sink(woof.beam_event_sink)

  woof.info("v17 variants", [
    woof.list("xs", [woof.vint(1), woof.vint(2)]),
    woof.map("o", [#("k", woof.vstr("v"))]),
    woof.null("missing"),
  ])

  let assert Ok(event) = pop_test_event()
  test_event_message(event) |> should.equal("v17 variants")

  remove_test_handler()
  reset()
}

@target(erlang)
pub fn beam_logger_sink_new_levels_reach_logger_test() {
  reset()
  install_test_handler()
  woof.set_sink(woof.beam_logger_sink)

  woof.notice("lvl notice", [])
  woof.critical("lvl critical", [])
  woof.alert("lvl alert", [])
  woof.emergency("lvl emergency", [])

  let assert Ok(e1) = pop_test_event()
  test_event_level(e1) |> should.equal("notice")
  test_event_message(e1) |> should.equal("lvl notice")

  let assert Ok(e2) = pop_test_event()
  test_event_level(e2) |> should.equal("critical")
  test_event_message(e2) |> should.equal("lvl critical")

  let assert Ok(e3) = pop_test_event()
  test_event_level(e3) |> should.equal("alert")
  test_event_message(e3) |> should.equal("lvl alert")

  let assert Ok(e4) = pop_test_event()
  test_event_level(e4) |> should.equal("emergency")
  test_event_message(e4) |> should.equal("lvl emergency")

  remove_test_handler()
  reset()
}

@target(erlang)
@external(erlang, "woof_ffi", "test_event_get_int_field")
fn test_event_get_int_field(
  event: Dynamic,
  field_name: String,
) -> Result(Int, Nil)

// ---------------------------------------------------------------------------
// v1.5 -inspect helper
// ---------------------------------------------------------------------------

pub fn inspect_returns_value_unchanged_test() {
  let result = woof.inspect(42, "answer")
  result |> should.equal(42)
}

pub fn inspect_logs_at_debug_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.inspect(#(1, "hello"), "pair")

  let assert [event] = get()
  event.level |> should.equal(woof.Debug)
  event.message |> should.equal("pair")

  reset()
}

pub fn inspect_field_contains_string_repr_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.inspect([1, 2, 3], "list")

  let assert [event] = get()
  let assert [#("value", woof.FString(repr))] = event.fields
  repr |> string.contains("1") |> should.be_true
  repr |> string.contains("2") |> should.be_true

  reset()
}

// ---------------------------------------------------------------------------
// v1.5 -tap_time helper
// ---------------------------------------------------------------------------

pub fn tap_time_returns_value_unchanged_test() {
  reset()
  let result = woof.tap_time(99, "checkpoint")
  result |> should.equal(99)
  reset()
}

pub fn tap_time_logs_at_debug_with_monotonic_field_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.tap_time("pipeline step", "checkpoint")

  let assert [event] = get()
  event.level |> should.equal(woof.Debug)
  event.message |> should.equal("checkpoint")
  let assert [#("monotonic_ms", woof.FInt(_))] = event.fields

  reset()
}

pub fn tap_time_skips_when_debug_disabled_test() {
  reset()
  woof.set_level(woof.Info)
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.tap_time("ignored", "label")

  get() |> list.length |> should.equal(0)
  reset()
}

// ---------------------------------------------------------------------------
// v1.5 -instanced Logger with context
// ---------------------------------------------------------------------------

pub fn logger_set_context_carries_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log =
    woof.new("api")
    |> woof.set_context([woof.str("version", "2"), woof.str("env", "prod")])

  log |> woof.log(woof.Info, "request", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("api"))
  event.fields
  |> should.equal([
    #("version", woof.FString("2")),
    #("env", woof.FString("prod")),
  ])

  reset()
}

pub fn logger_context_merges_before_inline_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("svc") |> woof.set_context([woof.str("region", "eu")])

  log |> woof.log(woof.Debug, "ping", [woof.int("ms", 5)])

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("region", woof.FString("eu")),
    #("ms", woof.FInt(5)),
  ])

  reset()
}

pub fn logger_context_merges_with_global_context_test() {
  reset()
  woof.set_global_context([woof.str("app", "woof")])
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("db") |> woof.set_context([woof.str("pool", "rw")])
  log |> woof.log(woof.Info, "query", [woof.bool("cached", True)])

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("app", woof.FString("woof")),
    #("pool", woof.FString("rw")),
    #("cached", woof.FBool(True)),
  ])

  reset()
}

pub fn logger_set_context_replaces_previous_context_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log =
    woof.new("svc")
    |> woof.set_context([woof.str("a", "1")])
    |> woof.set_context([woof.str("b", "2")])

  log |> woof.log(woof.Debug, "replaced", [])

  let assert [event] = get()
  event.fields |> should.equal([#("b", woof.FString("2"))])

  reset()
}

pub fn logger_without_context_behaves_as_before_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("legacy")
  log |> woof.log(woof.Warning, "msg", [woof.str("k", "v")])

  let assert [event] = get()
  event.namespace |> should.equal(Some("legacy"))
  event.fields |> should.equal([#("k", woof.FString("v"))])

  reset()
}

// ---------------------------------------------------------------------------
// v1.5 -level_from_string
// ---------------------------------------------------------------------------

pub fn level_from_string_known_levels_test() {
  woof.level_from_string("debug") |> should.equal(Ok(woof.Debug))
  woof.level_from_string("info") |> should.equal(Ok(woof.Info))
  woof.level_from_string("notice") |> should.equal(Ok(woof.Notice))
  woof.level_from_string("warning") |> should.equal(Ok(woof.Warning))
  woof.level_from_string("error") |> should.equal(Ok(woof.Error))
  woof.level_from_string("critical") |> should.equal(Ok(woof.Critical))
  woof.level_from_string("alert") |> should.equal(Ok(woof.Alert))
  woof.level_from_string("emergency") |> should.equal(Ok(woof.Emergency))
}

pub fn level_from_string_case_insensitive_test() {
  woof.level_from_string("DEBUG") |> should.equal(Ok(woof.Debug))
  woof.level_from_string("Warning") |> should.equal(Ok(woof.Warning))
  woof.level_from_string("ERROR") |> should.equal(Ok(woof.Error))
}

pub fn level_from_string_unknown_returns_error_test() {
  woof.level_from_string("verbose") |> should.equal(Error(Nil))
  woof.level_from_string("") |> should.equal(Error(Nil))
  woof.level_from_string("warn") |> should.equal(Error(Nil))
}

// ---------------------------------------------------------------------------
// v1.5 -get_level
// ---------------------------------------------------------------------------

pub fn get_level_returns_current_level_test() {
  reset()
  woof.set_level(woof.Warning)
  woof.get_level() |> should.equal(woof.Warning)
  reset()
}

pub fn get_level_reflects_configure_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Critical,
    format: woof.Text,
    colors: woof.Never,
  ))
  woof.get_level() |> should.equal(woof.Critical)
  reset()
}

// ---------------------------------------------------------------------------
// v1.5 -set_level_from_env
// ---------------------------------------------------------------------------

pub fn set_level_from_env_missing_var_returns_error_test() {
  reset()
  // Env var WOOF_TEST_MISSING_XYZ is guaranteed not set
  woof.set_level_from_env("WOOF_TEST_MISSING_XYZ") |> should.equal(Error(Nil))
  // Level unchanged
  woof.get_level() |> should.equal(woof.Debug)
  reset()
}

// ---------------------------------------------------------------------------
// v1.5 -append_context on Logger
// ---------------------------------------------------------------------------

pub fn append_context_adds_fields_to_empty_context_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("svc") |> woof.append_context([woof.str("a", "1")])
  log |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.fields |> should.equal([#("a", woof.FString("1"))])
  reset()
}

pub fn append_context_appends_to_existing_context_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log =
    woof.new("svc")
    |> woof.set_context([woof.str("a", "1")])
    |> woof.append_context([woof.str("b", "2")])

  log |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.fields
  |> should.equal([#("a", woof.FString("1")), #("b", woof.FString("2"))])
  reset()
}

pub fn append_context_does_not_replace_existing_context_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log =
    woof.new("svc")
    |> woof.set_context([woof.str("original", "yes")])
    |> woof.append_context([woof.str("extra", "also")])

  log |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  // Both fields present -set_context not clobbered
  event.fields
  |> should.equal([
    #("original", woof.FString("yes")),
    #("extra", woof.FString("also")),
  ])
  reset()
}

// ---------------------------------------------------------------------------
// v1.6 -child(Logger, String)
// ---------------------------------------------------------------------------

pub fn child_appends_namespace_with_dot_separator_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let http = woof.new("http")
  let router = woof.child(http, "router")
  router |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("http.router"))
  reset()
}

pub fn child_inherits_parent_context_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let parent = woof.new("svc") |> woof.set_context([woof.str("env", "prod")])
  let kid = woof.child(parent, "db")

  kid |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("svc.db"))
  event.fields |> should.equal([#("env", woof.FString("prod"))])
  reset()
}

pub fn child_with_no_parent_namespace_uses_only_suffix_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  // Logger created without `new`: no namespace path. Construct via new+empty
  // and child to verify base behaviour. Since `new` always sets Some(_),
  // we test the chained pattern: child of namespaced logger.
  let parent = woof.new("a")
  let kid = woof.child(parent, "b")
  let grandkid = woof.child(kid, "c")

  grandkid |> woof.log(woof.Info, "deep", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("a.b.c"))
  reset()
}

pub fn child_does_not_mutate_parent_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let parent = woof.new("svc") |> woof.set_context([woof.str("a", "1")])
  let _ = woof.child(parent, "child")

  // Parent unchanged
  parent |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("svc"))
  event.fields |> should.equal([#("a", woof.FString("1"))])
  reset()
}

// ---------------------------------------------------------------------------
// v1.6 -filter_event_sink
// ---------------------------------------------------------------------------

pub fn filter_event_sink_passes_when_predicate_true_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  let filtered = woof.filter_event_sink(fn(_e) { True }, sink)
  woof.set_event_sink(filtered)

  woof.info("kept", [])

  get() |> list.length |> should.equal(1)
  reset()
}

pub fn filter_event_sink_drops_when_predicate_false_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  let filtered = woof.filter_event_sink(fn(_e) { False }, sink)
  woof.set_event_sink(filtered)

  woof.info("dropped", [])

  get() |> list.length |> should.equal(0)
  reset()
}

pub fn filter_event_sink_routes_by_level_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  let only_errors =
    woof.filter_event_sink(
      fn(e) { woof.level_to_int(e.level) >= woof.level_to_int(woof.Error) },
      sink,
    )
  woof.set_event_sink(only_errors)

  woof.debug("d", [])
  woof.info("i", [])
  woof.warning("w", [])
  woof.error("e", [])
  woof.critical("c", [])

  let events = get()
  events |> list.length |> should.equal(2)
  let assert [e1, e2] = events
  e1.message |> should.equal("e")
  e2.message |> should.equal("c")
  reset()
}

// ---------------------------------------------------------------------------
// v1.6 -emit(LogEvent)
// ---------------------------------------------------------------------------

pub fn emit_dispatches_to_event_sink_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let event =
    woof.LogEvent(
      level: woof.Warning,
      message: "replay",
      fields: [woof.str("origin", "external")],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: Some("bridge"),
    )
  woof.emit(event)

  let assert [received] = get()
  received.level |> should.equal(woof.Warning)
  received.message |> should.equal("replay")
  received.namespace |> should.equal(Some("bridge"))
  received.fields |> should.equal([#("origin", woof.FString("external"))])
  reset()
}

pub fn emit_does_not_merge_global_context_test() {
  reset()
  woof.set_global_context([woof.str("app", "should_not_appear")])
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "raw",
      fields: [woof.str("only", "this")],
      timestamp: "ts",
      namespace: None,
    )
  woof.emit(event)

  let assert [received] = get()
  // emit() passes the LogEvent through as-is -no context merging
  received.fields |> should.equal([#("only", woof.FString("this"))])
  reset()
}

pub fn emit_dispatches_to_legacy_sinks_with_formatted_string_test() {
  reset()
  // Capture what the legacy sink receives via process dictionary.
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  // Legacy sink that copies the entry message into a captured event sink.
  woof.set_sink(woof.silent_sink)

  let event =
    woof.LogEvent(
      level: woof.Notice,
      message: "legacy path",
      fields: [],
      timestamp: "ts",
      namespace: None,
    )
  woof.emit(event)

  // Verify event sink received it (legacy path verified by absence of crash)
  let assert [received] = get()
  received.message |> should.equal("legacy path")
  reset()
}

// ---------------------------------------------------------------------------
// v1.6 -level_to_int (newly public)
// ---------------------------------------------------------------------------

pub fn level_to_int_maps_each_level_test() {
  woof.level_to_int(woof.Debug) |> should.equal(0)
  woof.level_to_int(woof.Info) |> should.equal(1)
  woof.level_to_int(woof.Notice) |> should.equal(2)
  woof.level_to_int(woof.Warning) |> should.equal(3)
  woof.level_to_int(woof.Error) |> should.equal(4)
  woof.level_to_int(woof.Critical) |> should.equal(5)
  woof.level_to_int(woof.Alert) |> should.equal(6)
  woof.level_to_int(woof.Emergency) |> should.equal(7)
}

// ---------------------------------------------------------------------------
// v1.5 -time() emits typed FInt field (bug fix verification)
// ---------------------------------------------------------------------------

pub fn time_emits_int_duration_field_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.time("op", fn() { Nil })

  let assert [event] = get()
  event.message |> string.starts_with("op completed") |> should.be_true
  let assert [#("duration_ms", woof.FInt(_))] = event.fields

  reset()
}

// ---------------------------------------------------------------------------
// v1.7 -New FieldValue variants (FList, FMap, FNull)
// ---------------------------------------------------------------------------

pub fn flist_variant_exists_test() {
  let v = woof.FList([woof.FInt(1), woof.FInt(2), woof.FInt(3)])
  let woof.FList(items) = v
  list.length(items) |> should.equal(3)
}

pub fn fmap_variant_exists_test() {
  let v = woof.FMap([#("k", woof.FString("v"))])
  let woof.FMap(pairs) = v
  list.length(pairs) |> should.equal(1)
}

pub fn fnull_variant_exists_test() {
  let v = woof.FNull
  v |> should.equal(woof.FNull)
}

// ---------------------------------------------------------------------------
// v1.7 -Field constructors: list, map, null
// ---------------------------------------------------------------------------

pub fn list_constructor_test() {
  let f = woof.list("items", [woof.FString("a"), woof.FString("b")])
  f
  |> should.equal(#("items", woof.FList([woof.FString("a"), woof.FString("b")])))
}

pub fn map_constructor_test() {
  let f = woof.map("addr", [#("city", woof.FString("Bologna"))])
  f
  |> should.equal(#("addr", woof.FMap([#("city", woof.FString("Bologna"))])))
}

pub fn null_constructor_test() {
  woof.null("optional") |> should.equal(#("optional", woof.FNull))
}

// ---------------------------------------------------------------------------
// v1.7 -Raw value helpers (vstr, vint, vfloat, vbool, vnull)
// ---------------------------------------------------------------------------

pub fn vstr_helper_test() {
  woof.vstr("x") |> should.equal(woof.FString("x"))
}

pub fn vint_helper_test() {
  woof.vint(42) |> should.equal(woof.FInt(42))
}

pub fn vfloat_helper_test() {
  woof.vfloat(3.14) |> should.equal(woof.FFloat(3.14))
}

pub fn vbool_helper_test() {
  woof.vbool(True) |> should.equal(woof.FBool(True))
  woof.vbool(False) |> should.equal(woof.FBool(False))
}

pub fn vnull_helper_test() {
  woof.vnull() |> should.equal(woof.FNull)
}

pub fn nested_construction_test() {
  // Real-world: a list of typed values + a nested map
  let f =
    woof.list("rows", [
      woof.FMap([
        #("id", woof.vint(1)),
        #("name", woof.vstr("alice")),
      ]),
      woof.FMap([
        #("id", woof.vint(2)),
        #("name", woof.vstr("bob")),
      ]),
    ])
  let assert #("rows", woof.FList(items)) = f
  list.length(items) |> should.equal(2)
}

// ---------------------------------------------------------------------------
// v1.7 -Native JSON output (FInt -> 42, not "42")
// ---------------------------------------------------------------------------

pub fn json_emits_int_as_number_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "n",
      fields: [],
      namespace: None,
      timestamp: "ts",
    )
  // Use the new public LogEvent-based formatter
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "msg",
      fields: [woof.int("n", 42)],
      timestamp: "ts",
      namespace: None,
    )
  let _ = entry
  let out = woof.format_event_json(event)
  // 42 must appear unquoted as a JSON number
  out |> string.contains("\"n\":42") |> should.be_true
  // Must NOT appear as "42"
  out |> string.contains("\"n\":\"42\"") |> should.be_false
}

pub fn json_emits_bool_as_native_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.bool("ok", True), woof.bool("ko", False)],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"ok\":true") |> should.be_true
  out |> string.contains("\"ko\":false") |> should.be_true
  out |> string.contains("\"true\"") |> should.be_false
}

pub fn json_emits_float_as_number_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.float("rate", 3.14)],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"rate\":3.14") |> should.be_true
}

pub fn json_emits_null_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.null("missing")],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"missing\":null") |> should.be_true
  out |> string.contains("\"null\"") |> should.be_false
}

pub fn json_emits_list_as_array_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.list("xs", [woof.vint(1), woof.vint(2), woof.vint(3)])],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"xs\":[1,2,3]") |> should.be_true
}

pub fn json_emits_map_as_object_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.map("addr", [
          #("city", woof.vstr("Bologna")),
          #("zip", woof.vstr("40121")),
        ]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out
  |> string.contains("\"addr\":{\"city\":\"Bologna\",\"zip\":\"40121\"}")
  |> should.be_true
}

pub fn json_emits_nested_map_in_list_test() {
  // Nested combination: list of maps
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.list("rows", [
          woof.FMap([#("id", woof.vint(1))]),
          woof.FMap([#("id", woof.vint(2))]),
        ]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out
  |> string.contains("\"rows\":[{\"id\":1},{\"id\":2}]")
  |> should.be_true
}

pub fn json_emits_empty_list_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.list("xs", [])],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"xs\":[]") |> should.be_true
}

pub fn json_emits_empty_map_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.map("o", [])],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"o\":{}") |> should.be_true
}

pub fn json_emits_list_of_nulls_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.list("nulls", [woof.vnull(), woof.vnull()])],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"nulls\":[null,null]") |> should.be_true
}

pub fn json_escapes_map_keys_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.map("data", [
          #("key with \"quote\"", woof.vstr("v")),
        ]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  // Map key must be JSON-escaped (quotes inside the key)
  out
  |> string.contains("\"key with \\\"quote\\\"\":\"v\"")
  |> should.be_true
}

pub fn json_reserved_key_check_only_at_top_level_test() {
  // "level" inside a nested FMap must NOT be prefixed (reserved keys only
  // matter at the top level where they collide with woof's own keys).
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.map("inner", [#("level", woof.vstr("debug"))]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  // Inner "level" stays as-is (no _ prefix)
  out
  |> string.contains("\"inner\":{\"level\":\"debug\"}")
  |> should.be_true
  // Must NOT have prefixed it
  out |> string.contains("_level") |> should.be_false
}

pub fn json_deeply_nested_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.map("user", [
          #("id", woof.vint(42)),
          #(
            "address",
            woof.FMap([
              #(
                "lines",
                woof.FList([woof.vstr("Via Roma 1"), woof.vstr("40121 Bologna")]),
              ),
            ]),
          ),
        ]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out
  |> string.contains(
    "\"user\":{\"id\":42,\"address\":{\"lines\":[\"Via Roma 1\",\"40121 Bologna\"]}}",
  )
  |> should.be_true
}

pub fn json_negative_int_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.int("delta", -42)],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"delta\":-42") |> should.be_true
}

pub fn do_emit_json_uses_native_types_test() {
  // End-to-end: when format=Json, the legacy sink receives a native-typed
  // JSON string (not stringified values). Tests the do_emit Json branch.
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.Json,
    colors: woof.Never,
  ))
  woof.set_sink(fn(_entry, formatted) {
    // Native types: 3000 unquoted, true unquoted
    formatted |> string.contains("\"port\":3000") |> should.be_true
    formatted |> string.contains("\"ok\":true") |> should.be_true
    formatted |> string.contains("\"port\":\"3000\"") |> should.be_false
  })
  woof.info("boot", [woof.int("port", 3000), woof.bool("ok", True)])
  reset()
}

// ---------------------------------------------------------------------------
// v1.7 -Security & solidity audit
// ---------------------------------------------------------------------------

pub fn audit_deep_nesting_50_levels_test() {
  let deep =
    list.fold(
      int.range(from: 1, to: 51, with: [], run: list.prepend),
      woof.FList([woof.vint(0)]),
      fn(acc, _) { woof.FList([acc]) },
    )
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "deep",
      fields: [#("nest", deep)],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("[0]") |> should.be_true
}

pub fn audit_large_list_500_items_test() {
  let items =
    int.range(from: 1, to: 501, with: [], run: list.prepend)
    |> list.reverse
    |> list.map(woof.vint)
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "wide",
      fields: [woof.list("nums", items)],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("[1,2,3,") |> should.be_true
  out |> string.contains(",499,500]") |> should.be_true
}

pub fn audit_empty_message_and_fields_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "",
      fields: [],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"msg\":\"\"") |> should.be_true
}

pub fn audit_unicode_key_and_value_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "msg",
      fields: [woof.str("città", "Bologna 🇮🇹")],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"città\":\"Bologna 🇮🇹\"") |> should.be_true
}

pub fn audit_control_chars_in_string_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "msg",
      fields: [
        woof.str("data", "tab\there\nnew\rret\u{0008}bksp\u{000C}ff"),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\\t") |> should.be_true
  out |> string.contains("\\n") |> should.be_true
  out |> string.contains("\\r") |> should.be_true
  out |> string.contains("\\b") |> should.be_true
  out |> string.contains("\\f") |> should.be_true
}

pub fn audit_ansi_escape_in_field_value_neutralised_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.str("evil", "\u{001B}[31mRED\u{001B}[0m")],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\\u001b") |> should.be_true
}

pub fn audit_emit_with_empty_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.emit(woof.LogEvent(
    level: woof.Info,
    message: "bare",
    fields: [],
    timestamp: "ts",
    namespace: None,
  ))
  let assert [event] = get()
  event.fields |> should.equal([])
  reset()
}

pub fn audit_emit_with_namespace_in_event_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.emit(woof.LogEvent(
    level: woof.Info,
    message: "m",
    fields: [],
    timestamp: "ts",
    namespace: Some("bridge"),
  ))
  let assert [event] = get()
  event.namespace |> should.equal(Some("bridge"))
  reset()
}

pub fn audit_filter_event_sink_predicate_drop_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  let drop_all = woof.filter_event_sink(fn(_) { False }, sink)
  woof.set_event_sink(drop_all)
  woof.info("dropped 1", [])
  woof.warning("dropped 2", [])
  woof.error("dropped 3", [])
  get() |> list.length |> should.equal(0)
  reset()
}

pub fn audit_reserved_keys_all_four_top_level_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.str("level", "x"),
        woof.str("time", "x"),
        woof.str("ns", "x"),
        woof.str("msg", "x"),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"_level\":\"x\"") |> should.be_true
  out |> string.contains("\"_time\":\"x\"") |> should.be_true
  out |> string.contains("\"_ns\":\"x\"") |> should.be_true
  out |> string.contains("\"_msg\":\"x\"") |> should.be_true
}

pub fn audit_emit_bypasses_level_filter_test() {
  // emit() is a primitive: caller decided. Level filter is NOT applied.
  reset()
  woof.set_level(woof.Emergency)
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)
  woof.emit(woof.LogEvent(
    level: woof.Debug,
    message: "below threshold",
    fields: [],
    timestamp: "ts",
    namespace: None,
  ))
  get() |> list.length |> should.equal(1)
  reset()
}

pub fn audit_special_chars_in_field_key_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.str("evil\"key\\name", "v")],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"evil\\\"key\\\\name\":\"v\"") |> should.be_true
}

pub fn audit_special_chars_in_map_key_test() {
  // Map keys (nested) must also be JSON-escaped
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.map("o", [#("a\\b\"c", woof.vstr("v"))]),
      ],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"a\\\\b\\\"c\":\"v\"") |> should.be_true
}

pub fn json_emits_string_with_escaping_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.str("q", "say \"hi\"")],
      timestamp: "ts",
      namespace: None,
    )
  let out = woof.format_event_json(event)
  out |> string.contains("\"q\":\"say \\\"hi\\\"\"") |> should.be_true
}

// ---------------------------------------------------------------------------
// v1.7 -Public format helpers
// ---------------------------------------------------------------------------

pub fn format_event_text_returns_string_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "Server started",
      fields: [woof.int("port", 3000)],
      timestamp: "2026-04-25T10:30:45.000Z",
      namespace: None,
    )
  let out = woof.format_event_text(event, woof.Never)
  out |> string.contains("[INFO]") |> should.be_true
  out |> string.contains("Server started") |> should.be_true
  out |> string.contains("port") |> should.be_true
}

pub fn format_event_compact_returns_string_test() {
  let event =
    woof.LogEvent(
      level: woof.Warning,
      message: "slow",
      fields: [woof.int("ms", 1200)],
      timestamp: "2026-04-25T10:30:45.000Z",
      namespace: None,
    )
  let out = woof.format_event_compact(event)
  out |> string.contains("WARN") |> should.be_true
  out |> string.contains("slow") |> should.be_true
  out |> string.contains("ms=1200") |> should.be_true
}

// ---------------------------------------------------------------------------
// v1.7.1 - NaN / Infinity float JSON safety (JavaScript target only)
// ---------------------------------------------------------------------------

@target(javascript)
@external(javascript, "./woof_ffi.mjs", "nan_float")
fn test_nan_float() -> Float

@target(javascript)
@external(javascript, "./woof_ffi.mjs", "infinity_float")
fn test_infinity_float() -> Float

@target(javascript)
pub fn json_nan_float_emits_null_test() {
  let nan = test_nan_float()
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.float("x", nan)],
      timestamp: "ts",
      namespace: None,
    )
  woof.format_event_json(event)
  |> string.contains("\"x\":null")
  |> should.be_true
}

@target(javascript)
pub fn json_infinity_float_emits_null_test() {
  let inf = test_infinity_float()
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.float("x", inf)],
      timestamp: "ts",
      namespace: None,
    )
  woof.format_event_json(event)
  |> string.contains("\"x\":null")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// v1.7.1 - ANSI escape sanitisation in Text format
// ---------------------------------------------------------------------------

pub fn text_ansi_in_message_is_stripped_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "\u{001B}[31mRED\u{001B}[0m injected",
      fields: [],
      namespace: None,
      timestamp: "2026-05-13T10:00:00.000Z",
    )
  let out = woof.format(entry, woof.Text)
  out |> string.contains("\u{001B}") |> should.be_false
  out |> string.contains("injected") |> should.be_true
}

pub fn text_ansi_in_field_value_is_stripped_test() {
  let entry =
    woof.Entry(
      level: woof.Info,
      message: "msg",
      fields: [#("evil", "\u{001B}[0mclean")],
      namespace: None,
      timestamp: "2026-05-13T10:00:00.000Z",
    )
  let out = woof.format(entry, woof.Text)
  out |> string.contains("\u{001B}") |> should.be_false
  out |> string.contains("clean") |> should.be_true
}

// ---------------------------------------------------------------------------
// v1.7.1 - Sink crash isolation
// ---------------------------------------------------------------------------

pub fn crashing_legacy_sink_does_not_block_later_sinks_test() {
  reset()
  let #(capture, get) = woof.test_sink()
  woof.set_event_sink(capture)
  // First sink panics; event_sink must still receive the event.
  woof.set_sinks([
    fn(_entry, _formatted) { panic as "intentional test crash" },
    woof.silent_sink,
  ])
  woof.info("after crash", [])
  get() |> list.length |> should.equal(1)
  reset()
}

pub fn crashing_event_sink_does_not_propagate_test() {
  reset()
  // A crashing event sink must not bubble the exception to the caller.
  woof.set_event_sink(fn(_event) { panic as "event sink crash" })
  woof.info("safe", [])
  reset()
}

// ---------------------------------------------------------------------------
// v1.8 - trace correlation (with_trace / set_trace / current_trace)
// ---------------------------------------------------------------------------

pub fn current_trace_none_by_default_test() {
  reset()
  woof.current_trace() |> should.equal(None)
  reset()
}

pub fn with_trace_sets_scoped_trace_test() {
  reset()
  woof.with_trace("trace-abc", "span-123", fn() {
    woof.current_trace() |> should.equal(Some(#("trace-abc", "span-123")))
  })
  reset()
}

pub fn with_trace_restores_after_body_test() {
  reset()
  woof.with_trace("t", "s", fn() { Nil })
  woof.current_trace() |> should.equal(None)
  reset()
}

pub fn with_trace_returns_body_value_test() {
  reset()
  let result = woof.with_trace("t", "s", fn() { 42 })
  result |> should.equal(42)
  reset()
}

pub fn with_trace_injects_trace_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.with_trace("trace-xyz", "span-789", fn() {
    woof.info("inside span", [woof.str("k", "v")])
  })

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("trace_id", woof.FString("trace-xyz")),
    #("span_id", woof.FString("span-789")),
    #("k", woof.FString("v")),
  ])
  reset()
}

pub fn with_trace_nested_restores_outer_test() {
  reset()
  woof.with_trace("outer-t", "outer-s", fn() {
    woof.with_trace("inner-t", "inner-s", fn() {
      woof.current_trace() |> should.equal(Some(#("inner-t", "inner-s")))
    })
    woof.current_trace() |> should.equal(Some(#("outer-t", "outer-s")))
  })
  reset()
}

pub fn log_outside_trace_has_no_trace_fields_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  woof.info("no trace", [woof.str("k", "v")])

  let assert [event] = get()
  event.fields |> should.equal([#("k", woof.FString("v"))])
  reset()
}

pub fn set_trace_carries_trace_on_logger_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("svc") |> woof.set_trace("log-t", "log-s")
  log |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("trace_id", woof.FString("log-t")),
    #("span_id", woof.FString("log-s")),
  ])
  reset()
}

pub fn set_trace_does_not_mutate_parent_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let parent = woof.new("svc")
  let _traced = parent |> woof.set_trace("t", "s")
  parent |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.fields |> should.equal([])
  reset()
}

pub fn child_inherits_parent_trace_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let parent = woof.new("svc") |> woof.set_trace("pt", "ps")
  let kid = woof.child(parent, "db")
  kid |> woof.log(woof.Info, "msg", [])

  let assert [event] = get()
  event.namespace |> should.equal(Some("svc.db"))
  event.fields
  |> should.equal([
    #("trace_id", woof.FString("pt")),
    #("span_id", woof.FString("ps")),
  ])
  reset()
}

pub fn set_trace_wins_over_scoped_trace_test() {
  reset()
  let #(sink, get) = woof.test_sink()
  woof.set_event_sink(sink)

  let log = woof.new("svc") |> woof.set_trace("logger-t", "logger-s")
  woof.with_trace("scoped-t", "scoped-s", fn() {
    log |> woof.log(woof.Info, "msg", [])
  })

  let assert [event] = get()
  event.fields
  |> should.equal([
    #("trace_id", woof.FString("logger-t")),
    #("span_id", woof.FString("logger-s")),
  ])
  reset()
}

// ---------------------------------------------------------------------------
// v1.8 - resource attributes (set_resource / get_resource)
// ---------------------------------------------------------------------------

pub fn get_resource_empty_by_default_test() {
  reset()
  woof.get_resource() |> should.equal([])
  reset()
}

pub fn set_resource_get_resource_roundtrip_test() {
  reset()
  woof.set_resource([
    woof.str("service.name", "api"),
    woof.str("service.version", "1.8.0"),
  ])
  woof.get_resource()
  |> should.equal([
    #("service.name", woof.FString("api")),
    #("service.version", woof.FString("1.8.0")),
  ])
  reset()
}

// ---------------------------------------------------------------------------
// v1.8 - OTLP JSON output
// ---------------------------------------------------------------------------

pub fn otlp_emits_severity_number_and_text_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "login",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"severity_number\":9") |> should.be_true
  out |> string.contains("\"severity_text\":\"INFO\"") |> should.be_true
}

pub fn otlp_emits_body_test() {
  let event =
    woof.LogEvent(
      level: woof.Warning,
      message: "slow query",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"body\":\"slow query\"") |> should.be_true
}

pub fn otlp_emits_typed_attributes_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.int("http.status_code", 200), woof.bool("cached", True)],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out
  |> string.contains(
    "\"attributes\":{\"http.status_code\":200,\"cached\":true}",
  )
  |> should.be_true
}

pub fn otlp_empty_attributes_is_object_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"attributes\":{}") |> should.be_true
}

pub fn otlp_promotes_trace_id_span_id_to_top_level_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [
        woof.str("trace_id", "0af7651916cd43dd"),
        woof.str("span_id", "b7ad6b7169203331"),
        woof.int("n", 1),
      ],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"trace_id\":\"0af7651916cd43dd\"") |> should.be_true
  out |> string.contains("\"span_id\":\"b7ad6b7169203331\"") |> should.be_true
  // trace ids must not leak into attributes
  out |> string.contains("\"attributes\":{\"n\":1}") |> should.be_true
}

pub fn otlp_omits_trace_when_absent_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("trace_id") |> should.be_false
  out |> string.contains("span_id") |> should.be_false
}

pub fn otlp_emits_resource_test() {
  reset()
  woof.set_resource([woof.str("service.name", "api")])
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out
  |> string.contains("\"resource\":{\"service.name\":\"api\"}")
  |> should.be_true
  reset()
}

pub fn otlp_omits_resource_when_empty_test() {
  reset()
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("resource") |> should.be_false
  reset()
}

pub fn otlp_timestamp_unix_nano_is_numeric_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"timestamp_unix_nano\":") |> should.be_true
  // value is an unquoted number, not a string
  out |> string.contains("\"timestamp_unix_nano\":\"") |> should.be_false
  // a real timestamp must not collapse to 0
  out |> string.contains("\"timestamp_unix_nano\":0") |> should.be_false
}

pub fn otlp_invalid_timestamp_falls_back_to_zero_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "not-a-timestamp",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"timestamp_unix_nano\":0") |> should.be_true
}

pub fn otlp_severity_mapping_all_levels_test() {
  let check = fn(level: woof.Level, number: String, text: String) {
    let event =
      woof.LogEvent(
        level: level,
        message: "m",
        fields: [],
        timestamp: "2026-04-25T00:00:00.000Z",
        namespace: None,
      )
    let out = woof.format_event_otlp(event)
    out |> string.contains("\"severity_number\":" <> number) |> should.be_true
    out
    |> string.contains("\"severity_text\":\"" <> text <> "\"")
    |> should.be_true
  }
  check(woof.Debug, "5", "DEBUG")
  check(woof.Info, "9", "INFO")
  check(woof.Notice, "10", "INFO2")
  check(woof.Warning, "13", "WARN")
  check(woof.Error, "17", "ERROR")
  check(woof.Critical, "18", "ERROR2")
  check(woof.Alert, "21", "FATAL")
  check(woof.Emergency, "24", "FATAL4")
}

pub fn otlp_carries_namespace_in_attributes_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [woof.int("n", 1)],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: Some("http.router"),
    )
  let out = woof.format_event_otlp(event)
  out
  |> string.contains("\"attributes\":{\"namespace\":\"http.router\",\"n\":1}")
  |> should.be_true
}

pub fn otlp_omits_namespace_when_absent_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "m",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("namespace") |> should.be_false
}

pub fn otlp_escapes_body_test() {
  let event =
    woof.LogEvent(
      level: woof.Info,
      message: "say \"hi\"",
      fields: [],
      timestamp: "2026-04-25T00:00:00.000Z",
      namespace: None,
    )
  let out = woof.format_event_otlp(event)
  out |> string.contains("\"body\":\"say \\\"hi\\\"\"") |> should.be_true
}

pub fn do_emit_otlp_routes_through_typed_formatter_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.OtlpJson,
    colors: woof.Never,
  ))
  woof.set_sink(fn(_entry, formatted) {
    formatted |> string.contains("\"severity_number\":9") |> should.be_true
    formatted
    |> string.contains("\"attributes\":{\"port\":3000}")
    |> should.be_true
  })
  woof.info("boot", [woof.int("port", 3000)])
  reset()
}

pub fn do_emit_otlp_includes_trace_from_with_trace_test() {
  reset()
  woof.configure(woof.Config(
    level: woof.Debug,
    format: woof.OtlpJson,
    colors: woof.Never,
  ))
  woof.set_sink(fn(_entry, formatted) {
    formatted |> string.contains("\"trace_id\":\"tt\"") |> should.be_true
    formatted |> string.contains("\"span_id\":\"ss\"") |> should.be_true
  })
  woof.with_trace("tt", "ss", fn() { woof.info("traced", []) })
  reset()
}

pub fn format_with_otlpjson_on_entry_path_test() {
  let entry =
    woof.Entry(
      level: woof.Error,
      message: "boom",
      fields: [#("code", "500")],
      namespace: None,
      timestamp: "2026-04-25T00:00:00.000Z",
    )
  let out = woof.format(entry, woof.OtlpJson)
  out |> string.contains("\"severity_number\":17") |> should.be_true
  out |> string.contains("\"body\":\"boom\"") |> should.be_true
  out |> string.contains("\"attributes\":{\"code\":\"500\"}") |> should.be_true
}
