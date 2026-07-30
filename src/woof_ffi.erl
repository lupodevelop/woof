-module(woof_ffi).
-export([get_state/1, set_state/1, get_context/1, set_context/1,
         get_trace/1, set_trace/1, iso_to_unix_nano/1,
         now/0, monotonic_now/0, is_tty/0, get_env/1,
         beam_log/5, beam_event_log/4,
         push_test_event/1, pop_all_test_events/0, clear_test_events/0,
         install_test_handler/0, remove_test_handler/0, pop_test_event/0,
         test_event_level/1, test_event_message/1, test_event_domain_is_woof/1,
         test_event_fields/1, test_event_namespace/1, test_event_get_int_field/2,
         safe_call_fn/1, log/2,
         box_new/1, box_get/1, box_set/2, random_float/0,
         get_log_at_most/1, set_log_at_most/1]).

%% woof FFI - Erlang target
%% Global config - stored in persistent_term (erts, always available).
%% Reads are essentially free; writes are rare.

get_state(Default) ->
    case persistent_term:get(woof_state, undefined) of
        undefined -> Default;
        State     -> State
    end.

set_state(State) ->
    persistent_term:put(woof_state, State),
    nil.

%% Scoped context - stored in the process dictionary so each BEAM
%% process (= each request handler in OTP) gets its own context.

get_context(Default) ->
    case erlang:get(woof_context) of
        undefined -> Default;
        Ctx       -> Ctx
    end.

set_context(Ctx) ->
    erlang:put(woof_context, Ctx),
    nil.

%% Scoped trace - stored in the process dictionary so each BEAM process
%% (= each request handler) gets its own trace.  The value is an Option
%% term (none or {some, {TraceId, SpanId}}) passed through opaquely.

get_trace(Default) ->
    case erlang:get(woof_trace) of
        undefined -> Default;
        Trace     -> Trace
    end.

set_trace(Trace) ->
    erlang:put(woof_trace, Trace),
    nil.

%% Convert an RFC 3339 timestamp to Unix nanoseconds, rendered as a digit
%% string.  Returns <<"0">> when the input cannot be parsed.

iso_to_unix_nano(Iso) ->
    try
        Nanos = calendar:rfc3339_to_system_time(
            binary_to_list(Iso), [{unit, nanosecond}]),
        integer_to_binary(Nanos)
    catch
        _:_ -> <<"0">>
    end.

%% ISO 8601 timestamp with millisecond precision.

now() ->
    list_to_binary(
        calendar:system_time_to_rfc3339(
            os:system_time(millisecond),
            [{unit, millisecond}, {offset, "Z"}]
        )
    ).

%% Monotonic time in milliseconds - for measuring durations.

monotonic_now() ->
    erlang:monotonic_time(millisecond).

%% TTY detection - checks whether stdout is connected to a terminal.

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

%% Route a log event through the OTP logger (OTP 21+).
%% Used by woof:beam_logger_sink/2 - the opt-in production sink.
%% Level is a Gleam atom (debug/info/warning/error) - matches OTP levels.
%% Fields are passed as logger metadata under the `fields` key.
%% Namespace, when present, is included in metadata under `namespace`.
%% The pre-formatted string is unused; BEAM logger handlers own the output.

beam_log(Level, Message, Fields, Namespace, _Formatted) ->
    Meta0 = #{domain => [woof], fields => Fields},
    Meta = case Namespace of
        none         -> Meta0;
        {some, NS}   -> Meta0#{namespace => NS}
    end,
    logger:log(Level, "~ts", [Message], Meta),
    nil.

%% Route a typed LogEvent through OTP logger with structured metadata.
%% Fields are converted from Gleam FieldValue tuples to native Erlang terms.
%% FString → binary, FInt → integer, FFloat → float, FBool → boolean atom.

beam_event_log(Level, Message, Fields, Namespace) ->
    ErlFields = maps:from_list(
        [{K, field_value_to_term(V)} || {K, V} <- Fields]
    ),
    Meta0 = #{domain => [woof], fields => ErlFields},
    Meta = case Namespace of
        none       -> Meta0;
        {some, NS} -> Meta0#{namespace => NS}
    end,
    logger:log(Level, "~ts", [Message], Meta),
    nil.

field_value_to_term({f_string, S}) -> S;
field_value_to_term({f_int,    N}) -> N;
field_value_to_term({f_float,  F}) -> F;
field_value_to_term({f_bool,   B}) -> B;
field_value_to_term({f_list,   Items}) ->
    [field_value_to_term(I) || I <- Items];
field_value_to_term({f_map,    Pairs}) ->
    maps:from_list(
        [{K, field_value_to_term(V)} || {K, V} <- Pairs]
    );
field_value_to_term(f_null) -> null.

%% Call F(), catching any exception so a crashing sink cannot block later ones.
%% Errors are reported to stderr.

safe_call_fn(F) ->
    try F() catch
        Class:Reason ->
            io:format(standard_error, "[woof] sink crashed ~p:~p~n",
                      [Class, Reason]),
            nil
    end.

