:- module(pppc_label,
          [ label_body/2,               % +Compound, -Labelled
            unlabel_body/3              % +Labelled, +Line, -Compound
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).

/** <module> Statement labelling

Gives every statement of a routine body a hierarchical label, a list
of integers, as in the paper (section 4.4.6). The statements directly
in a sequence are numbered 1, 2, ... after the label of the enclosing
structured statement, so a statement's label is a prefix of the labels
of every statement nested inside it.

  - The routine body's statements are [1], [2], ...
  - The body of for/while/repeat with label P is labelled [P,1], [P,2], ...
    A begin..end body is transparent: its statements are the children.
  - The then and else branches of an `if` P are [P,1] and [P,2]. A
    begin..end branch is itself a node; its statements are [P,1,1], ...
  - Nested begin..end inside a sequence is flattened into it.
  - Empty statements inside sequences are dropped.

Labelled statements are lbl(Label, Stmt). In a labelled for/while
statement the body argument is a list of lbl/2 terms; in a repeat the
statement list is; in an if each branch is a single lbl/2 term.
*/

%!  label_body(+Body, -Labelled:list) is det.
%
%   Body is a typed compound/3 statement (a routine body).
label_body(compound(_, [Ss], _), LSs) :-
    label_seq(Ss, [], 1, LSs).

label_seq([], _, _, []).
label_seq([compound(_, [Inner], _)|Ss], P, K, LSs) :- !,
    append(Inner, Ss, All),
    label_seq(All, P, K, LSs).
label_seq([empty(_, _, _)|Ss], P, K, LSs) :- !,
    label_seq(Ss, P, K, LSs).
label_seq([S|Ss], P, K0, [LS|LSs]) :-
    append(P, [K0], Lab),
    label_stmt(S, Lab, LS),
    K is K0 + 1,
    label_seq(Ss, P, K, LSs).

label_stmt(for(L, [V, F, T, D, Body], Ty), P, lbl(P, for(L, [V, F, T, D, LB], Ty))) :- !,
    body_list(Body, Ss), label_seq(Ss, P, 1, LB).
label_stmt(while(L, [C, Body], Ty), P, lbl(P, while(L, [C, LB], Ty))) :- !,
    body_list(Body, Ss), label_seq(Ss, P, 1, LB).
label_stmt(repeat(L, [Ss, C], Ty), P, lbl(P, repeat(L, [LB, C], Ty))) :- !,
    label_seq(Ss, P, 1, LB).
label_stmt(if(L, [C, Then, Else], Ty), P, lbl(P, if(L, [C, LT, LE], Ty))) :- !,
    append(P, [1], PT), label_branch(Then, PT, LT),
    append(P, [2], PE), label_branch(Else, PE, LE).
label_stmt(S, P, lbl(P, S)).

label_branch(compound(L, [Ss], Ty), P, lbl(P, compound(L, [LSs], Ty))) :- !,
    label_seq(Ss, P, 1, LSs).
label_branch(S, P, LS) :-
    label_stmt(S, P, LS).

body_list(compound(_, [Ss], _), Ss) :- !.
body_list(S, [S]).

%!  unlabel_body(+Labelled:list, +Line, -Body) is det.
%
%   Inverse of label_body/2 (up to the flattening it performs). Also
%   used by later passes, which may have replaced statements inside
%   lbl/2 wrappers.
unlabel_body(LSs, L, compound(L, [Ss], void)) :-
    maplist(unlabel, LSs, Ss).

unlabel(lbl(_, S), U) :- unlabel_stmt(S, U).

unlabel_stmt(for(L, [V, F, T, D, LB], Ty), for(L, [V, F, T, D, B], Ty)) :- !,
    unlabel_body(LB, L, B).
unlabel_stmt(omp_for(L, [V, F, T, D, LB, Cl], Ty), omp_for(L, [V, F, T, D, B, Cl], Ty)) :- !,
    unlabel_body(LB, L, B).
unlabel_stmt(while(L, [C, LB], Ty), while(L, [C, B], Ty)) :- !,
    unlabel_body(LB, L, B).
unlabel_stmt(repeat(L, [LB, C], Ty), repeat(L, [Ss, C], Ty)) :- !,
    maplist(unlabel, LB, Ss).
unlabel_stmt(if(L, [C, LT, LE], Ty), if(L, [C, T, E], Ty)) :- !,
    unlabel(LT, T), unlabel(LE, E).
unlabel_stmt(compound(L, [LSs], Ty), compound(L, [Ss], Ty)) :- !,
    maplist(unlabel, LSs, Ss).
unlabel_stmt(S, S).
