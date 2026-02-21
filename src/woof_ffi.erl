-module(woof_ffi).
-export([get_state/1, set_state/1, get_context/1, set_context/1,
         now/0, monotonic_now/0, is_tty/0, get_env/1]).

%% woof FFI — Erlang target
%% Global config — stored in persistent_term (erts, always available).
%% Reads are essentially free; writes are rare.

get_state(Default) ->
    case persistent_term:get(woof_state, undefined) of
        undefined -> Default;
        State     -> State
    end.

set_state(State) ->
    persistent_term:put(woof_state, State),
    nil.

%% Scoped context — stored in the process dictionary so each BEAM
%% process (= each request handler in OTP) gets its own context.

get_context(Default) ->
    case erlang:get(woof_context) of
        undefined -> Default;
        Ctx       -> Ctx
    end.

set_context(Ctx) ->
    erlang:put(woof_context, Ctx),
    nil.

%% ISO 8601 timestamp with millisecond precision.

now() ->
    list_to_binary(
        calendar:system_time_to_rfc3339(
            os:system_time(millisecond),
            [{unit, millisecond}, {offset, "Z"}]
        )
    ).

%% Monotonic time in milliseconds — for measuring durations.

monotonic_now() ->
    erlang:monotonic_time(millisecond).

%% TTY detection — checks whether stdout is connected to a terminal.

is_tty() ->
    case io:getopts(standard_io) of
        {ok, Opts} ->
            case proplists:get_value(terminal, Opts) of
                true -> true;
                _    -> false
            end;
        _ ->
            false
    end.

%% Read an environment variable.  Returns {ok, Value} or {error, nil}.

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, list_to_binary(Value)}
    end.
