import { Ok, Error } from "./gleam.mjs";
import { set_context, set_trace } from "./woof_ffi.mjs";

export function reset_scopes() {
  set_context(undefined);
  set_trace(undefined);
}

export function catch_panic(body) {
  try {
    return new Ok(body());
  } catch (error) {
    if (error.gleam_error !== "panic") throw error;
    return new Error(error.message);
  }
}
