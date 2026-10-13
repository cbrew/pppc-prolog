:- use_module(library(pppc)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(filesex)).
:- use_module(library(apply)).
:- use_module(library(lists)).

/** <module> End-to-end tests

Run from the project root inside the devenv shell: make check

For every program in test/programs and test/programs/negative:

  1. the --report output equals the checked-in .report file;
  2. the serial and parallel C build with gcc -O2 -fopenmp;
  3. the parallel binary run with OMP_NUM_THREADS=1 and 4 prints the
     same as the serial binary (numbers within a relative tolerance
     of 1e-9), except montepi, whose result must be within 0.01 of pi.
*/

:- begin_tests(e2e).

%   program(-Pas) enumerates the test programs. Paths are relative to
%   the project root, where `make check` runs.
program(Pas) :-
    member(Dir, ['test/programs', 'test/programs/negative']),
    directory_files(Dir, Fs), msort(Fs, Sorted),
    member(F, Sorted), file_name_extension(_, pas, F),
    directory_file_path(Dir, F, Pas).

test(report, [forall(program(Pas))]) :-
    pppc_report(Pas, Lines),
    file_name_extension(Base, pas, Pas),
    file_name_extension(Base, report, Expected),
    read_file_to_string(Expected, Text, []),
    split_string(Text, "\n", "", Parts), exclude(==(""), Parts, ExpectedLines),
    assertion(Lines == ExpectedLines).

test(run, [forall(program(Pas))]) :-
    build(Pas, serial, Serial),
    build(Pas, parallel, Parallel),
    run(Serial, 1, Reference),
    run(Parallel, 1, Out1),
    run(Parallel, 4, Out4),
    file_base_name(Pas, File), file_name_extension(Name, _, File),
    check(Name, Reference, Out1),
    check(Name, Reference, Out4).

build(Pas, Mode, Exe) :-
    file_base_name(Pas, File), file_name_extension(Name, _, File),
    make_directory_path('build/e2e'),
    format(atom(C), 'build/e2e/~w_~w.c', [Name, Mode]),
    format(atom(Exe), 'build/e2e/~w_~w', [Name, Mode]),
    ( Mode == serial -> Opts = [serial(true)] ; Opts = [] ),
    pppc_compile(Pas, Opts, Code),
    setup_call_cleanup(open(C, write, S), write(S, Code), close(S)),
    process_create(path(gcc), ['-O2', '-Wall', '-Werror', '-fopenmp', C, '-o', Exe, '-lm'],
                   [stderr(pipe(Err)), process(Pid)]),
    read_string(Err, _, Diag), close(Err),
    process_wait(Pid, Status),
    assertion(Status-Diag == exit(0)-"").

run(Exe, Threads, Output) :-
    process_create(Exe, [], [ stdout(pipe(Out)), process(Pid),
                              environment(['OMP_NUM_THREADS'=Threads]) ]),
    read_string(Out, _, Output), close(Out),
    process_wait(Pid, Status),
    assertion(Status == exit(0)).

check(montepi, _, Out) :- !,
    last_number(Out, Pi),
    assertion(abs(Pi - pi) < 0.01).
check(_, Reference, Out) :-
    split_string(Reference, " \n", " \n", Ws1),
    split_string(Out, " \n", " \n", Ws2),
    assertion(maplist(same_word, Ws1, Ws2)).

same_word(W, W) :- !.
same_word(W1, W2) :-
    number_string(X, W1), number_string(Y, W2),
    abs(X - Y) =< 1.0e-9 * max(abs(X), abs(Y)).

last_number(Out, N) :-
    split_string(Out, " \n", " \n", Ws),
    include([W]>>number_string(_, W), Ws, Ns),
    last(Ns, Last), number_string(N, Last).

:- end_tests(e2e).
