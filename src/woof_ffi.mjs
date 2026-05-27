// woof FFI - JavaScript target
//
// Global config lives in a module-level variable (safe: JS is
// single-threaded). Context uses the same approach - there is no
// process dictionary on JS, but concurrency is cooperative so
// push/pop stays balanced as long as callbacks are synchronous
// (which they are in Gleam).

import { Ok, Error, toList, prepend } from "./gleam.mjs";

let state = undefined;
let context = undefined;
let trace = undefined;

export function get_state(fallback) {
  return state === undefined ? fallback : state;
}

export function set_state(s) {
  state = s;
  return undefined;
}

export function get_context(fallback) {
  return context === undefined ? fallback : context;
}

export function set_context(ctx) {
  context = ctx;
  return undefined;
}

// Scoped trace - module-level variable (JS is single-threaded). The value
// is a Gleam Option term, stored and returned opaquely.
export function get_trace(fallback) {
  return trace === undefined ? fallback : trace;
}

export function set_trace(t) {
  trace = t;
  return undefined;
}

// Convert an ISO 8601 timestamp to Unix nanoseconds, rendered as a digit
// string. Returns "0" when the input cannot be parsed. The nanosecond
// digits are appended as text to avoid Number precision loss.
export function iso_to_unix_nano(iso) {
  const ms = new Date(iso).getTime();
  if (Number.isNaN(ms)) {
    return "0";
  }
  return String(ms) + "000000";
}

export function now() {
  return new Date().toISOString();
}

export function monotonic_now() {
  // performance.now() returns milliseconds with sub-ms precision.
  // We floor to get integer milliseconds like Erlang's monotonic_time/1.
  if (typeof performance !== "undefined") {
    return Math.floor(performance.now());
  }
  // Fallback for environments without performance API.
  return Date.now();
}

export function is_tty() {
  // Node.js / Deno check
  try {
    if (typeof process !== "undefined" && process.stdout && process.stdout.isTTY) {
      return true;
    }
  } catch (_) {}
  return false;
}

// Route a log event through the level-aware console API.
// Used by woof's beam_logger_sink/2 - the opt-in production sink.
// On JS there is no centralised logger equivalent to OTP, so we use
// console.debug/info/warn/error so browser DevTools and Node.js can
// filter by severity.  The pre-formatted string is used so woof's own
// Text/Compact/JSON formatting is preserved.
export function beam_log(level, _message, _fields, _namespace, formatted) {
  const name = level.constructor.name;
  if (name === "Debug") {
    console.debug(formatted);
  } else if (name === "Info") {
    console.info(formatted);
  } else if (name === "Notice" || name === "Warning") {
    console.warn(formatted);
  } else if (name === "Error" || name === "Critical" || name === "Alert" || name === "Emergency") {
    console.error(formatted);
  } else {
    console.log(formatted);
  }
}

// test_sink() event capture - module-level array (JS is single-threaded).
let _test_events = [];

export function push_test_event(event) {
  _test_events.push(event);
  return undefined;
}

export function pop_all_test_events() {
  const captured = toList(_test_events);
  _test_events = [];
  return captured;
}

export function clear_test_events() {
  _test_events = [];
  return undefined;
}

// beam_event_sink - typed EventSink that routes through console with level routing.
// On JS, we use the pre-formatted message since there's no native structured logger.
export function beam_event_log(level, message, _fields, _namespace) {
  const name = level.constructor.name;
  if (name === "Debug") {
    console.debug(message);
  } else if (name === "Info") {
    console.info(message);
  } else if (name === "Notice" || name === "Warning") {
    console.warn(message);
  } else if (name === "Error" || name === "Critical" || name === "Alert" || name === "Emergency") {
    console.error(message);
  } else {
    console.log(message);
  }
  return undefined;
}

export function get_env(name) {
  try {
    if (typeof process !== "undefined" && process.env) {
      const val = process.env[name];
      if (val !== undefined) {
        return new Ok(val);
      }
    }
  } catch (_) {}
  return new Error(undefined);
}

// Call f(), catching any exception so a crashing sink cannot block later ones.
export function safe_call_fn(f) {
  try {
    f();
  } catch (e) {
    const msg = `[woof] sink crashed: ${e}`;
    if (typeof process !== "undefined" && process.stderr) {
      process.stderr.write(msg + "\n");
    } else {
      console.error(msg);
    }
  }
  return undefined;
}

// Test helpers - expose non-finite float values for JS-target tests only.
export function nan_float() { return NaN; }
export function infinity_float() { return Infinity; }
