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

test(threads) :-
    pppc(['--report', '--threads', '1', 'test/programs/pi.pas'], exit(0), Out, _),
    assertion(sub_string(Out, 0, _, _, "program 9 serial unprofitable(")).

test(cost_table) :-
    pppc(['--report', '--cost', 'test/costs/free.pl', 'test/programs/negative/small.pas'],
         exit(0), Out, _),
    assertion(sub_string(Out, 0, _, _, "program 7 parallel")).

test(missing_cost_table_exit_1) :-
    pppc(['--cost', 'no/such/table.pl', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "no/such/table.pl: cannot open cost table")).

test(bad_threads_exit_1) :-
    pppc(['--threads', '0', 'test/programs/pi.pas'], Status, _, Err),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "must be a positive integer, not 0")).

test(calibrate_app_writes_table) :-
    tmp_file_stream(text, File, S), close(S),
    process_create(path(swipl), [pppc_calibrate, '--max-threads', '1', '--repeat', '1', '-o', File],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status-Err == exit(0)-""),
    load_cost_table(File, _).

:- end_tests(cli).
