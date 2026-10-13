:- module(pppc_parloop,
          [ classify_loops/2,           % +Labelled, -Loops
            stmt_access/2,              % +Stmt, -Access
            is_local/2                  % +Var, +Loop
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(pairs)).
:- use_module(library(pppc/tree)).
:- use_module(library(pppc/dataflow)).

/** <module> Parallel loop detection

Implements the parallelization rules of the paper (section 4.3.3).
Must be called inside pppc_dataflow:with_dataflow/4 for the routine.

A bottom-up traversal computes for each statement an access summary

    acc(Refs, Changes, Assoc, Arrays, Effects)

  - Refs, Changes: ordsets of variables read / written;
  - Assoc: ordset of Var-Op for variables only updated by statements
    `Var := Var Op Expr`, Op in + * and or min max;
  - Arrays: list of Array-Access, Access is sub(FirstSubscript) or
    `whole`;
  - Effects: ordset of call, io, vparam_change.

Summaries of compound statements are merged as described in section
4.4.6: an associative variable stays associative only if no other
part of the statement touches it, or uses a different operator.

A `for` loop is parallel if it has no effects and every variable it
touches is one of index, read_only, associative(Op), distributed or
local. Only the outermost parallel loop is taken; loops inside it are
reported as nested.
*/

%!  classify_loops(+Labelled:list, -Loops:list) is det.
%
%   Loops has an entry loop(Label, Line, Verdict, Classes) for each
%   for loop, in source order. Verdict is `parallel`, serial(Reasons)
%   or nested(OuterLine). Classes is a list of Var-Class (empty for
%   nested loops).
classify_loops(LSs, Loops) :-
    phrase(loops_seq(LSs), Loops).

loops_seq([]) --> [].
loops_seq([S|Ss]) --> loops(S), loops_seq(Ss).

loops(lbl(P, for(L, [Var, _, _, _, Body], _))) --> !,
    { classify(P, Var, Body, Verdict, Classes) },
    [loop(P, L, Verdict, Classes)],
    (   { Verdict == parallel }
    ->  nested(Body, L)
    ;   loops_seq(Body)
    ).
loops(lbl(_, while(_, [_, Body], _)))  --> !, loops_seq(Body).
loops(lbl(_, repeat(_, [Body, _], _))) --> !, loops_seq(Body).
loops(lbl(_, if(_, [_, T, E], _)))     --> !, loops(T), loops(E).
loops(lbl(_, compound(_, [Ss], _)))    --> !, loops_seq(Ss).
loops(_) --> [].

nested(Stmts, Outer) -->
    { findall(loop(P, L, nested(Outer), []),
              ( member(S, Stmts), sub_term(lbl(P, for(L, _, _)), S) ),
              Inner) },
    Inner.

                 /*******************************
                 *        CLASSIFICATION        *
                 *******************************/

classify(P, Var, Body, Verdict, Classes) :-
    var_node(Var, I),
    seq_access(Body, acc(Refs, Chgs, Assoc, Arrays, Effects)),
    pairs_keys(Assoc, AssocVars),
    pairs_keys(Arrays, ArrayVars0),
    sort(ArrayVars0, ArrayVars),
    foldl(ord_union, [Refs, Chgs, AssocVars, ArrayVars], [I], All),
    maplist(var_class(P, I, Chgs, Assoc, Arrays), All, Classes),
    findall(dependent(V), member(V-dependent, Classes), Deps),
    append(Effects, Deps, Reasons),
    (   Reasons == []
    ->  Verdict = parallel
    ;   Verdict = serial(Reasons)
    ).

var_class(P, I, Chgs, Assoc, Arrays, V, V-Class) :-
    (   V == I
    ->  ( ord_memberchk(V, Chgs) -> Class = dependent ; Class = index )
    ;   memberchk(V-Op, Assoc)
    ->  Class = associative(Op)
    ;   \+ ord_memberchk(V, Chgs)
    ->  Class = read_only
    ;   distributed(V, I, Arrays)
    ->  Class = distributed
    ;   is_local(V, P)
    ->  Class = local
    ;   Class = dependent
    ).

%   Every access of array V is subscripted, in its first dimension, by
%   the loop index I itself.
distributed(V, I, Arrays) :-
    memberchk(V-_, Arrays),
    forall(member(V-Access, Arrays),
           ( Access = sub(Sub), var_node(Sub, I) )).

%!  is_local(+Var, +Loop) is semidet.
%
%   Var is local to the loop labelled Loop: it is only assigned as a
%   whole, and its value is never passed between iterations or into
%   or out of the loop. Written after the
%   paper's is_local/2, with the "previous iteration" test done
%   exactly by pppc_dataflow:carried/3 instead of the before/2
%   ordering of labels.
is_local(V, L) :-
    set_inside(V, L),
    \+ partly_set_inside(V, L),
    \+ value_enters(V, L),
    \+ value_escapes(V, L),
    \+ carried(L, V, _).

set_inside(V, L) :-
    defines(S, V, _), inside(L, S), !.

%   An element or field assignment cannot make a private copy whole.
partly_set_inside(V, L) :-
    defines(S, V, nokill), inside(L, S), !.

value_enters(V, L) :-
    reach(V, S, U), inside(L, U), \+ inside(L, S), !.

value_escapes(V, L) :-
    reach(V, S, U), inside(L, S), \+ inside(L, U), !.

                 /*******************************
                 *        ACCESS SUMMARY        *
                 *******************************/

%!  stmt_access(+Stmt, -Access) is det.
%
%   Stmt may be labelled (lbl/2) or not.
stmt_access(lbl(_, S), A) :- !,
    stmt_access(S, A).
stmt_access(S, A) :-
    shallow_access(S, A0),
    findall(C, child_stmt(S, C), Children),
    seq_access(Children, A1),
    merge_access(A0, A1, A).

seq_access(Ss, A) :-
    empty_access(A0),
    foldl(merge_stmt, Ss, A0, A).

merge_stmt(S, A0, A) :-
    stmt_access(S, A1),
    merge_access(A0, A1, A).

empty_access(acc([], [], [], [], [])).

child_stmt(for(_, [_, _, _, _, B], _), S) :- member(S, B).
child_stmt(while(_, [_, B], _), S) :- member(S, B).
child_stmt(repeat(_, [B, _], _), S) :- member(S, B).
child_stmt(if(_, [_, T, E], _), S) :- member(S, [T, E]).
child_stmt(compound(_, [B], _), S) :- member(S, B).

%   shallow_access(+Stmt, -Access): what the statement's own node does.
shallow_access(assign(_, [T, E], _), A) :-
    assoc_update(T, E, V, Op, Other), !,
    expr_vars(Other, Refs),
    arrays_in(Other, Arrays),
    effects_of(assign(_, [T, E], _), Effects),
    A = acc(Refs, [], [V-Op], Arrays, Effects).
shallow_access(S, acc(Refs, Chgs, [], Arrays, Effects)) :-
    reads_writes(S, Refs, Chgs),
    arrays_in(S, Arrays),
    effects_of(S, Effects).

assoc_update(T, op2(_, [Op, X, Y], _), V, Op, Other) :-
    var_node(T, V),
    arg(3, T, Type), memberchk(Type, [integer, real, boolean]),
    memberchk(Op, [+, *, and, or, min, max]),
    (   var_node(X, V), expr_vars(Y, YVs), \+ ord_memberchk(V, YVs)
    ->  Other = Y
    ;   var_node(Y, V), expr_vars(X, XVs), \+ ord_memberchk(V, XVs)
    ->  Other = X
    ).

reads_writes(assign(_, [T, E], _), Refs, [V]) :- !,
    target_base(T, V, _),
    target_uses(T, U1), expr_vars(E, U2), ord_union(U1, U2, Refs).
reads_writes(zero_assign(_, [T], _), Refs, [V]) :- !,
    target_base(T, V, _), target_uses(T, Refs).
reads_writes(for(_, [Var, F, T, _, _], _), Refs, [I]) :- !,
    var_node(Var, I), expr_vars(F-T, Refs).
reads_writes(pcall(_, [_, Args], _), Refs, Chgs) :- !,
    expr_vars(Args, Refs),
    findall(V, (member(addr(_, [X], _), Args), target_base(X, V, _)), Vs),
    sort(Vs, Chgs).
reads_writes(S, Refs, []) :-
    shallow_expr(S, E), expr_vars(E, Refs).

shallow_expr(while(_, [C, _], _), C) :- !.
shallow_expr(repeat(_, [_, C], _), C) :- !.
shallow_expr(if(_, [C, _, _], _), C) :- !.
shallow_expr(compound(_, _, _), none) :- !.
shallow_expr(S, S).

%   arrays_in(+Term, -Accesses): array accesses in the expressions of
%   the statement node (not nested statements).
arrays_in(S, As) :-
    shallow_terms(S, T),
    phrase(arrays(T), As).

shallow_terms(for(_, [V, F, T, _, _], _), V-F-T) :- !.
shallow_terms(S, E) :- shallow_expr(S, E).

arrays(index(_, [A, I], _)) --> { var_node(A, N) }, !, [N-sub(I)], arrays(I).
arrays(N) --> { var_node(N, V), arg(3, N, array(_, _, _)) }, !, [V-whole].
arrays(T) --> { compound(T), \+ var_node(T, _) }, !,
    { T =.. [_|Args] }, arrays_list(Args).
arrays(_) --> [].

arrays_list([]) --> [].
arrays_list([A|As]) --> arrays(A), arrays_list(As).

effects_of(S, Effects) :-
    findall(E, effect(S, E), Es),
    sort(Es, Effects).

effect(S, call) :- shallow_terms(S, T), has_user_call(T).
effect(write(_, _, _), io).
effect(S, vparam_change) :-
    ( S = assign(_, [T, _], _) ; S = zero_assign(_, [T], _) ),
    sub_term(B, T), compound(B), B = vparam(_, _, _), !.

%!  merge_access(+A1, +A2, -A) is det.
merge_access(acc(R1, C1, A1, Ar1, E1), acc(R2, C2, A2, Ar2, E2), acc(R, C, A, Ar, E)) :-
    ord_union(R1, C1, T1),
    ord_union(R2, C2, T2),
    keep_assoc(A1, T2, A2, K1, D1),
    keep_assoc(A2, T1, A1, K2, D2),
    ord_union(K1, K2, A),
    ord_union(D1, D2, Dropped),
    foldl(ord_union, [R1, R2, Dropped], [], R),
    foldl(ord_union, [C1, C2, Dropped], [], C),
    append(Ar1, Ar2, Ar),
    ord_union(E1, E2, E).

%   keep_assoc(+Assoc, +OtherTouched, +OtherAssoc, -Kept, -Dropped)
keep_assoc([], _, _, [], []).
keep_assoc([V-Op|As], Touched, Other, Kept, Dropped) :-
    (   \+ ord_memberchk(V, Touched),
        ( memberchk(V-Op2, Other) -> Op2 == Op ; true )
    ->  Kept = [V-Op|Kept1], Dropped = Dropped1
    ;   Kept = Kept1, Dropped = [V|Dropped1]
    ),
    keep_assoc(As, Touched, Other, Kept1, Dropped1).
