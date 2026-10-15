:- module(pppc_transform,
          [ analyse_program/2,          % +Typed, -Routines
            candidate_loops/2,          % +Routines, -Keys
            parallelize_program/3,      % +Typed, -Parallel, -Routines
            parallelize_program/5       % +Typed, +Table, +N, -Parallel, -Routines
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(pairs)).
:- use_module(library(pppc/label)).
:- use_module(library(pppc/dataflow)).
:- use_module(library(pppc/parloop)).
:- use_module(library(pppc/predict)).

/** <module> Parallelizer driver and loop transformation

Runs the parallelizer phases of the paper (section 4.4.6) over each
routine of a typed program: statement labelling, reaching definitions,
parallel loop detection, run time prediction (pppc_predict), code
transformation and cleanup.

A parallel loop becomes

    omp_for(Line, [Var, From, To, Dir, Body, Clauses], void)

where Clauses is a list of private(Vars), shared(Vars) and
reduction(Op, Vars) terms with non-empty variable lists.
*/

%!  analyse_program(+Typed, -Routines:list) is det.
%
%   Routines has one routine(Name, Labelled, Loops, Reach) per routine
%   (the main program first, named `program`: a reserved word, so no
%   user routine can have the same name). Reach is the sorted list of
%   reach(Var, Def, Use) facts. Used for --dump and --report.
analyse_program(Typed, Routines) :-
    program_routines(Typed, Rs),
    maplist(analyse_routine, Rs, Routines).

%!  candidate_loops(+Routines, -Keys:list) is det.
%
%   Keys is the sorted list of Routine-Line of the loops that obey the
%   parallelization rules in Routines (from analyse_program/2): the
%   loops run time prediction decides about, and a timed build times.
candidate_loops(Routines, Keys) :-
    findall(N-L, ( member(routine(N, _, Loops, _), Routines),
                   member(loop(_, L, parallel, _), Loops) ),
            Keys0),
    sort(Keys0, Keys).

%!  parallelize_program(+Typed, -Parallel, -Routines) is det.
%
%   Transform every loop that obeys the parallelization rules, without
%   run time prediction.
parallelize_program(Typed, Parallel, Routines) :-
    analyse_program(Typed, Routines),
    transform_program(Typed, Routines, Parallel).

%!  parallelize_program(+Typed, +Table, +N, -Parallel, -Routines) is det.
%
%   Transform the loops that obey the parallelization rules and are
%   predicted, with cost table Table, to run faster in parallel on N
%   threads. Routines has the final verdicts.
parallelize_program(Typed, Table, N, Parallel, Routines) :-
    analyse_program(Typed, Routines0),
    decide(Routines0, Table, N, Routines, _),
    transform_program(Typed, Routines, Parallel).

transform_program(Typed, Routines, Parallel) :-
    Typed = program(L, [Name, block(BL, [Decls, Procs, Body], void)], void),
    routine_body(program, Routines, Body, NewBody),
    maplist(transform_proc(Routines), Procs, NewProcs),
    Parallel = program(L, [Name, block(BL, [Decls, NewProcs, NewBody], void)], void).

transform_proc(Routines, proc(L, [N, Ps, R, block(BL, [D, P, Body], void)], void),
               proc(L, [N, Ps, R, block(BL, [D, P, NewBody], void)], void)) :-
    routine_body(N, Routines, Body, NewBody).

routine_body(Name, Routines, compound(L, _, _), NewBody) :-
    memberchk(routine(Name, LSs, Loops0, _), Routines),
    maplist(hide_result(Name), Loops0, Loops),
    transform_seq(LSs, Loops, LSs1),
    unlabel_body(LSs1, L, NewBody).

%   A function's result is stored in pppc_result, a C local declared
%   outside the loop and so shared by default; it must not be named in
%   a clause. (The only class it can have in a parallel loop is
%   distributed: reading it is an error, so it is never local or
%   associative.)
%   (A plain helper rather than a yall lambda: a lambda that mentions a
%   variable of the enclosing clause, like Name here, behaves differently
%   depending on whether library(yall) was loaded when this file was
%   compiled, unless the variable is declared with Name/[X]>>... .)
hide_result(Name, loop(P, L, V, Classes0), loop(P, L, V, Classes)) :-
    exclude(class_of(Name), Classes0, Classes).

class_of(Name, X-_) :- X == Name.

                 /*******************************
                 *          ROUTINES            *
                 *******************************/

%   program_routines(+Typed, -Rs): Rs is a list of
%   r(Name, Body, AllVars, ExitVars, CallVars). CallVars are the
%   variables another routine called from this one can reach (and so
%   also those a var parameter of this one might alias): the globals not
%   shadowed here, plus this routine's var parameters.

program_routines(program(_, [_, block(_, [Decls, Procs, Body], _)], _), [Main|Rs]) :-
    decl_names(Decls, Globals),
    Main = r(program, Body, Globals, [], Globals),
    maplist(proc_routine(Globals), Procs, Rs).

proc_routine(Globals, proc(_, [Name, Params, R, block(_, [Decls, _, Body], _)], _),
             r(Name, Body, All, Exit, Call)) :-
    findall(N, (member(param(_, [_, Ns, _], _), Params), member(N, Ns)), PNs),
    findall(N, (member(param(_, [var, Ns, _], _), Params), member(N, Ns)), VNs),
    decl_names(Decls, Locals),
    ( R == none -> Res = [] ; Res = [Name] ),
    foldl(union_list, [PNs, Locals, Res], [], Own),
    ord_subtract(Globals, Own, Visible),
    foldl(union_list, [Visible, Own], [], All),
    foldl(union_list, [Visible, VNs, Res], [], Exit),
    union_list(VNs, Visible, Call).

union_list(L, S0, S) :- sort(L, SL), ord_union(S0, SL, S).

decl_names(Decls, Names) :-
    findall(N, (member(var_decl(_, [Ns, _], _), Decls), member(N, Ns)), Names0),
    sort(Names0, Names).

analyse_routine(r(Name, Body, All, Exit, Call), routine(Name, LSs, Loops, Reach)) :-
    label_body(Body, LSs),
    with_dataflow(LSs, All, Exit, Call,
                  ( classify_loops(LSs, Call, Loops),
                    findall(reach(V, S, U), reach(V, S, U), Reach0),
                    sort(Reach0, Reach) )).

                 /*******************************
                 *        TRANSFORMATION        *
                 *******************************/

transform_seq(LSs, Loops, LSs1) :-
    maplist(transform(Loops), LSs, LSs1).

transform(Loops, lbl(P, for(L, [V, F, T, D, B], Ty)), lbl(P, S)) :- !,
    (   memberchk(loop(P, _, parallel, Classes), Loops)
    ->  clauses(Classes, Clauses),
        S = omp_for(L, [V, F, T, D, B, Clauses], Ty)
    ;   transform_seq(B, Loops, B1),
        S = for(L, [V, F, T, D, B1], Ty)
    ).
transform(Loops, lbl(P, while(L, [C, B], Ty)), lbl(P, while(L, [C, B1], Ty))) :- !,
    transform_seq(B, Loops, B1).
transform(Loops, lbl(P, repeat(L, [B, C], Ty)), lbl(P, repeat(L, [B1, C], Ty))) :- !,
    transform_seq(B, Loops, B1).
transform(Loops, lbl(P, if(L, [C, T, E], Ty)), lbl(P, if(L, [C, T1, E1], Ty))) :- !,
    transform(Loops, T, T1),
    transform(Loops, E, E1).
transform(Loops, lbl(P, compound(L, [B], Ty)), lbl(P, compound(L, [B1], Ty))) :- !,
    transform_seq(B, Loops, B1).
transform(_, S, S).

%!  clauses(+Classes, -Clauses) is det.
%
%   Map the paper's variable categories to OpenMP data-sharing clauses.
clauses(Classes, Clauses) :-
    findall(V, member(V-local, Classes), Private),
    findall(V, ( member(V-C, Classes), memberchk(C, [read_only, distributed]) ), Shared),
    findall(Op-V, member(V-associative(Op), Classes), OpVs),
    keysort(OpVs, Sorted),
    group_pairs_by_key(Sorted, Groups),
    findall(reduction(Op, Vs), member(Op-Vs, Groups), Reductions),
    exclude(==(private([])), [private(Private)], P1),
    exclude(==(shared([])), [shared(Shared)], S1),
    append([P1, S1, Reductions], Clauses).
