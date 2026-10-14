:- use_module(library(main)).
:- use_module(library(option)).
:- use_module(library(pppc)).

/** <module> pppc command line

    swipl pppc [options] input.pas

Exit status: 0 success, 1 error in the source program, 2 internal error.
*/

:- initialization(main, main).

opt_type(serial, serial, boolean).
opt_type(report, report, boolean).
opt_type(predict, predict, boolean).
opt_type(prediction, prediction, boolean).
opt_type(threads, threads, integer).
opt_type(cost, cost, file).
opt_type(dump,   dump,   oneof([tokens, parse, typed, labelled, reach, predict, parallel])).
opt_type(o,      output, file(write)).

opt_help(serial, "Do not parallelize: emit plain serial C").
opt_help(report, "Print the parallelization decision for every for loop").
opt_help(predict, "Print predicted loop times and speedups").
opt_help(prediction, "Decide parallel loops by predicted time (default true; --no-prediction parallelizes every eligible loop)").
opt_help(threads, "Number of threads to predict for (default 4)").
opt_help(cost, "Cost table file (default: the shipped table)").
opt_help(dump,   "Print the intermediate representation after a stage and stop").
opt_help(output, "Write the C code to this file (default: standard output)").
opt_help(help(usage), " [options] input.pas").

main(Argv) :-
    argv_options(Argv, Positional, Options),
    (   Positional = [File]
    ->  catch(run(File, Options), pppc(E), failed(File, E))
    ;   argv_usage(debug),
        halt(1)
    ).

run(File, Options) :-
    option(dump(Stage), Options), !,
    pppc_stage(File, Stage, Options, Result),
    print_term(Result, []), nl.
run(File, Options) :-
    option(predict(true), Options), !,
    pppc_predict(File, Options, prediction(Loops, Serial, Speedups)),
    option(threads(N), Options, 4),
    forall(member(loop_time(R, L, S, P), Loops),
           format("~w~t~12| ~t~d~6+  serial ~t~d~19+  parallel@~d ~t~d~24+~n",
                  [R, L, round(S), N, round(P)])),
    format("program serial ~d~nspeedup", [round(Serial)]),
    forall(member(K-X, Speedups), format(" ~d:~2f", [K, X])),
    nl.
run(File, Options) :-
    option(report(true), Options), !,
    pppc_report(File, Options, Lines),
    forall(member(L, Lines), writeln(L)).
run(File, Options) :-
    pppc_compile(File, Options, C),
    (   option(output(Out), Options)
    ->  setup_call_cleanup(open(Out, write, S), write(S, C), close(S))
    ;   write(C)
    ).

failed(File, semantic_errors(Errors)) :- !,
    forall(member(pppc(E), Errors), print_message(error, pppc(File, E))),
    halt(1).
failed(File, internal(Pass, Reason)) :- !,
    print_message(error, pppc(File, internal(Pass, Reason))),
    halt(2).
failed(File, E) :-
    print_message(error, pppc(File, E)),
    halt(1).
