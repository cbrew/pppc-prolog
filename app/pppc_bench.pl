:- use_module(library(main)).
:- use_module(library(option)).
:- use_module(library(pppc/bench)).
:- use_module(library(pppc/messages), []).

/** <module> pppc_bench command line

    swipl pppc_bench [-o FILE] [--threads 1,2,4] [--repeat K]
                     [--program NAME]... [--sizes FILE] [--cost FILE]

Runs the benchmarks (see pppc_bench) and writes the results as
markdown to FILE or standard output. Text after the notes marker of an
existing FILE is kept.

Exit status: 0 success, 1 the bench failed, 2 internal error.
*/

:- initialization(main, main).

opt_type(o,       output,  file(write)).
opt_type(threads, threads, atom).
opt_type(repeat,  repeat,  between(1, 1000)).
opt_type(program, program, atom).
opt_type(sizes,   sizes,   file).
opt_type(cost,    cost,    file).

opt_help(output,  "Write the results to this file (default: standard output)").
opt_help(threads, "Comma-separated thread counts (default: 1-8 and the number of CPUs)").
opt_help(repeat,  "Runs of each binary at each thread count; the median is kept (default 3)").
opt_help(program, "Run only this benchmark (repeatable; default: all seven)").
opt_help(sizes,   "Problem sizes file (default bench/sizes.pl)").
opt_help(cost,    "Cost table file (default: the shipped table)").
opt_help(help(usage), " [options]").

main(Argv) :-
    argv_options(Argv, Positional, Options0),
    (   Positional == []
    ->  catch(( bench_options_cli(Options0, Options),
                bench(Options, Results),
                output(Options0, Results) ),
              pppc(E), failed(E))
    ;   argv_usage(debug),
        halt(1)
    ).

%   bench_options_cli(+CLIOptions, -Options): the options of bench/2.
bench_options_cli(Options0, Options) :-
    findall(P, member(program(P), Options0), Programs),
    (   Programs == []
    ->  Os1 = []
    ;   Os1 = [programs(Programs)]
    ),
    (   option(threads(Text), Options0)
    ->  thread_list(Text, Ps),
        Os2 = [threads(Ps)|Os1]
    ;   Os2 = Os1
    ),
    include(passed_on, Options0, Os3),
    append(Os2, Os3, Options).

passed_on(repeat(_)).
passed_on(sizes(_)).
passed_on(cost(_)).

thread_list(Text, Ps) :-
    split_string(Text, ",", " ", Parts),
    (   maplist(number_string, Ps, Parts),
        Ps \== [],
        forall(member(P, Ps), (integer(P), P > 0))
    ->  true
    ;   throw(pppc(bench(bad_threads(Text))))
    ).

output(Options, Results) :-
    (   option(output(File), Options)
    ->  warn_unmarked(File),
        notes(File, Notes),
        with_output_to(string(Text), write_results(current_output, Results, Notes)),
        setup_call_cleanup(open(File, write, S), write(S, Text), close(S))
    ;   write_results(current_output, Results, "\n")
    ).

%   warn_unmarked(+File): File has text but no notes marker, so all of
%   it is about to be replaced.
warn_unmarked(File) :-
    (   exists_file(File),
        read_file_to_string(File, Text, []),
        split_string(Text, "", " \t\r\n", [Trimmed]),
        Trimmed \== "",
        \+ sub_string(Text, _, _, _, "<!-- notes -->")
    ->  print_message(warning, pppc(pppc_bench, bench(no_notes_marker(File))))
    ;   true
    ).

failed(internal(Pass, Reason)) :- !,
    print_message(error, pppc(pppc_bench, internal(Pass, Reason))),
    halt(2).
failed(semantic_errors(Errors)) :- !,
    forall(member(pppc(E), Errors), print_message(error, pppc(pppc_bench, E))),
    halt(1).
failed(E) :-
    print_message(error, pppc(pppc_bench, E)),
    halt(1).
