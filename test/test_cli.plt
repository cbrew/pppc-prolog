:- use_module(library(process)).
:- use_module(library(readutil)).

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

:- end_tests(cli).
