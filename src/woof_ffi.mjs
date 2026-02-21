// woof FFI — JavaScript target
//
// Global config lives in a module-level variable (safe: JS is
// single-threaded). Context uses the same approach — there is no
// process dictionary on JS, but concurrency is cooperative so
// push/pop stays balanced as long as callbacks are synchronous
// (which they are in Gleam).

import { Ok, Error } from "./gleam.mjs";

let state = undefined;
let context = undefined;

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
