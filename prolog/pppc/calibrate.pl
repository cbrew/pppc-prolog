:- module(pppc_calibrate,
          [ calibrate/2,                % +Options, -Facts
            calibration_options/2,      % +Options0, -Options
            calibration_c/2,            % +Options, -CText
            parse_output/2,             % +Text, -Samples
            normalise/3,                % +Samples, +Options, -Facts
            write_table/3               % +Stream, +Facts, +Options
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(pairs)).
:- use_module(library(pppc/cost)).
:- use_module(library(pppc/codegen)).
:- use_module(library(pppc/semantic), []).

/** <module> Measure a target cost table

Produces the cost table of pppc_cost on the machine it runs on, as the
paper's "special program, which measures the time needed for the
operations" (section 4.3.4) did:

  1. generate one C program that times every probe: a loop whose body
     repeats one operation of the cost table U times;
  2. build it with gcc -O2 -fopenmp and run it, with library(process);
  3. normalise: the time of one operation is the difference between
     the runs with U = 12 and U = 4, divided by 8 (which cancels the
     loop overhead), in units of one integer addition; take the median
     of the runs.

The expression probes are typed tree nodes turned into C by codegen's
c_expr/2, so they time exactly the C the compiler emits. Operators are
timed as a dependent chain (each result is the next operand), so they
cost their latency and one integer addition is one cycle. Inline asm
barriers between the copies stop gcc folding the chain or removing
the work.

Options: max_threads(N) (default: the number of CPUs), repeat(K)
(default 5), iterations(I) (default 1000000), reps(R), the repetitions
of each OpenMP region (default 2000).
*/

%!  calibrate(+Options, -Facts) is det.
%
%   Measure this machine. Throws pppc(calibrate(Why)) if the C program
%   cannot be built or its output cannot be read.
calibrate(Options0, Facts) :-
    calibration_options(Options0, Options),
    calibration_c(Options, C),
    run_c(C, Options, Output),
    parse_output(Output, Samples),
    normalise(Samples, Options, Facts).

%!  calibration_options(+Options0, -Options) is det.
%
%   Options0 completed with the defaults.
calibration_options(Options0, Options) :-
    current_prolog_flag(cpu_count, CPUs),
    merge_options(Options0,
                  [max_threads(CPUs), repeat(5), iterations(1000000), reps(2000)],
                  Options).

%   The two unroll counts, and the divisor of the iterations for the
%   (slow) output probe.
unrolls(4, 12).
write_divisor(64).

                 /*******************************
                 *            PROBES            *
                 *******************************/

%   probe(?Entry, -Decls, -Copy) enumerates the probes in a fixed order.
%   Entry is the cost table entry measured (see required_entry/1), or
%   call1 (a call with one argument, from which param is derived).
%   Decls lists the Name-Type locals the probe uses (the first is the
%   chain variable). Copy is one copy of the operation:
%
%     - chain(E): p_a = E, so each copy depends on the last;
%     - free(E):  r = E on unchanged operands;
%     - c(Text):  C statements.

probe(unit(loop), [], c("PPPC_BAR_long(k);")).   % or gcc deletes the loop
probe(op2(Op/T/T), [a-T, b-T], chain(op2(0, [Op, id(0, [a], T), id(0, [b], T)], R))) :-
    required_entry(op2(Op/T/T)),
    pppc_semantic:op2_rule(Op, T, T, R).
probe(op1(Op/T), [a-T], chain(op1(0, [Op, id(0, [a], T)], T))) :-
    required_entry(op1(Op/T)).
probe(func(F), Decls, free(builtin(0, [F, Args], R))) :-
    required_entry(func(F)),
    once(pppc_semantic:builtin_sig(F, ArgTypes, R)),
    func_args(ArgTypes, Decls, Args).
probe(unit(index), [a-integer],
      chain(index(0, [id(0, [v], array(1, 1024, integer)), id(0, [a], integer)], integer))).
probe(unit(itor), [a-integer], free(itor(0, [id(0, [a], integer)], real))).
probe(unit(store), [a-integer], c("p_s = p_a; PPPC_BAR_MEM(p_s); PPPC_BAR_long(p_a);")).
probe(unit(if), [c-boolean], c("if (p_c) __asm__ volatile(\"\"); PPPC_BAR_bool(p_c);")).
probe(unit(call), [], c("r = pppc_f0(); PPPC_BAR_long(r);")).
probe(call1, [a-integer], c("p_a = pppc_f1(p_a);")).
probe(unit(write_item), [a-integer], c("fprintf(pppc_null, \"%ld\", p_a);")).

func_args([], [], []).
func_args([T], [a-T], [id(0, [a], T)]).

probes(Probes) :-
    findall(p(E, D, C), probe(E, D, C), Probes).

                 /*******************************
                 *          C PROGRAM           *
                 *******************************/

%!  calibration_c(+Options, -CText:string) is det.
%
%   The C program. It is run as `prog Iterations Repeat MaxThreads
%   Reps` and prints, for each repetition, `probe K U Seconds` for every
%   probe K (counting from 0) and unroll count U, and `fork_join P
%   Seconds`, `reduction P Seconds` (seconds per OpenMP region) for P
%   in 1..MaxThreads.
calibration_c(_Options, C) :-
    probes(Probes),
    runtime_text(Runtime),
    unrolls(U1, U2),
    with_output_to(string(C),
                   ( write(Runtime),
                     write_prelude,
                     forall(nth0(K, Probes, P),
                            ( write_probe(K, U1, P), write_probe(K, U2, P) )),
                     write_main(Probes) )).

write_prelude :-
    format("~s", [
"
/* calibration harness */
#if defined(__x86_64__)
#define PPPC_FREG \"+x\"
#elif defined(__aarch64__)
#define PPPC_FREG \"+w\"
#else
#define PPPC_FREG \"+m\"
#endif
#define PPPC_BAR_long(v)   __asm__ volatile(\"\" : \"+r\"(v))
#define PPPC_BAR_bool(v)   __asm__ volatile(\"\" : \"+r\"(v))
#define PPPC_BAR_double(v) __asm__ volatile(\"\" : PPPC_FREG(v))
#define PPPC_BAR_MEM(v)    __asm__ volatile(\"\" : \"+m\"(v))

static volatile double pppc_sink;
static FILE *pppc_null;
static long p_s;
static struct { long e[1024]; } p_v;
__attribute__((noinline, noipa)) static long pppc_f0(void) { return 1; }
__attribute__((noinline, noipa)) static long pppc_f1(long a) { return a; }
"]).

write_probe(K, U, p(_, Decls, Copy)) :-
    copy_text(Copy, Decls, RType, Text),
    format("~nstatic double pppc_probe_~d_~d(long iters)~n{~n", [K, U]),
    forall(member(N-T, Decls),
           ( c_scalar(T, CT, Init), format("    ~w p_~w = ~w;~n", [CT, N, Init]) )),
    c_scalar(RType, RCT, _),
    format("    ~w r = 0;~n    double t0, t1;~n    long k;~n", [RCT]),
    format("    t0 = omp_get_wtime();~n    for (k = 0; k < iters; k++) {~n", []),
    forall(between(1, U, _), format("        ~s~n", [Text])),
    format("    }~n    t1 = omp_get_wtime();~n", []),
    forall(member(N-T, Decls), format("    pppc_sink += (double)p_~w;~n", [N])),
    format("    pppc_sink += (double)r;~n    return t1 - t0;~n}~n", []).

%   copy_text(+Copy, +Decls, -ResultType, -Text): one copy of the
%   operation, as C, and the type of r.
copy_text(chain(E), [A-T|_], integer, Text) :-
    c_expr(E, CE),
    c_scalar(T, CT, _),
    format(string(Text), "p_~w = ~s; PPPC_BAR_~w(p_~w);", [A, CE, CT, A]).
copy_text(free(E), Decls, RType, Text) :-
    arg(3, E, RType),
    c_expr(E, CE),
    c_scalar(RType, RCT, _),
    findall(B, ( member(N-T, Decls), c_scalar(T, CT, _),
                 format(string(B), " PPPC_BAR_~w(p_~w);", [CT, N]) ),
            Bars),
    atomic_list_concat(Bars, BarText),
    format(string(Text), "r = ~s; PPPC_BAR_~w(r);~w", [CE, RCT, BarText]).
copy_text(c(Text), _, integer, Text).

%   c_scalar(Type, CType, Initial value). The values keep every chain
%   finite: a / b, a div b and a mod b stay put with b = 1.
c_scalar(integer, long, '7').
c_scalar(real, double, '1.5').
c_scalar(boolean, bool, true).

write_main(Probes) :-
    length(Probes, N),
    unrolls(U1, U2),
    write_divisor(D),
    format("~nstatic double (*const pppc_probes[~d][2])(long) = {", [N]),
    forall(between(1, N, K1),
           ( K is K1 - 1,
             format("~n    { pppc_probe_~d_~d, pppc_probe_~d_~d },", [K, U1, K, U2]) )),
    format("~n};~n", []),
    nth0(W, Probes, p(unit(write_item), _, _)), !,
    format("static const long pppc_unroll[2] = { ~d, ~d };~n", [U1, U2]),
    format("static const long pppc_write_probe = ~d, pppc_write_divisor = ~d;~n", [W, D]),
    format("~s", [
"
static double pppc_region(int p, long reps, int reduce)
{
    double s = 0, t0 = omp_get_wtime();
    for (long k = 0; k < reps; k++) {
        if (reduce) {
            #pragma omp parallel for num_threads(p) reduction(+:s)
            for (long i = 0; i < p; i++) s += 1.0;
        } else {
            #pragma omp parallel for num_threads(p)
            for (long i = 0; i < p; i++) __asm__ volatile(\"\");
        }
    }
    pppc_sink += s;
    return (omp_get_wtime() - t0) / reps;
}

int main(int argc, char **argv)
{
    if (argc != 5) return 2;
    long iters = atol(argv[1]), reps = atol(argv[4]);
    int repeat = atoi(argv[2]), maxp = atoi(argv[3]);
    long n = sizeof pppc_probes / sizeof pppc_probes[0];
    for (long k = 0; k < 1024; k++) p_v.e[k] = k + 1;   /* p_v.e[a - 1] == a */
    pppc_null = fopen(\"/dev/null\", \"w\");
    if (!pppc_null) return 2;
    pppc_region(maxp, reps, 0);              /* start the threads */
    pppc_probes[0][0](iters);                /* warm up */
    for (int r = 0; r < repeat; r++) {
        for (long k = 0; k < n; k++) {
            long it = k == pppc_write_probe ? iters / pppc_write_divisor : iters;
            for (int u = 0; u < 2; u++)
                printf(\"probe %ld %ld %.9e\\n\", k, pppc_unroll[u], pppc_probes[k][u](it));
        }
        for (int p = 1; p <= maxp; p++) {
            printf(\"fork_join %d %.9e\\n\", p, pppc_region(p, reps, 0));
            printf(\"reduction %d %.9e\\n\", p, pppc_region(p, reps, 1));
        }
    }
    return 0;
}
"]).

                 /*******************************
                 *        BUILD AND RUN         *
                 *******************************/

run_c(C, Options, Output) :-
    tmp_file(pppc_calibrate, Base),
    file_name_extension(Base, c, Src),
    call_cleanup(
        ( setup_call_cleanup(open(Src, write, S), write(S, C), close(S)),
          build(Src, Base),
          run(Base, Options, Output) ),
        ( catch(delete_file(Src), _, true),
          catch(delete_file(Base), _, true) )).

build(Src, Exe) :-
    catch(process_create(path(gcc), ['-O2', '-fopenmp', '-o', Exe, Src, '-lm'],
                         [stdout(null), stderr(pipe(E)), process(Pid)]),
          error(existence_error(_, _), _),
          throw(pppc(calibrate(no_compiler)))),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    (   Status == exit(0)
    ->  true
    ;   throw(pppc(calibrate(build_failed(Err))))
    ).

run(Exe, Options, Output) :-
    option(iterations(I), Options),
    option(repeat(K), Options),
    option(max_threads(P), Options),
    option(reps(R), Options),
    maplist(to_atom, [I, K, P, R], Args),
    process_create(Exe, Args,
                   [stdout(pipe(O)), process(Pid)]),
    read_string(O, _, Output), close(O),
    process_wait(Pid, Status),
    (   Status == exit(0)
    ->  true
    ;   throw(pppc(calibrate(run_failed(Status))))
    ).

to_atom(X, A) :-
    format(atom(A), '~w', [X]).

                 /*******************************
                 *          NORMALISE           *
                 *******************************/

%!  parse_output(+Text, -Samples) is det.
%
%   Samples is a list of Key-Seconds, Key one of probe(K, U),
%   fork_join(P), reduction(P). Throws pppc(calibrate(bad_output(Line)))
%   on a line of another form.
parse_output(Text, Samples) :-
    split_string(Text, "\n", "", Lines0),
    exclude(==(""), Lines0, Lines),
    maplist(sample, Lines, Samples).

sample(Line, Key-Secs) :-
    split_string(Line, " ", "", Fields),
    append([KindS|ArgSs], [SecsS], Fields),
    atom_string(Kind, KindS),
    maplist(integer_string, Args, ArgSs),
    number_string(Secs, SecsS), number(Secs),
    Key =.. [Kind|Args],
    memberchk(Key, [probe(_, _), fork_join(_), reduction(_)]),
    !.
sample(Line, _) :-
    throw(pppc(calibrate(bad_output(Line)))).

integer_string(N, S) :-
    number_string(N, S),
    integer(N).

%!  normalise(+Samples, +Options, -Facts) is det.
%
%   Turn timings into cost table facts. An operation's time is the
%   median over the runs of (time at U2 - time at U1) / (U2 - U1) /
%   iterations; every cost is that time divided by the integer
%   addition's, rounded, at least 1. cost(loop) is one iteration of
%   the empty loop, cost(param) the extra time of a call with one
%   argument. Options gives iterations(I).
normalise(Samples, Options, Facts) :-
    option(iterations(I), Options),
    probes(Probes),
    findall(E-T, ( nth0(K, Probes, p(E, _, _)), op_time(Samples, K, E, I, T) ), Times),
    memberchk(op2((+)/integer/integer)-Add, Times),
    (   Add > 0
    ->  true
    ;   throw(pppc(calibrate(no_signal)))
    ),
    nth0(KL, Probes, p(unit(loop), _, _)), !,
    unrolls(U1, _),
    median(Samples, probe(KL, U1), LoopSecs),
    Loop is LoopSecs / I,
    memberchk(unit(call)-Call, Times),
    memberchk(call1-Call1, Times),
    findall(F, ( member(E-T, Times), entry_fact(E, T, Loop, Call, Call1, Add, F) ),
            Ops),
    findall(F, overhead_fact(Samples, Add, F), Overheads),
    append([Ops, [default_trips(25)], Overheads], Facts0),
    order_facts(Facts0, Facts).

op_time(Samples, K, E, I, T) :-
    unrolls(U1, U2),
    (   E == unit(write_item)
    ->  write_divisor(D), It is I // D
    ;   It = I
    ),
    findall(T1, ( member(probe(K, U1)-S1, Samples), T1 = S1 ), S1s),
    findall(T2, ( member(probe(K, U2)-S2, Samples), T2 = S2 ), S2s),
    pairs_keys_values(Pairs, S1s, S2s),
    findall(D1, ( member(A-B, Pairs), D1 is (B - A) / ((U2 - U1) * It) ), Ds),
    median_list(Ds, T).

entry_fact(unit(loop), _, Loop, _, _, Add, cost(loop, C)) :- !,
    units(Loop, Add, C).
entry_fact(call1, _, _, Call, Call1, Add, cost(param, C)) :- !,
    units(Call1 - Call, Add, C).
entry_fact(E, T, _, _, _, Add, Fact) :-
    units(T, Add, C),
    entry_term(E, C, Fact).

entry_term(op2(Op/L/R), C, cost_op2(Op, L, R, C)).
entry_term(op1(Op/T), C, cost_op1(Op, T, C)).
entry_term(func(F), C, cost_func(F, C)).
entry_term(unit(K), C, cost(K, C)).

overhead_fact(Samples, Add, overhead(fork_join, P, C)) :-
    fork_join_points(Samples, Ps),
    member(P, Ps),
    median(Samples, fork_join(P), T),
    units(T, Add, C).
overhead_fact(Samples, Add, overhead(reduction, P, C)) :-
    fork_join_points(Samples, Ps),
    member(P, Ps),
    median(Samples, fork_join(P), T0),
    median(Samples, reduction(P), T1),
    units(T1 - T0, Add, C).

fork_join_points(Samples, Ps) :-
    findall(P, member(fork_join(P)-_, Samples), Ps0),
    sort(Ps0, Ps).

units(T, Add, C) :-
    C is max(1, round(T / Add)).

median(Samples, Key, M) :-
    findall(S, member(Key-S, Samples), Ss),
    median_list(Ss, M).

median_list(Xs0, M) :-
    msort(Xs0, Xs),
    length(Xs, N),
    N > 0,
    Mid is N // 2,
    (   N mod 2 =:= 1
    ->  nth0(Mid, Xs, M)
    ;   Lo is Mid - 1, nth0(Lo, Xs, A), nth0(Mid, Xs, B),
        M is (A + B) / 2
    ).

%   Facts in the order of the table format: operators, functions,
%   cost/2, default_trips, overheads.
order_facts(Facts0, Facts) :-
    map_list_to_pairs(fact_rank, Facts0, Ranked),
    keysort(Ranked, Sorted),
    pairs_values(Sorted, Facts).

fact_rank(cost_op2(_, _, _, _), 1).
fact_rank(cost_op1(_, _, _), 2).
fact_rank(cost_func(_, _), 3).
fact_rank(cost(_, _), 4).
fact_rank(default_trips(_), 5).
fact_rank(overhead(_, _, _), 6).

                 /*******************************
                 *            OUTPUT            *
                 *******************************/

%!  write_table(+Stream, +Facts, +Options) is det.
%
%   Write Facts as a cost table file, after a header comment recording
%   the machine and the options.
write_table(S, Facts, Options) :-
    get_time(Now),
    format_time(atom(Date), '%F %T', Now),
    cpu_model(CPU),
    gcc_version(GCC),
    format(S, "/*  PPPC cost table, measured by pppc_calibrate~n~n", []),
    format(S, "    Date:    ~w~n    CPU:     ~w~n    gcc:     ~w (-O2 -fopenmp)~n",
           [Date, CPU, GCC]),
    format(S, "    Options: ~q~n~n", [Options]),
    format(S, "    Costs are in units of one integer addition.~n*/~n~n", []),
    forall(member(F, Facts), portray_clause(S, F)).

cpu_model(Model) :-
    catch(read_file_to_string('/proc/cpuinfo', Text, []), _, fail),
    split_string(Text, "\n", "", Lines),
    member(L, Lines),
    string_concat("model name", Rest, L),
    split_string(Rest, ":", " \t", [_, Model|_]),
    !.
cpu_model(unknown).

gcc_version(V) :-
    catch(( process_create(path(gcc), ['-dumpfullversion'],
                           [stdout(pipe(O)), process(Pid)]),
            read_string(O, _, S), close(O), process_wait(Pid, _) ),
          _, fail),
    split_string(S, "", " \n", [V]),
    !.
gcc_version(unknown).