%% ── Mutable box ─────────────────────────────────────────────────────────
%% A single-slot mutable cell, backed by a private ETS table so each box
%% is independent of every other (unlike woof_state, which is one shared
%% persistent_term).  Used by stateful sink wrappers (rate_limit_event_sink,
%% batch_event_sink, log_at_most) to hold per-instance state across calls.

box_new(Initial) ->
    Tab = ets:new(woof_box, [set, public]),
    ets:insert(Tab, {v, Initial}),
    Tab.

box_get(Tab) ->
    [{v, V}] = ets:lookup(Tab, v),
    V.

box_set(Tab, V) ->
    ets:insert(Tab, {v, V}),
    nil.

%% Uniform random float in [0.0, 1.0) - backs sample_event_sink.

random_float() ->
    rand:uniform().

%% log_at_most/5 per-key counters - process (BEAM node) wide, same storage
%% strategy as woof_state: persistent_term, since the cap is meant to be
%% global, not per-caller.

get_log_at_most(Default) ->
    case persistent_term:get(woof_log_at_most, undefined) of
        undefined -> Default;
        Counts    -> Counts
    end.

set_log_at_most(Counts) ->
    persistent_term:put(woof_log_at_most, Counts),
    nil.

%% Read an environment variable.  Returns {ok, Value} or {error, nil}.

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, list_to_binary(Value)}
    end.

%% ── test_sink() event capture ──────────────────────────────────────────────
%% Uses the process dictionary so each test process gets isolated storage.
%% push_test_event/1  - appends one LogEvent to the capture list.
%% pop_all_test_events/0 - returns the full list and clears it.
%% clear_test_events/0   - clears without returning.

push_test_event(Event) ->
    Current = case erlang:get(woof_event_capture) of
        undefined -> [];
        List      -> List
    end,
    erlang:put(woof_event_capture, lists:append(Current, [Event])),
    nil.

pop_all_test_events() ->
    Events = case erlang:get(woof_event_capture) of
        undefined -> [];
        List      -> List
    end,
    erlang:put(woof_event_capture, []),
    Events.

clear_test_events() ->
    erlang:put(woof_event_capture, []),
    nil.

%% ── Test utilities for beam_logger_sink ────────────────────────────────────
%% Called only from the test suite to verify that beam_logger_sink routes
%% events through OTP logger:log/4 with the correct metadata.
%%
%% install_test_handler/0 - adds this module as a logger handler and saves the
%%   current primary level (restoring it on remove).
%% remove_test_handler/0  - removes the handler and restores primary level.
%% pop_test_event/0       - dequeues the earliest captured woof event; returns
%%   {ok, Event} or {error, nil} when the queue is empty.
%% Accessor functions decode individual fields from a captured event map.

install_test_handler() ->
    #{level := OldLevel} = logger:get_primary_config(),
    persistent_term:put(woof_test_old_primary_level, OldLevel),
    logger:set_primary_config(level, all),
    try ets:delete(woof_test_events) catch _:_ -> ok end,
    ets:new(woof_test_events, [named_table, public, ordered_set]),
    case logger:add_handler(woof_test_handler, woof_ffi, #{level => all}) of
        ok                          -> nil;
        {error, {already_exist, _}} -> nil
    end.

remove_test_handler() ->
    logger:remove_handler(woof_test_handler),
    OldLevel = persistent_term:get(woof_test_old_primary_level, notice),
    logger:set_primary_config(level, OldLevel),
    try ets:delete(woof_test_events) catch _:_ -> ok end,
    nil.

pop_test_event() ->
    case ets:first(woof_test_events) of
        '$end_of_table' ->
            {error, nil};
        Key ->
            [{Key, Event}] = ets:lookup(woof_test_events, Key),
            ets:delete(woof_test_events, Key),
            {ok, Event}
    end.

test_event_level(Event) ->
    atom_to_binary(maps:get(level, Event), utf8).

test_event_message(Event) ->
    maps:get(message, Event).

test_event_domain_is_woof(Event) ->
    maps:get(domain, Event) =:= [woof].

test_event_fields(Event) ->
    maps:get(fields, Event).

test_event_namespace(Event) ->
    maps:get(namespace, Event).

%% Extract a specific field as an integer from a beam_event_sink event.
%% Returns {ok, Int} if the field exists and is an integer, {error, nil} otherwise.
test_event_get_int_field(Event, FieldName) ->
    Fields = maps:get(fields, Event, #{}),
    case maps:get(FieldName, Fields, undefined) of
        undefined -> {error, nil};
        V when is_integer(V) -> {ok, V};
        _ -> {error, nil}
    end.

%% OTP logger handler callback.
%% Only woof events (domain=[woof]) are captured; everything else is ignored.
log(#{level := Level,
      msg   := {_Format, [Message]},
      meta  := #{domain := [woof]} = Meta}, _Config) ->
    Fields    = maps:get(fields,    Meta, []),
    Namespace = case maps:get(namespace, Meta, undefined) of
        undefined -> none;
        NS        -> {some, NS}
    end,
    Key = erlang:monotonic_time(),
    ets:insert(woof_test_events, {Key, #{
        level     => Level,
        message   => Message,
        domain    => [woof],
        fields    => Fields,
        namespace => Namespace
    }});
log(_LogEvent, _Config) ->
    ok.
