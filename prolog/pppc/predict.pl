:- module(pppc_predict,
          [ decide/5                    % +Routines0, +Table, +N, -Routines, -Prediction
          ]).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module(library(ugraphs)).
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

    env(Table, Routines, Times, Mode, Routine, Stack)

where Routines is the analysed program (pppc_transform's
routine(Name, Labelled, Loops, Reach) list), Times an assoc from the
routines not on a call cycle to the time of their body (each is costed
once, see routine_times/4), Mode is `serial` or par(P, Chosen) (Chosen
lists Routine/Label-Reductions for every loop run in parallel),
Routine is the routine whose body is being costed and Stack the
routines whose costing is in progress (to stop at recursion).
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
%   program's predicted serial time and Speedups is [1-S1, ..., N-SN],
%   for every P up to 8, then for powers of two, and for N.
decide(Rs0, Table, N, Rs, prediction(Times, Serial, Speedups)) :-
    routine_times(Table, Rs0, serial, STimes),
    maplist(decide_routine(Table, Rs0, STimes, N), Rs0, Rs, Timess),
    append(Timess, Times),
    findall(R/P-NR, ( member(routine(R, _, Loops, _), Rs),
                      member(loop(P, _, parallel, Classes), Loops),
                      reductions(Classes, NR) ),
            Chosen),
    get_assoc(program, STimes, Serial),
    speedup_points(N, Ps),
    maplist(speedup(Table, Rs0, Chosen, Serial), Ps, Speedups).

%   speedup_points(+N, -Ps): the thread counts the speedup is given for.
speedup_points(N, Ps) :-
    Low is min(N, 8),
    numlist(1, Low, Ps0),
    findall(P, ( between(4, 62, K), P is 2^K, P < N ), Ps1),
    (   N > 8
    ->  append([Ps0, Ps1, [N]], Ps)
    ;   Ps = Ps0
    ).

decide_routine(Table, Rs, RTimes, N, routine(Name, LSs, Loops0, Reach),
               routine(Name, LSs, Loops, Reach), Times) :-
    Env = env(Table, Rs, RTimes, serial, Name, [Name]),
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
    routine_times(Table, Rs, Mode, Times),
    get_assoc(program, Times, T).

                 /*******************************
                 *          ROUTINES            *
                 *******************************/

%   routine_times(+Table, +Routines, +Mode, -Times): Times maps every
%   routine that is not on a cycle of the call graph to the time of one
%   execution of its body. Nothing that calls such a routine can be
%   reached from it, so its time does not depend on which routines are
%   in progress: it is computed once, callees first, rather than at
%   every call (which takes time exponential in the call depth).
%   Routines on a cycle are costed at each call, by routine_time/3.
routine_times(Table, Rs, Mode, Times) :-
    call_graph(Rs, G),
    transitive_closure(G, Closure),
    findall(R, ( member(R-Reach, Closure), memberchk(R, Reach) ), Cyclic),
    del_vertices(G, Cyclic, Dag),
    top_sort(Dag, CallersFirst),
    reverse(CallersFirst, CalleesFirst),
    empty_assoc(T0),
    foldl(add_routine_time(Table, Rs, Mode), CalleesFirst, T0, Times).

add_routine_time(Table, Rs, Mode, Name, T0, T) :-
    routine_time(env(Table, Rs, T0, Mode, Name, []), Name, Time),
    put_assoc(Name, T0, Time, T).

%   call_graph(+Routines, -Graph): an edge from each routine to every
%   routine it calls.
call_graph(Rs, G) :-
    findall(N, member(routine(N, _, _, _), Rs), Ns),
    findall(N-C, ( member(routine(N, LSs, _, _), Rs),
                   sub_term(Call, LSs), callee(Call, C) ),
            Edges),
    vertices_edges_to_ugraph(Ns, Edges, G).

callee(pcall(_, [C, _], _), C).
callee(fcall(_, [C, _], _), C).

