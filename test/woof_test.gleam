import gleam/dynamic.{type Dynamic}
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
// Legacy field helpers - still work, return FieldValue now
// ---------------------------------------------------------------------------

pub fn legacy_field_helper_string_test() {
  woof.field("key", "value")
  |> should.equal(#("key", woof.FString("value")))
}

pub fn legacy_field_helper_int_test() {
  woof.int_field("status", 200)
  |> should.equal(#("status", woof.FInt(200)))
}

pub fn legacy_field_helper_float_test() {
  woof.float_field("duration", 12.5)
  |> should.equal(#("duration", woof.FFloat(12.5)))
}

pub fn legacy_field_helper_bool_test() {
  woof.bool_field("cached", True)
  |> should.equal(#("cached", woof.FBool(True)))

  woof.bool_field("cached", False)
  |> should.equal(#("cached", woof.FBool(False)))
}

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
