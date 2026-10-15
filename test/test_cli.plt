:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(pppc/cost)).

/*  Runs the installed `swipl pppc` app (the pack must be linked into
    SWIPL_PACK_PATH, which the devenv shell does). */

:- begin_tests(cli).

pppc(Args, Status, Out, Err) :-
    process_create(path(swipl), [pppc|Args],
                   [stdout(pipe(O)), stderr(pipe(E)), process(Pid)]),
    read_string(O, _, Out), read_string(E, _, Err),
    close(O), close(E),
    process_wait(Pid, Status).

tmp_program(Text, File) :-
    tmp_file_stream(text, File, S), write(S, Text), close(S).

test(compiles_to_stdout) :-
    pppc(['test/programs/pi.pas'], Status, Out, _),
    assertion(Status == exit(0)),
    assertion(sub_string(Out, _, _, _, "#pragma omp parallel for")).

test(serial_has_no_pragmas) :-
    pppc(['--serial', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(\+ sub_string(Out, _, _, _, "#pragma")).

test(all_semantic_errors_exit_1) :-
    tmp_program("program bad;\nvar x: real;\nbegin\n  x := true;\n  y := 1\nend.\n", F),
    pppc([F], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, ":4: cannot assign boolean to real")),
    assertion(sub_string(Err, _, _, _, ":5: `y' is not declared")).

test(syntax_error_exit_1) :-
    tmp_program("program bad\nbegin end.\n", F),
    pppc([F], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, ":2: syntax error: expected ;, found `begin'")).

test(missing_file_exit_1) :-
    pppc(['no/such/file.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "no/such/file.pas: cannot open source file")).

test(report) :-
    pppc(['--report', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(Out == "program 9 parallel h:read_only i:index sum:associative(+) x:local\n").

test(dump_reach) :-
    pppc(['--dump=reach', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, _, _, _, "reach(sum,[3,2],[3,2])")).

%   Source errors found while evaluating literals and constants exit 1,
%   not 2 (internal error).
test(bad_constants_exit_1) :-
    tmp_program("program bad;\nconst z = 1 / 0;\nvar x: real;\nbegin x := 1e400 end.\n", F1),
    pppc([F1], S1, _, E1),
    assertion(S1 == exit(1)),
    assertion(sub_string(E1, _, _, _, ":4: number out of range: 1e400")),
    tmp_program("program bad;\nconst z = 1 / 0;\nbegin end.\n", F2),
    pppc([F2], S2, _, E2),
    assertion(S2 == exit(1)),
    assertion(sub_string(E2, _, _, _, ":2: cannot compute constant `z': division by zero")).

test(predict) :-
    pppc(['--predict', 'test/programs/pi.pas'], Status, Out, _),
    assertion(Status == exit(0)),
    assertion(sub_string(Out, _, _, _, "parallel@4")),
    assertion(sub_string(Out, _, _, _, "\nspeedup 1:")).

test(predict_columns_stay_apart) :-
    % mm's serial times need eight digits or more
    pppc(['--predict', 'test/programs/mm.pas'], exit(0), Out, _),
    split_string(Out, "\n", "", Lines),
    forall(( member(L, Lines), sub_string(L, 0, _, _, "program "),
             sub_string(L, _, _, _, "parallel@") ),
           ( split_string(L, " ", " ", Fields0),
             exclude(==(""), Fields0, Fields),
             assertion(length(Fields, 6)) )).

test(threads) :-
    pppc(['--report', '--threads', '1', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, 0, _, _, "program 9 serial unprofitable(")).

test(cost_table) :-
    pppc(['--report', '--cost', 'test/costs/free.pl', 'test/programs/negative/small.pas'],
         exit(0), Out, _),
    assertion(sub_string(Out, 0, _, _, "program 7 parallel")).

test(no_prediction_report) :-
    % the empty range 5 to 1 is not worth a parallel region, but is
    % eligible
    pppc(['--report', '--no-prediction', 'test/programs/features.pas'], exit(0), Out, _),
    assertion(sub_string(Out, _, _, _, "\nprogram 57 parallel")).

test(no_prediction_compiles_every_eligible_loop) :-
    pppc(['--no-prediction', 'test/programs/negative/small.pas'], exit(0), Out, _),
    aggregate_all(count, sub_string(Out, _, _, _, "#pragma omp parallel for"), N),
    assertion(N == 2).

test(dump_predict_uses_threads) :-
    pppc(['--dump', 'predict', '--threads', '2', 'test/programs/pi.pas'], exit(0), Out, _),
    term_string(prediction(_, _, Speedups), Out),
    assertion(pairs_keys(Speedups, [1, 2])).

test(dump_parallel_uses_cost_table) :-
    % small's loops are parallel only with the zero-overhead table
    pppc(['--dump', 'parallel', 'test/programs/negative/small.pas'], exit(0), Out0, _),
    assertion(\+ sub_string(Out0, _, _, _, "omp_for")),
    pppc(['--dump', 'parallel', '--cost', 'test/costs/free.pl',
          'test/programs/negative/small.pas'], exit(0), Out, _),
    assertion(sub_string(Out, _, _, _, "omp_for")).

test(missing_cost_table_exit_1) :-
    pppc(['--cost', 'no/such/table.pl', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "no/such/table.pl: cannot open cost table")).

test(bad_threads_exit_1) :-
    pppc(['--threads', '0', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "must be a positive integer, not 0")).

%   At n = 50 the pi loop is too short to be worth a parallel region.
test(const_override_reaches_prediction) :-
    pppc(['--report', '--const', 'n=50', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, 0, _, _, "program 9 serial unprofitable(")).

test(const_override_compiles) :-
    pppc(['--serial', '--const', 'n=123457', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, _, _, _, "123457")).

test(unknown_const_exit_1) :-
    pppc(['--const', 'm=5', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "pi.pas: no program constant `m'")).

test(bad_const_exit_1) :-
    pppc(['--const', 'n=x', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "--const needs NAME=VALUE")).

%   The value is read on its own, so a negative number needs no space
%   (Prolog alone would read n=-5 with the operator =-).
test(negative_const) :-
    tmp_program("program t;\nconst xmin = -2.0;\nvar x: real;\nbegin x := xmin; writeln(x) end.\n", F),
    pppc(['--serial', '--const', 'xmin=-1.5', F], Status, Out, Err),
    assertion(Status-Err == exit(0)-""),
    assertion(sub_string(Out, _, _, _, "-1.5")).

test(malformed_const_exit_1, [forall(member(Arg, ['n=', '=5', n, 'n=(']))]) :-
    pppc(['--const', Arg, 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    format(string(Expected), "--const needs NAME=VALUE with a number, true or false, not ~w", [Arg]),
    assertion(sub_string(Err, _, _, _, Expected)).

test(wrong_type_const_exit_1) :-
    pppc(['--const', 'n=2.5', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "pi.pas:3: cannot override constant `n' (integer) with 2.5")).

test(time_option) :-
    pppc(['--time', '--serial', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, _, _, _, "atexit(pppc_time_report);")),
    assertion(sub_string(Out, _, _, _, "\"program 9\"")).

test(calibrate_app_writes_table) :-
    tmp_file_stream(text, File, S), close(S),
    process_create(path(swipl), [pppc_calibrate, '--max-threads', '1', '--repeat', '1', '-o', File],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status-Err == exit(0)-""),
    load_cost_table(File, _).

:- end_tests(cli).
