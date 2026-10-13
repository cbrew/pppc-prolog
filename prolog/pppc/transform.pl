:- module(pppc_transform,
          [ analyse_program/2,          % +Typed, -Routines
            parallelize_program/3       % +Typed, -Parallel, -Routines
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(pairs)).
:- use_module(library(pppc/label)).
:- use_module(library(pppc/dataflow)).
:- use_module(library(pppc/parloop)).

/** <module> Parallelizer driver and loop transformation

Runs the parallelizer phases of the paper (section 4.4.6) over each
routine of a typed program: statement labelling, reaching definitions,
parallel loop detection, code transformation and cleanup. Run time
prediction is Phase 2; every loop found parallel is transformed.

A parallel loop becomes

    omp_for(Line, [Var, From, To, Dir, Body, Clauses], void)

where Clauses is a list of private(Vars), shared(Vars) and
reduction(Op, Vars) terms with non-empty variable lists.
*/

%!  analyse_program(+Typed, -Routines:list) is det.
%
%   Routines has one routine(Name, Labelled, Loops, Reach) per routine
%   (the main program first, named `main`). Reach is the sorted list of
%   reach(Var, Def, Use) facts. Used for --dump and --report.
analyse_program(Typed, Routines) :-
    program_routines(Typed, Rs),
    maplist(analyse_routine, Rs, Routines).

%!  parallelize_program(+Typed, -Parallel, -Routines) is det.
parallelize_program(Typed, Parallel, Routines) :-
    analyse_program(Typed, Routines),
    Typed = program(L, [Name, block(BL, [Decls, Procs, Body], void)], void),
    routine_body(main, Routines, Body, NewBody),
    maplist(transform_proc(Routines), Procs, NewProcs),
    Parallel = program(L, [Name, block(BL, [Decls, NewProcs, NewBody], void)], void).

transform_proc(Routines, proc(L, [N, Ps, R, block(BL, [D, P, Body], void)], void),
               proc(L, [N, Ps, R, block(BL, [D, P, NewBody], void)], void)) :-
    routine_body(N, Routines, Body, NewBody).

routine_body(Name, Routines, compound(L, _, _), NewBody) :-
    memberchk(routine(Name, LSs, Loops, _), Routines),
    transform_seq(LSs, Loops, LSs1),
    unlabel_body(LSs1, L, NewBody).

                 /*******************************
                 *          ROUTINES            *
                 *******************************/

%   program_routines(+Typed, -Rs): Rs is a list of
%   r(Name, Body, AllVars, ExitVars).

program_routines(program(_, [_, block(_, [Decls, Procs, Body], _)], _), [Main|Rs]) :-
    decl_names(Decls, Globals),
    Main = r(main, Body, Globals, []),
    maplist(proc_routine(Globals), Procs, Rs).

proc_routine(Globals, proc(_, [Name, Params, R, block(_, [Decls, _, Body], _)], _),
             r(Name, Body, All, Exit)) :-
    findall(N, (member(param(_, [_, Ns, _], _), Params), member(N, Ns)), PNs),
    findall(N, (member(param(_, [var, Ns, _], _), Params), member(N, Ns)), VNs),
    decl_names(Decls, Locals),
    ( R == none -> Res = [] ; Res = [Name] ),
    foldl(union_list, [Globals, PNs, Locals, Res], [], All),
    foldl(union_list, [Globals, VNs, Res], [], Exit).

union_list(L, S0, S) :- sort(L, SL), ord_union(S0, SL, S).

decl_names(Decls, Names) :-
    findall(N, (member(var_decl(_, [Ns, _], _), Decls), member(N, Ns)), Names0),
    sort(Names0, Names).

analyse_routine(r(Name, Body, All, Exit), routine(Name, LSs, Loops, Reach)) :-
    label_body(Body, LSs),
    with_dataflow(LSs, All, Exit,
                  ( classify_loops(LSs, Loops),
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
