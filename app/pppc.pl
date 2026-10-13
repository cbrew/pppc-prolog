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
opt_type(dump,   dump,   oneof([tokens, parse, typed, labelled, reach, parallel])).
opt_type(o,      output, file(write)).

opt_help(serial, "Do not parallelize: emit plain serial C").
opt_help(report, "Print the parallelization decision for every for loop").
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
    pppc_stage(File, Stage, Result),
    print_term(Result, []), nl.
run(File, Options) :-
    option(report(true), Options), !,
    pppc_report(File, Lines),
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
