:- module(pppc_predict,
          [ decide/5                    % +Routines0, +Table, +N, -Routines, -Prediction
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pppc/cost)).

/** <module> Run time prediction and the profitability decision

Implements section 4.3.4 of the paper: the predicted execution time
of a routine body, computed bottom-up over its labelled statements
with the costs of a target cost table (pppc_cost), and the decision
to parallelize an eligible loop only if that is predicted to be
faster.

Times are exact rationals (`rdiv`), so the mean of two branches stays
exact; they are rounded only for display.

Costing predicates take an environment

    env(Table, Routines, Mode, Routine, Stack)

where Routines is the analysed program (pppc_transform's
routine(Name, Labelled, Loops, Reach) list), Mode is `serial` or
par(P, Chosen) (Chosen lists Routine/Label-Reductions for every loop
run in parallel), Routine is the routine whose body is being costed
and Stack the routines whose costing is in progress (to stop at
recursion).
*/

%!  decide(+Routines0, +Table, +N, -Routines, -Prediction) is det.
%
%   Routines is Routines0 with every `parallel` loop whose predicted
%   parallel time at N threads is not less than its serial time
%   changed to serial([unprofitable(Serial, Parallel)]) (times rounded
%   to integers). Prediction is
%
%       prediction(Loops, Serial, Speedups)
%
%   Loops has loop_time(Routine, Line, SerialTime, ParallelTimeAtN) for
%   each loop that was `parallel` in Routines0, Serial is the
%   program's predicted serial time and Speedups is [1-S1, ..., N-SN].
decide(Rs0, Table, N, Rs, prediction(Times, Serial, Speedups)) :-
    maplist(decide_routine(Table, Rs0, N), Rs0, Rs, Timess),
    append(Timess, Times),
    findall(R/P-NR, ( member(routine(R, _, Loops, _), Rs),
                      member(loop(P, _, parallel, Classes), Loops),
                      reductions(Classes, NR) ),
            Chosen),
    program_time(Table, Rs0, serial, Serial),
    numlist(1, N, Ps),
    maplist(speedup(Table, Rs0, Chosen, Serial), Ps, Speedups).

decide_routine(Table, Rs, N, routine(Name, LSs, Loops0, Reach),
               routine(Name, LSs, Loops, Reach), Times) :-
    Env = env(Table, Rs, serial, Name, [Name]),
    foldl(decide_loop(Env, Name, LSs, N), Loops0, Loops, Times, []).

decide_loop(Env, Name, LSs, N, loop(P, L, parallel, Classes), Loop) -->
    !,
    { once(sub_term(lbl(P, For), LSs)),
      stmt_time(Env, lbl(P, For), S),
      reductions(Classes, NR),
      parallel_for_time(Env, For, N, NR, Par),
      (   Par < S
      ->  Loop = loop(P, L, parallel, Classes)
      ;   SR is round(S), PR is round(Par),
          Loop = loop(P, L, serial([unprofitable(SR, PR)]), Classes)
      )
    },
    [loop_time(Name, L, S, Par)].
decide_loop(_, _, _, _, Loop, Loop) --> [].

reductions(Classes, N) :-
    aggregate_all(count, member(_-associative(_), Classes), N).

speedup(Table, Rs, Chosen, Serial, P, P-S) :-
    program_time(Table, Rs, par(P, Chosen), T),
    (   T =:= 0
    ->  S = 1
    ;   S is Serial rdiv T
    ).

program_time(Table, Rs, Mode, T) :-
    routine_time(env(Table, Rs, Mode, program, []), program, T).

                 /*******************************
                 *          ROUTINES            *
                 *******************************/

%   routine_time(+Env, +Name, -Time): the predicted time of one
%   execution of the body of routine Name; 0 for a recursive call.
routine_time(env(Table, Rs, Mode, _, Stack), Name, T) :-
    (   memberchk(Name, Stack)
    ->  T = 0
    ;   memberchk(routine(Name, LSs, _, _), Rs),
        seq_time(env(Table, Rs, Mode, Name, [Name|Stack]), LSs, T)
    ).

call_time(Env, Name, Args, T) :-
    Env = env(Table, _, _, _, _),
    routine_time(Env, Name, TB),
    unit_cost(Table, call, Call),
    args_time(Env, Args, TA),
    T is TB + Call + TA.

%   args_time(+Env, +Args, -Time): evaluating and passing Args.
args_time(Env, Args, T) :-
    Env = env(Table, _, _, _, _),
    unit_cost(Table, param, Param),
    foldl(arg_time(Env, Param), Args, 0, T).

arg_time(Env, Param, A, T0, T) :-
    expr_time(Env, A, TA),
    T is T0 + TA + Param.

                 /*******************************
                 *          STATEMENTS          *
                 *******************************/

seq_time(Env, LSs, T) :-
    foldl(add_stmt(Env), LSs, 0, T).

add_stmt(Env, LS, T0, T) :-
    stmt_time(Env, LS, T1),
    T is T0 + T1.

%   stmt_time(+Env, +Labelled, -Time)
stmt_time(Env, lbl(P, S), T) :-
    Env = env(_, _, Mode, R, _),
    S = for(_, _, _), !,
    (   Mode = par(N, Chosen),
        memberchk(R/P-NR, Chosen)
    ->  parallel_for_time(Env, S, N, NR, T)
    ;   serial_for_time(Env, S, T)
    ).
stmt_time(Env, lbl(_, S), T) :-
    stmt(S, Env, T).

