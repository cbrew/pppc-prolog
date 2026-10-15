:- module(pppc_bench,
          [ bench/2,                    % +Options, -Results
            bench_options/2,            % +Options0, -Options
            read_sizes/2,               % +File, -Sizes
            parse_timings/2,            % +Text, -Timings
            speedup_rows/2,             % +Results, -Rows
            loop_rows/3,                % +Results, +P, -Rows
            write_results/3,            % +Stream, +Results, +Notes
            notes/2                     % +File, -Notes
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(pairs)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(pppc)).
:- use_module(library(pppc/cost)).
:- use_module(library(pppc/predict), [speedup_points/2]).
:- use_module(library(pppc/calibrate), [cpu_model/1, gcc_version/1]).

/** <module> Measure speedups and loop verdicts

Reproduces the paper's Table 4.1 (section 4.3.6): for each benchmark,
at the problem size given in a sizes file, the predicted and actual
whole-program speedups at several thread counts, and for each
candidate loop the predicted and actual time per execution, serial and
parallel, with the verdict each implies.

Three binaries are built per benchmark, all timed (pppc option
timing(true)): `serial`, `parallel` (run time prediction at the largest
thread count, Pmax) and `all` (every candidate loop parallel). `serial`
runs K times, the others K times at each thread count P, under
OMP_NUM_THREADS=P, OMP_PLACES=cores and OMP_PROC_BIND=close: one thread
per physical core while there are cores left (with the default places,
one per hardware thread, `close` would put threads 0 and 1 on the two
hardware threads of one core). Medians are reported.

Options of bench/2:

  - threads(Ps)  thread counts (default: the speedup points up to the
    number of CPUs);
  - repeat(K)  runs of each binary at each thread count (default 3);
  - programs(Names)  benchmarks to run (default: all seven);
  - sizes(File)  the sizes file (default `bench/sizes.pl`);
  - dir(Dir)  where the programs are (default `test/programs`);
  - cost(File)  the cost table (default: the shipped table).

Errors are thrown as pppc(bench(Why)).
*/

%!  bench_options(+Options0, -Options) is det.
%
%   Options0 completed with the defaults, the thread counts sorted and
%   without duplicates. Throws pppc(bench(bad_threads(Ps))) if the
%   thread counts are not a non-empty list of positive integers.
bench_options(Options0, Options) :-
    current_prolog_flag(cpu_count, CPUs),
    speedup_points(CPUs, Default),
    default_cost_file(Cost),
    merge_options(Options0,
                  [ threads(Default), repeat(3),
                    programs([pi, montepi, mandel, linear, nbody, mm, cg]),
                    sizes('bench/sizes.pl'), dir('test/programs'), cost(Cost) ],
                  Options1),
    option(threads(Ps0), Options1),
    (   is_list(Ps0), Ps0 \== [], forall(member(P, Ps0), (integer(P), P > 0))
    ->  sort(Ps0, Ps)
    ;   throw(pppc(bench(bad_threads(Ps0))))
    ),
    merge_options([threads(Ps)], Options1, Options).

%!  bench(+Options, -Results) is det.
%
%   Run the benchmarks. Results is a dict bench{...} with the keys
%   date, cpu, gcc, cost, repeat, threads, and programs: one dict
%   prog{name, sizes, unit, speedups, loops, runs} per benchmark, where
%   speedups is the predicted P-Speedup for every thread count, with
%   the loops chosen at Pmax, loops is P-LoopTimes
%   (the loop_time/4 terms of pppc_predict/3 at P) for P = 4 and Pmax,
%   unit is the cost table's seconds per unit, and runs is a list of
%   run(Mode, P, WallSeconds, Timings) with Timings as parse_timings/2
%   gives them.
bench(Options0, Results) :-
    bench_options(Options0, Options),
    option(threads(Ps), Options),
    option(repeat(K), Options),
    option(programs(Names), Options),
    option(sizes(SizesFile), Options),
    option(cost(Cost), Options),
    read_sizes(SizesFile, Sizes),
    load_cost_table(Cost, Table),
    unit_seconds(Table, Unit),
    maplist(bench_program(Options, Sizes, Unit), Names, Progs),
    get_time(Now),
    format_time(atom(Date), '%F %T', Now),
    cpu_model(CPU),
    gcc_version(GCC),
    Results = bench{date:Date, cpu:CPU, gcc:GCC, cost:Cost, repeat:K,
                    threads:Ps, programs:Progs}.

bench_program(Options, Sizes, Unit, Name, Prog) :-
    (   memberchk(Name-Overrides, Sizes)
    ->  true
    ;   throw(pppc(bench(missing_size(Name))))
    ),
    option(dir(Dir), Options),
    option(threads(Ps), Options),
    option(repeat(K), Options),
    option(cost(Cost), Options),
    format(atom(Pas), '~w/~w.pas', [Dir, Name]),
    findall(const(O), member(O, Overrides), Consts),
    Base = [cost(Cost)|Consts],
    max_list(Ps, Pmax),
    pppc_predict(Pas, [threads(Pmax), points(Ps)|Base], prediction(_, _, Speedups)),
    loop_points(Ps, LoopPs),
    findall(P-Times,
            ( member(P, LoopPs),
              pppc_predict(Pas, [threads(P)|Base], prediction(Times, _, _)) ),
            Loops),
    setup_call_cleanup(
        tmp_file(pppc_bench, Tmp),
        ( build(Pas, Name, serial, [serial(true), timing(true)|Base], Tmp, Serial),
          build(Pas, Name, parallel, [threads(Pmax), timing(true)|Base], Tmp, Parallel),
          build(Pas, Name, all, [prediction(false), timing(true)|Base], Tmp, All),
          findall(R, runs(Name, serial, Serial, [1], K, R), Rs1),
          findall(R, runs(Name, parallel, Parallel, Ps, K, R), Rs2),
          findall(R, runs(Name, all, All, Ps, K, R), Rs3) ),
        remove_builds(Tmp)),
    append([Rs1, Rs2, Rs3], Runs),
    Prog = prog{name:Name, sizes:Overrides, unit:Unit, speedups:Speedups,
                loops:Loops, runs:Runs}.

%   loop_points(+Ps, -LoopPs): the thread counts with a loop table: 4
%   (the paper's machine) and the largest, if measured.
loop_points(Ps, LoopPs) :-
    max_list(Ps, Pmax),
    include(loop_point(Pmax), Ps, LoopPs0),
    sort(LoopPs0, LoopPs).

loop_point(Pmax, P) :- memberchk(P, [4, Pmax]).

runs(Name, Mode, Exe, Ps, K, run(Mode, P, Wall, Timings)) :-
    member(P, Ps),
    between(1, K, _),
    run(Name, Mode, Exe, P, Wall, Timings).

                 /*******************************
                 *        BUILD AND RUN         *
                 *******************************/

%   build(+Pas, +Name, +Mode, +Options, +Tmp, -Exe): compile Pas with
%   pppc and gcc into Tmp_Mode.
build(Pas, Name, Mode, Options, Tmp, Exe) :-
    pppc_compile(Pas, Options, C),
    format(atom(Src), '~w_~w.c', [Tmp, Mode]),
    format(atom(Exe), '~w_~w', [Tmp, Mode]),
    setup_call_cleanup(open(Src, write, S), write(S, C), close(S)),
    catch(process_create(path(gcc), ['-O2', '-fopenmp', '-o', Exe, Src, '-lm'],
                         [stdout(null), stderr(pipe(E)), process(Pid)]),
          error(existence_error(_, _), _),
          throw(pppc(bench(no_gcc)))),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    (   Status == exit(0)
    ->  true
    ;   throw(pppc(bench(build_failed(Name, Mode, Err))))
    ).

remove_builds(Tmp) :-
    forall(( member(Mode, [serial, parallel, all]),
             member(Ext, ['', '.c']),
             format(atom(F), '~w_~w~w', [Tmp, Mode, Ext]) ),
           catch(delete_file(F), _, true)).

%   run(+Name, +Mode, +Exe, +P, -Wall, -Timings): run Exe on P threads.
run(Name, Mode, Exe, P, Wall, Timings) :-
    get_time(T0),
    process_create(Exe, [],
                   [ stdout(null), stderr(pipe(E)), process(Pid),
                     environment(['OMP_NUM_THREADS'=P, 'OMP_PLACES'=cores,
                                  'OMP_PROC_BIND'=close]) ]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    get_time(T1),
    (   Status == exit(0)
    ->  true
    ;   throw(pppc(bench(run_failed(Name, Mode, P, Status))))
    ),
    Wall is T1 - T0,
    parse_timings(Err, Timings).

%!  parse_timings(+Text, -Timings) is det.
%
%   Timings is a list of Routine-Line-Executions-Seconds, one for each
%   `pppc_time` line of Text. Throws pppc(bench(bad_timing(Line))) for
%   any other non-empty line.
parse_timings(Text, Timings) :-
    split_string(Text, "\n", "", Lines0),
    exclude(==(""), Lines0, Lines),
    maplist(timing, Lines, Timings).

timing(Line, R-L-N-Secs) :-
    split_string(Line, " ", "", ["pppc_time", RS, LS, NS, SecsS]),
    atom_string(R, RS),
    number_string(L, LS), integer(L),
    number_string(N, NS), integer(N), N >= 0,
    number_string(Secs, SecsS), Secs >= 0,
    !.
timing(Line, _) :-
    throw(pppc(bench(bad_timing(Line)))).

                 /*******************************
                 *            SIZES             *
                 *******************************/

%!  read_sizes(+File, -Sizes) is det.
%
%   Sizes is a list Name-Overrides from the size(Name, Overrides) facts
%   of File, read as data. Overrides is a list of Constant=Value with
%   Value a number, true or false. Throws
%   pppc(bench(bad_sizes(File, Culprit))) with Culprit cannot_open,
%   syntax_error(What), duplicate(Name) or the offending term.
read_sizes(File, Sizes) :-
    catch(setup_call_cleanup(open(File, read, S),
                             read_all(S, Terms),
                             close(S)),
          E, sizes_error(File, E)),
    foldl(add_size(File), Terms, [], Sizes0),
    reverse(Sizes0, Sizes).

read_all(S, Terms) :-
    read_term(S, T, []),
    (   T == end_of_file
    ->  Terms = []
    ;   Terms = [T|Ts],
        read_all(S, Ts)
    ).

sizes_error(File, error(syntax_error(What), _)) :- !,
    throw(pppc(bench(bad_sizes(File, syntax_error(What))))).
sizes_error(File, error(existence_error(source_sink, _), _)) :- !,
    throw(pppc(bench(bad_sizes(File, cannot_open)))).
sizes_error(_, E) :-
    throw(E).

add_size(File, T, Sizes, [Name-Os|Sizes]) :-
    (   ground(T), T = size(Name, Os), atom(Name),
        is_list(Os), maplist(override, Os)
    ->  (   memberchk(Name-_, Sizes)
        ->  throw(pppc(bench(bad_sizes(File, duplicate(Name)))))
        ;   true
        )
    ;   throw(pppc(bench(bad_sizes(File, T))))
    ).

override(N=V) :-
    atom(N),
    ( number(V) ; V == true ; V == false ),
    !.

                 /*******************************
                 *          SUMMARIES           *
                 *******************************/

%!  speedup_rows(+Results, -Rows) is det.
%
%   One row(Name, SerialSeconds, Predicted, Actual) per benchmark, where
%   Predicted and Actual are lists P-Speedup over the thread counts
%   (Speedup is `none` if there is no value) and SerialSeconds is the
%   median serial wall time.
speedup_rows(Results, Rows) :-
    maplist(speedup_row(Results.threads), Results.programs, Rows).

speedup_row(Ps, Prog, row(Prog.name, Serial, Pred, Actual)) :-
    median_wall(Prog.runs, serial, 1, Serial),
    maplist(predicted_speedup(Prog.speedups), Ps, Pred),
    maplist(actual_speedup(Prog.runs, Serial), Ps, Actual).

predicted_speedup(Speedups, P, P-S) :-
    (   memberchk(P-S0, Speedups)
    ->  S is float(S0)
    ;   S = none
    ).

actual_speedup(Runs, Serial, P, P-S) :-
    (   median_wall(Runs, parallel, P, T), T > 0
    ->  S is Serial / T
    ;   S = none
    ).

median_wall(Runs, Mode, P, T) :-
    findall(W, member(run(Mode, P, W, _), Runs), Ws),
    median(Ws, T).

%!  loop_rows(+Results, +P, -Rows) is det.
%
%   One loop(Name, Routine, Line, PredSerial, PredPar, Serial, Par) per
%   candidate loop of each benchmark at P threads: predicted and
%   measured time of one execution in seconds. A measured time is
%   `none` if the loop never ran.
loop_rows(Results, P, Rows) :-
    findall(Row, ( member(Prog, Results.programs),
                   loop_row(Prog, P, Row) ),
            Rows).

loop_row(Prog, P, loop(Prog.name, R, L, PS, PP, S, Par)) :-
    memberchk(P-Times, Prog.loops),
    member(loop_time(R, L, PS0, PP0), Times),
    PS is PS0 * Prog.unit,
    PP is PP0 * Prog.unit,
    per_execution(Prog.runs, serial, 1, R-L, S),
    per_execution(Prog.runs, all, P, R-L, Par).

%   per_execution(+Runs, +Mode, +P, +Key, -Secs): the median over the
%   runs of the loop's mean time per execution.
per_execution(Runs, Mode, P, R-L, Secs) :-
    findall(T, ( member(run(Mode, P, _, Ts), Runs),
                 memberchk(R-L-N-Total, Ts),
                 N > 0,
                 T is Total / N ),
            Xs),
    (   median(Xs, Secs)
    ->  true
    ;   Secs = none
    ).

median(Xs0, M) :-
    msort(Xs0, Xs),
    length(Xs, N),
    N > 0,
    Mid is N // 2,
    (   N mod 2 =:= 1
    ->  nth0(Mid, Xs, M)
    ;   Lo is Mid - 1, nth0(Lo, Xs, A), nth0(Mid, Xs, B),
        M is (A + B) / 2
    ).

                 /*******************************
                 *            OUTPUT            *
                 *******************************/

%!  write_results(+Stream, +Results, +Notes:string) is det.
%
%   Write Results as markdown, ending with the notes marker and Notes.
write_results(S, Results, Notes) :-
    format(S, "# PPPC benchmark results~n~n", []),
    format(S, "- Date: ~w~n- CPU: ~w~n- gcc: ~w (-O2 -fopenmp)~n",
           [Results.date, Results.cpu, Results.gcc]),
    shown_path(Results.cost, Cost),
    atomic_list_concat(Results.threads, ', ', Threads),
    format(S, "- Cost table: ~w~n- Threads: ~w~n- Each time is the median of ~d runs~n~n",
           [Cost, Threads, Results.repeat]),
    format(S, "| Program | Sizes |~n|---|---|~n", []),
    forall(member(Prog, Results.programs),
           ( sizes_text(Prog.sizes, T),
             format(S, "| ~w | ~w |~n", [Prog.name, T]) )),
    write_speedups(S, Results),
    loop_points(Results.threads, LoopPs),
    forall(member(P, LoopPs), write_loops(S, Results, P)),
    format(S, "~n<!-- notes -->~n", []),
    format(S, "~s", [Notes]).

%   shown_path(+File, -Shown): File relative to the working directory
%   if it is inside it, so committed results hold no machine-specific
%   path; otherwise File as given.
shown_path(File, Shown) :-
    (   is_absolute_file_name(File),
        working_directory(Dir, Dir),
        atom_concat(Dir, Rel, File),
        Rel \== ''
    ->  Shown = Rel
    ;   Shown = File
    ).

sizes_text(Os, Text) :-
    maplist([N=V, T]>>format(string(T), "~w=~w", [N, V]), Os, Ts),
    atomic_list_concat(Ts, ', ', Text).

write_speedups(S, Results) :-
    Ps = Results.threads,
    speedup_rows(Results, Rows),
    format(S, "~n## Speedups (Table 4.1)~n~n", []),
    format(S, "| Program | | Serial (s) |", []),
    forall(member(P, Ps), format(S, " P=~d |", [P])),
    format(S, "~n|---|---|---:|", []),
    forall(member(_, Ps), format(S, "---:|", [])),
    nl(S),
    forall(member(row(Name, Serial, Pred, Actual), Rows),
           ( format(S, "| ~w | Predicted | ~2f |", [Name, Serial]),
             forall(member(_-X, Pred), cell(S, X)),
             format(S, "~n| | Actual | |", []),
             forall(member(_-X, Actual), cell(S, X)),
             nl(S) )).

cell(S, none) :- !, format(S, " - |", []).
cell(S, X) :- format(S, " ~2f |", [X]).

write_loops(S, Results, P) :-
    loop_rows(Results, P, Rows),
    format(S, "~n## Loops at P=~d~n~n", [P]),
    format(S, "Time of one execution of each candidate loop, in µs. \c
               Actual parallel times are from the build with every \c
               candidate loop parallel.~n~n", []),
    format(S, "| Program | Loop | Predicted serial | Predicted parallel | \c
               Actual serial | Actual parallel | Predicted | Actual | Agree |~n", []),
    format(S, "|---|---|---:|---:|---:|---:|---|---|---|~n", []),
    foldl(write_loop(S), Rows, 0-0, Right-Known),
    length(Rows, N),
    format(S, "~nVerdict right for ~d of ~d candidate loops at P=~d", [Right, Known, P]),
    (   Known < N
    ->  Missing is N - Known,
        format(S, " (~d not run)", [Missing])
    ;   true
    ),
    format(S, ".~n", []).

write_loop(S, loop(Name, R, L, PS, PP, AS, AP), Right0-Known0, Right-Known) :-
    verdict(PS, PP, PV),
    verdict(AS, AP, AV),
    (   AV == none
    ->  Agree = '-', Right = Right0, Known = Known0
    ;   PV == AV
    ->  Agree = yes, Right is Right0 + 1, Known is Known0 + 1
    ;   Agree = no, Right = Right0, Known is Known0 + 1
    ),
    format(S, "| ~w | ~w ~d |", [Name, R, L]),
    maplist(us_cell(S), [PS, PP, AS, AP]),
    maplist(verdict_text, [PV, AV], [PT, AT]),
    format(S, " ~w | ~w | ~w |~n", [PT, AT, Agree]).

verdict_text(none, '-') :- !.
verdict_text(V, V).

verdict(S, P, none) :- ( S == none ; P == none ), !.
verdict(S, P, parallel) :- P < S, !.
verdict(_, _, serial).

us_cell(S, none) :- !, format(S, " - |", []).
us_cell(S, Secs) :- Us is Secs * 1.0e6, format(S, " ~1f |", [Us]).

%!  notes(+File, -Notes:string) is det.
%
%   The text after the line holding the notes marker in File (the rest
%   of that line, such as a CR or trailing spaces, is dropped), or "\n"
%   if File does not exist or has no marker.
notes(File, Notes) :-
    (   exists_file(File),
        read_file_to_string(File, Text, []),
        once(sub_string(Text, B, L, _, "<!-- notes -->")),
        End is B + L,
        sub_string(Text, End, _, 0, Rest),
        once(sub_string(Rest, NL, 1, _, "\n"))
    ->  Start is NL + 1,
        sub_string(Rest, Start, _, 0, Notes)
    ;   Notes = "\n"
    ).
