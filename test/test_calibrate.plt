:- use_module(library(pppc/calibrate)).
:- use_module(library(pppc/cost)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(apply)).
:- use_module(library(lists)).

/*  Calibration without live timings, except calibrate_smoke, which
    runs a very short real calibration and checks only that the
    result is a valid table. */

:- begin_tests(calibrate).

test(generated_c_compiles) :-
    calibration_c([], C),
    tmp_file_stream(text, Src0, S0), close(S0),
    file_name_extension(Src0, c, Src),
    setup_call_cleanup(open(Src, write, S), write(S, C), close(S)),
    file_name_extension(Exe, _, Src),
    process_create(path(gcc), ['-O2', '-fopenmp', '-o', Exe, Src, '-lm'],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status-Err == exit(0)-"").

test(parse_output) :-
    parse_output("probe 0 4 1.5e-3\nprobe 0 12 2.5e-3\nfork_join 2 1.0e-6\n\c
                  reduction 2 1.25e-6\n", Samples),
    assertion(Samples == [probe(0, 4)-1.5e-3, probe(0, 12)-2.5e-3,
                          fork_join(2)-1.0e-6, reduction(2)-1.25e-6]).

test(bad_output, throws(pppc(calibrate(bad_output("hello world"))))) :-
    parse_output("probe 0 4 1.5e-3\nhello world\n", _).

%   Canned timings for I = 64000 iterations: every operation takes
%   2 ns except integer addition (1 ns), the empty loop takes 3 ns per
%   iteration, and calls take the same with or without an argument.
%   A probe at unroll count U takes U * T * Iterations seconds, plus
%   a constant 1 ms that the difference cancels.
canned(Samples) :-
    I = 64000,
    pppc_calibrate:probes(Probes),
    findall(Key-Secs,
            ( nth0(K, Probes, p(E, _, _)),
              member(U, [4, 12]),
              op_ns(E, T),
              ( E == unit(write_item) -> It is I // 64 ; It = I ),
              Secs is 1.0e-3 + U * T * 1.0e-9 * It,
              Key = probe(K, U) ),
            Ops),
    Over = [ fork_join(1)-5.0e-6, reduction(1)-5.5e-6,
             fork_join(2)-8.0e-6, reduction(2)-9.0e-6 ],
    append(Ops, Over, Samples).

op_ns(op2((+)/integer/integer), 1) :- !.
op_ns(unit(loop), 0) :- !.           % its U = 4 run is 3 ns * I, below
op_ns(_, 2).

test(normalise) :-
    canned(Samples0),
    % the empty loop: 1 ms + 3 ns * I at U = 4 is not canned by op_ns;
    % replace its U = 4 sample
    pppc_calibrate:probes(Probes),
    once(nth0(KL, Probes, p(unit(loop), _, _))),
    selectchk(probe(KL, 4)-_, Samples0, Samples1),
    Loop is 3.0e-9 * 64000,
    Samples = [probe(KL, 4)-Loop|Samples1],
    normalise(Samples, [iterations(64000)], Facts),
    forall(member(F, [ cost_op2(+, integer, integer, 1), cost_op2(*, real, real, 2),
                       cost_func(sin, 2), cost(loop, 3), cost(param, 1),
                       cost(write_item, 2), default_trips(25),
                       overhead(fork_join, 1, 5000), overhead(reduction, 1, 500),
                       overhead(fork_join, 2, 8000), overhead(reduction, 2, 1000) ]),
           assertion(memberchk(F, Facts))).

test(written_table_loads) :-
    canned(Samples),
    normalise(Samples, [iterations(64000)], Facts),
    tmp_file_stream(text, File, S),
    write_table(S, Facts, [iterations(64000)]),
    close(S),
    load_cost_table(File, Table),
    overhead(Table, fork_join, 2, C),
    assertion(C == 8000).

test(calibrate_smoke) :-
    calibrate([max_threads(2), repeat(3), iterations(200000), reps(50)], Facts),
    tmp_file_stream(text, File, S),
    write_table(S, Facts, []),
    close(S),
    load_cost_table(File, _).

:- end_tests(calibrate).
