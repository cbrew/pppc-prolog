:- module(pppc_messages, []).

/** <module> Diagnostic messages

Renders pppc(File, Error) terms for print_message/2. All diagnostics
the compiler produces go through here, so their wording lives in one
place and they print in the usual File:Line: format.
*/

:- multifile prolog:message//1.

prolog:message(pppc(File, Error)) -->
    pppc_message(File, Error).

pppc_message(File, syntax(L, Expected, Found)) -->
    [ '~w:~w: syntax error: expected ~w, found '-[File, L, Expected] ],
    found(Found).
pppc_message(File, semantic(L, Msg)) -->
    [ '~w:~w: '-[File, L] ],
    semantic(Msg).
pppc_message(File, bad_number(L, Text)) -->
    [ '~w:~w: number out of range: ~w'-[File, L, Text] ].
pppc_message(File, no_source) -->
    [ '~w: cannot open source file'-[File] ].
pppc_message(File, internal(Pass, Reason)) -->
    [ '~w: internal compiler error in pass ~w: ~p'-[File, Pass, Reason] ].
pppc_message(File, bad_threads(N)) -->
    [ '~w: the number of threads must be a positive integer, not ~p'-[File, N] ].
pppc_message(_, cost_table_missing(Table)) -->
    [ '~w: cannot open cost table'-[Table] ].
pppc_message(_, bad_cost_table(Table, syntax_error(L, What))) --> !,
    [ '~w:~w: syntax error in cost table: ~w'-[Table, L, What] ].
pppc_message(_, bad_cost_table(Table, Culprit)) -->
    [ '~w: '-[Table] ],
    cost_table(Culprit).
pppc_message(Who, calibrate(Why)) -->
    [ '~w: '-[Who] ],
    calibrate(Why).

cost_table(missing(Entry))     --> !, [ 'cost table has no entry for ~q'-[Entry] ].
cost_table(duplicate(Fact))    --> !, [ 'duplicate cost table entry ~q'-[Fact] ].
cost_table(syntax_error(What)) --> !, [ 'syntax error in cost table: ~w'-[What] ].
cost_table(Fact)               --> [ 'invalid cost table entry ~q'-[Fact] ].

calibrate(no_compiler)       --> !, [ 'cannot run gcc' ].
calibrate(build_failed(Out)) --> !, [ 'the calibration program does not build:~n~w'-[Out] ].
calibrate(run_failed(St))    --> !, [ 'the calibration program failed: ~p'-[St] ].
calibrate(bad_output(Line))  --> !, [ 'unexpected calibration output: ~w'-[Line] ].
calibrate(no_signal)         --> !, [ 'integer addition was too fast to time; use more iterations' ].
calibrate(Why)               --> [ 'calibration failed: ~p'-[Why] ].

found(eof)      --> !, [ 'end of file' ].
found(kw(K))    --> !, [ '`~w''' - [K] ].
found(id(N))    --> !, [ 'identifier `~w''' - [N] ].
found(punct(P)) --> !, [ '`~w''' - [P] ].
found(int(N))   --> !, [ 'number ~w' - [N] ].
found(real(R))  --> !, [ 'number ~w' - [R] ].
found(str(_))   --> !, [ 'string' ].
found(char(C))  --> !, [ 'character `~w''' - [C] ].
found(X)        --> [ '~p' - [X] ].

semantic(redeclared(N))         --> [ '`~w'' is already declared'-[N] ].
semantic(undeclared(N))         --> [ '`~w'' is not declared'-[N] ].
semantic(not_constant(N))       --> [ 'value of constant `~w'' is not a constant expression'-[N] ].
semantic(not_a_type(N))         --> [ '`~w'' is not a type'-[N] ].
semantic(bad_bounds)            --> [ 'array bounds must be integer constants with low =< high' ].
semantic(nested_routine(N))     --> [ 'nested procedure or function `~w'' is not supported'-[N] ].
semantic(bad_for_variable)      --> [ 'for loop variable must be a simple integer variable' ].
semantic(not_a_procedure(N))    --> [ '`~w'' is not a procedure'-[N] ].
semantic(not_a_function(N))     --> [ '`~w'' is not a function'-[N] ].
semantic(not_a_variable(N))     --> [ '`~w'' is not a variable'-[N] ].
semantic(function_result_read(N)) --> [ 'function `~w'' called without arguments'-[N] ].
semantic(bad_zero_assignment)   --> [ 'zero assignment needs an array or record of numbers' ].
semantic(assign_mismatch(V, E)) --> [ 'cannot assign ~p to ~p'-[E, V] ].
semantic(not_boolean)           --> [ 'condition must be boolean' ].
semantic(not_integer)           --> [ 'integer expression expected' ].
semantic(not_writable)          --> [ 'write accepts only integer, real, boolean and string values' ].
semantic(not_an_array)          --> [ 'subscript applied to a value that is not an array' ].
semantic(not_a_record)          --> [ 'field selection applied to a value that is not a record' ].
semantic(no_such_field(F))      --> [ 'no field `~w'''-[F] ].
semantic(type_clash(Op, T))     --> [ 'type clash at operator ~w: ~p'-[Op, T] ].
semantic(type_clash(Op, A, B))  --> [ 'type clash at operator ~w: ~p and ~p'-[Op, A, B] ].
semantic(bad_arguments(N))      --> [ 'wrong argument types for `~w'''-[N] ].
semantic(arg_count(N, E, G))    --> [ '`~w'' takes ~d argument(s), ~d given'-[N, E, G] ].
semantic(arg_mismatch(P, A))    --> [ 'argument of type ~p given for parameter of type ~p'-[A, P] ].
semantic(constant_error(N, W))  --> [ 'cannot compute constant `~w'': '-[N] ], evaluation(W).

evaluation(zero_divisor)   --> !, [ 'division by zero' ].
evaluation(float_overflow) --> !, [ 'overflow' ].
evaluation(W)              --> [ '~w'-[W] ].
