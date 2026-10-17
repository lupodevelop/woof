-module(woof_test_ffi).
-export([catch_panic/1, reset_scopes/0]).

reset_scopes() ->
    woof_ffi:set_context([]),
    woof_ffi:set_trace(none).

catch_panic(Body) ->
    try Body() of
        Value -> {ok, Value}
    catch
        error:#{gleam_error := panic, message := Message} -> {error, Message}
    end.