stmt(assign(_, [Target, E], _), Env, T) :-
    Env = env(Table, _, _, _, _),
    expr_time(Env, Target, T1),
    expr_time(Env, E, T2),
    arg(3, Target, Type),
    leaves(Type, N),
    unit_cost(Table, store, Store),
    T is T1 + T2 + N * Store.
stmt(zero_assign(_, [V], _), Env, T) :-
    Env = env(Table, _, _, _, _),
    expr_time(Env, V, T1),
    arg(3, V, Type),
    leaves(Type, N),
    unit_cost(Table, store, Store),
    T is T1 + N * Store.
stmt(if(_, [C, Then, Else], _), Env, T) :-
    Env = env(Table, _, _, _, _),
    expr_time(Env, C, TC),
    unit_cost(Table, if, If),
    stmt_time(Env, Then, TT),
    stmt_time(Env, Else, TE),
    T is TC + If + (TT + TE) rdiv 2.
stmt(while(_, [C, Body], _), Env, T) :-
    loop_time(Env, C, Body, T).
stmt(repeat(_, [Body, C], _), Env, T) :-
    loop_time(Env, C, Body, T).
stmt(compound(_, [LSs], _), Env, T) :-
    seq_time(Env, LSs, T).
stmt(pcall(_, [Name, Args], _), Env, T) :-
    call_time(Env, Name, Args, T).
stmt(write(_, [_, Args], _), Env, T) :-
    Env = env(Table, _, _, _, _),
    unit_cost(Table, write_item, W),
    foldl(arg_time(Env, W), Args, 0, T).
stmt(empty(_, _, _), _, 0).

%   while and repeat: default_trips iterations of body and condition.
loop_time(Env, C, Body, T) :-
    Env = env(Table, _, _, _, _),
    trips(Table, N),
    unit_cost(Table, loop, Loop),
    expr_time(Env, C, TC),
    seq_time(Env, Body, TB),
    T is N * (TB + TC + Loop).

serial_for_time(Env, for(_, [_, F, To, D, Body], _), T) :-
    for_parts(Env, F, To, D, Body, TBounds, Trips, TIter),
    T is TBounds + Trips * TIter.

%   parallel_for_time(+Env, +For, +P, +Reductions, -Time)
parallel_for_time(Env, for(_, [_, F, To, D, Body], _), P, NR, T) :-
    Env = env(Table, _, _, _, _),
    for_parts(Env, F, To, D, Body, TBounds, Trips, TIter),
    overhead(Table, fork_join, P, FJ),
    overhead(Table, reduction, P, Red),
    T is TBounds + ((Trips + P - 1) // P) * TIter + FJ + NR * Red.

for_parts(Env, F, To, D, Body, TBounds, Trips, TIter) :-
    Env = env(Table, _, _, _, _),
    expr_time(Env, F, TF),
    expr_time(Env, To, TT),
    TBounds is TF + TT,
    for_trips(Table, F, To, D, Trips),
    seq_time(Env, Body, TB),
    unit_cost(Table, loop, Loop),
    TIter is TB + Loop.

for_trips(_, iconst(_, [F], _), iconst(_, [T], _), D, N) :- !,
    (   D == up
    ->  N is max(0, T - F + 1)
    ;   N is max(0, F - T + 1)
    ).
for_trips(Table, _, _, _, N) :-
    trips(Table, N).

%   leaves(+Type, -N): the number of scalars in a value of Type.
leaves(array(Lo, Hi, E), N) :- !,
    leaves(E, NE),
    N is (Hi - Lo + 1) * NE.
leaves(record(Fs), N) :- !,
    foldl(add_leaves, Fs, 0, N).
leaves(_, 1).

add_leaves(_-T, N0, N) :-
    leaves(T, NT),
    N is N0 + NT.

                 /*******************************
                 *         EXPRESSIONS          *
                 *******************************/

%   expr_time(+Env, +Expr, -Time), after the paper's cost_expr/2.
expr_time(Env, E, T) :-
    Env = env(Table, _, _, _, _),
    expr(E, Env, Table, T).

expr(id(_, _, _), _, _, 0).
expr(vparam(_, _, _), _, _, 0).
expr(fresult(_, _, _), _, _, 0).
expr(iconst(_, _, _), _, _, 0).
expr(fconst(_, _, _), _, _, 0).
expr(bconst(_, _, _), _, _, 0).
expr(string(_, _, _), _, _, 0).
expr(op2(_, [Op, L, R], _), Env, Table, T) :-
    expr(L, Env, Table, TL),
    expr(R, Env, Table, TR),
    arg(3, L, TyL), arg(3, R, TyR),
    op2_cost(Table, Op, TyL, TyR, C),
    T is TL + TR + C.
expr(op1(_, [Op, E], _), Env, Table, T) :-
    expr(E, Env, Table, TE),
    arg(3, E, Ty),
    op1_cost(Table, Op, Ty, C),
    T is TE + C.
expr(itor(_, [E], _), Env, Table, T) :-
    expr(E, Env, Table, TE),
    unit_cost(Table, itor, C),
    T is TE + C.
expr(index(_, [A, I], _), Env, Table, T) :-
    expr(A, Env, Table, TA),
    expr(I, Env, Table, TI),
    unit_cost(Table, index, C),
    T is TA + TI + C.
expr(field(_, [R, _], _), Env, Table, T) :-
    expr(R, Env, Table, T).
expr(addr(_, [V], _), Env, Table, T) :-
    expr(V, Env, Table, T).
expr(builtin(_, [F, Args], _), Env, Table, T) :-
    func_cost(Table, F, C),
    args_time(Env, Args, TA),
    T is C + TA.
expr(fcall(_, [F, Args], _), Env, _, T) :-
    call_time(Env, F, Args, T).