%   routine_time(+Env, +Name, -Time): the predicted time of one
%   execution of the body of routine Name; 0 for a recursive call.
routine_time(env(Table, Rs, Times, Mode, _, Stack), Name, T) :-
    (   memberchk(Name, Stack)
    ->  T = 0
    ;   get_assoc(Name, Times, T)
    ->  true
    ;   memberchk(routine(Name, LSs, _, _), Rs),
        seq_time(env(Table, Rs, Times, Mode, Name, [Name|Stack]), LSs, T)
    ).

call_time(Env, Name, Args, T) :-
    Env = env(Table, _, _, _, _, _),
    routine_time(Env, Name, TB),
    unit_cost(Table, call, Call),
    args_time(Env, Args, TA),
    T is TB + Call + TA.

%   args_time(+Env, +Args, -Time): evaluating and passing Args.
args_time(Env, Args, T) :-
    Env = env(Table, _, _, _, _, _),
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
    Env = env(_, _, _, Mode, R, _),
    S = for(_, _, _), !,
    (   Mode = par(N, Chosen),
        memberchk(R/P-NR, Chosen)
    ->  parallel_for_time(Env, S, N, NR, T)
    ;   serial_for_time(Env, S, T)
    ).
stmt_time(Env, lbl(_, S), T) :-
    stmt(S, Env, T).

stmt(assign(_, [Target, E], _), Env, T) :-
    Env = env(Table, _, _, _, _, _),
    expr_time(Env, Target, T1),
    expr_time(Env, E, T2),
    arg(3, Target, Type),
    leaves(Type, N),
    unit_cost(Table, store, Store),
    T is T1 + T2 + N * Store.
stmt(zero_assign(_, [V], _), Env, T) :-
    Env = env(Table, _, _, _, _, _),
    expr_time(Env, V, T1),
    arg(3, V, Type),
    leaves(Type, N),
    unit_cost(Table, store, Store),
    T is T1 + N * Store.
stmt(if(_, [C, Then, Else], _), Env, T) :-
    Env = env(Table, _, _, _, _, _),
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
    Env = env(Table, _, _, _, _, _),
    unit_cost(Table, write_item, W),
    foldl(arg_time(Env, W), Args, 0, T).
stmt(empty(_, _, _), _, 0).

%   while and repeat: default_trips iterations of body and condition.
loop_time(Env, C, Body, T) :-
    Env = env(Table, _, _, _, _, _),
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
    Env = env(Table, _, _, _, _, _),
    for_parts(Env, F, To, D, Body, TBounds, Trips, TIter),
    overhead(Table, fork_join, P, FJ),
    overhead(Table, reduction, P, Red),
    T is TBounds + ((Trips + P - 1) // P) * TIter + FJ + NR * Red.

for_parts(Env, F, To, D, Body, TBounds, Trips, TIter) :-
    Env = env(Table, _, _, _, _, _),
    expr_time(Env, F, TF),
    expr_time(Env, To, TT),
    TBounds is TF + TT,
    for_trips(Table, F, To, D, Trips),
    seq_time(Env, Body, TB),
    unit_cost(Table, loop, Loop),
    TIter is TB + Loop.

for_trips(Table, F, T, D, N) :-
    (   int_const(F, VF), int_const(T, VT)
    ->  (   D == up
        ->  N is max(0, VT - VF + 1)
        ;   N is max(0, VF - VT + 1)
        )
    ;   trips(Table, N)
    ).

%   int_const(+Expr, -Value) is semidet: Expr is an integer expression
%   of constants (named constants are already iconst nodes), with the
%   operators the semantic pass folds in constant declarations.
int_const(iconst(_, [V], _), V).
int_const(op1(_, [-, E], integer), V) :-
    int_const(E, V0),
    V is -V0.
int_const(op2(_, [Op, A, B], integer), V) :-
    int_const(A, VA),
    int_const(B, VB),
    int_op(Op, VA, VB, V).

int_op(+, A, B, V) :- V is A + B.
int_op(-, A, B, V) :- V is A - B.
int_op(*, A, B, V) :- V is A * B.
int_op(div, A, B, V) :- B =\= 0, V is A // B.

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
    Env = env(Table, _, _, _, _, _),
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
