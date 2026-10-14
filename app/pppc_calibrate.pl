:- use_module(library(main)).
:- use_module(library(option)).
:- use_module(library(pppc/calibrate)).
:- use_module(library(pppc/messages), []).

/** <module> pppc_calibrate command line

    swipl pppc_calibrate [-o FILE] [--max-threads N] [--repeat K]

Measures a cost table for this machine (see pppc_calibrate) and
writes it to FILE or standard output.

Exit status: 0 success, 1 calibration failed, 2 internal error.
*/

:- initialization(main, main).

opt_type(o,           output,      file(write)).
opt_type(max_threads, max_threads, between(1, 1024)).
opt_type(repeat,      repeat,      between(1, 1000)).

opt_help(output,      "Write the table to this file (default: standard output)").
opt_help(max_threads, "Measure OpenMP overheads for 1..N threads (default: number of CPUs)").
opt_help(repeat,      "Runs of each measurement; the median is kept (default 5)").
opt_help(help(usage), " [options]").

main(Argv) :-
    argv_options(Argv, Positional, Options0),
    (   Positional == []
    ->  include(calibration_option, Options0, Options),
        catch(run(Options), E, failed(E))
    ;   argv_usage(debug),
        halt(1)
    ).

calibration_option(max_threads(_)).
calibration_option(repeat(_)).
calibration_option(output(_)).

run(Options0) :-
    calibration_options(Options0, Options),
    calibrate(Options, Facts),
    exclude(output_option, Options, Recorded),
    (   option(output(File), Options)
    ->  setup_call_cleanup(open(File, write, S),
                           write_table(S, Facts, Recorded),
                           close(S))
    ;   write_table(current_output, Facts, Recorded)
    ).

output_option(output(_)).

failed(pppc(E)) :- !,
    print_message(error, pppc(pppc_calibrate, E)),
    halt(1).
failed(E) :-
    print_message(error, pppc(pppc_calibrate, internal(calibrate, E))),
    halt(2).
