:- module(pppc_dataflow,
          [ with_dataflow/4,            % +Labelled, +AllVars, +ExitVars, :Goal
            with_dataflow/5,            % +Labelled, +AllVars, +ExitVars, +CallVars, :Goal
            reach/3,                    % ?Var, ?DefLabel, ?UseLabel
            carried/3,                  % +Loop, ?Var, ?UseLabel
            defines/3,                  % ?Label, ?Var, ?Kind
            inside/2                    % +Loop, +Label
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(pppc/tree)).

/** <module> Reaching definitions

Builds a statement-level control flow graph for one routine body
(labelled by pppc_label) as dynamic facts, and computes reaching
definitions over it with tabling. This replaces the paper's explicit
iterative solution of the dataflow equations (ASU86 10.5).

The graph has one node per labelled statement plus two extra nodes:

  - [-1], the routine entry, which defines every variable;
  - [0], the routine exit, which uses the variables whose values
    escape the routine (globals, var parameters, function result).

A call of a user routine may read and change only what the callee can
reach: the globals not shadowed in this routine, this routine's own var
parameters (which may be globals in disguise), and the variables passed
to it as var arguments. It cannot touch this routine's locals.

Facts (local to this module, valid only inside with_dataflow/5):

  - def(Label, Var, Kind)  Kind is `kill` for an assignment to the
    whole variable, `nokill` for an element/field assignment or a
    possible modification by a call;
  - use(Label, Var);
  - edge(From, To).
*/

:- meta_predicate
    with_dataflow(+, +, +, 0),
    with_dataflow(+, +, +, +, 0).

:- dynamic def/3, use/2, edge/2.

:- table reach_in/3, clear/3.

%!  with_dataflow(+Labelled:list, +AllVars:list, +ExitVars:list, :Goal)
%!  with_dataflow(+Labelled:list, +AllVars:list, +ExitVars:list,
%!                +CallVars:list, :Goal)
%
%   Run Goal with the dataflow facts for the routine body Labelled
%   loaded. AllVars are all variables visible in the routine; ExitVars
%   those live at its exit; CallVars those a call of another routine
%   may read or change (besides its var arguments). with_dataflow/4
%   takes CallVars = AllVars, which is right for the main program.
%   Goal is run as once/1.
with_dataflow(LSs, AllVars, ExitVars, Goal) :-
    with_dataflow(LSs, AllVars, ExitVars, AllVars, Goal).

with_dataflow(LSs, AllVars, ExitVars, CallVars, Goal) :-
    setup_call_cleanup(
        load_graph(LSs, AllVars, ExitVars, CallVars),
        once(Goal),
        clear_graph).

clear_graph :-
    retractall(def(_, _, _)),
    retractall(use(_, _)),
    retractall(edge(_, _)),
    abolish_module_tables(pppc_dataflow).

load_graph(LSs, AllVars, ExitVars, CallVars) :-
    clear_graph,
    forall(member(V, AllVars), assertz(def([-1], V, kill))),
    forall(member(V, ExitVars), assertz(use([0], V))),
    flow_seq(LSs, CallVars, [[-1]], Exits),
    connect(Exits, [0]).

                 /*******************************
                 *        CONTROL FLOW          *
                 *******************************/

%   flow_seq(+Stmts, +CallVars, +Preds, -Exits): Preds are the nodes
%   that flow into the first statement; Exits those that flow out of
%   the last. CallVars is passed down for the effects of calls.

flow_seq([], _, Preds, Preds).
flow_seq([S|Ss], Vs, Preds, Exits) :-
    flow(S, Vs, Preds, X),
    flow_seq(Ss, Vs, X, Exits).

flow(lbl(P, repeat(_, [Body, C], _)), Vs, Preds, [P]) :- !,
    node_effects(P, C, Vs),
    flow_seq(Body, Vs, [P|Preds], X),
    connect(X, P).
flow(lbl(P, S), Vs, Preds, Exits) :-
    connect(Preds, P),
    stmt_effects(S, P, Vs),
    flow_inner(S, P, Vs, Exits).

flow_inner(for(_, [_, _, _, _, Body], _), P, Vs, [P]) :- !,
    flow_seq(Body, Vs, [P], X), connect(X, P).
flow_inner(omp_for(_, [_, _, _, _, Body, _], _), P, Vs, [P]) :- !,
    flow_seq(Body, Vs, [P], X), connect(X, P).
flow_inner(while(_, [_, Body], _), P, Vs, [P]) :- !,
    flow_seq(Body, Vs, [P], X), connect(X, P).
flow_inner(if(_, [_, Then, Else], _), P, Vs, Exits) :- !,
    flow(Then, Vs, [P], X1),
    flow(Else, Vs, [P], X2),
    append(X1, X2, Exits).
flow_inner(compound(_, [LSs], _), P, Vs, Exits) :- !,
    flow_seq(LSs, Vs, [P], Exits).
flow_inner(_, P, _, [P]).

connect(Preds, N) :-
    forall(member(P, Preds), assertz(edge(P, N))).

                 /*******************************
                 *      DEFINITIONS & USES      *
                 *******************************/

%   stmt_effects(+Stmt, +Label, +CallVars) asserts the def/use facts of
%   the statement node itself (not of nested statements): its own reads
%   and writes, plus those of any user call it makes.

stmt_effects(S, P, Vs) :-
    own_effects(S, P),
    shallow_part(S, Part),
    (   has_user_call(Part)
    ->  call_effects(P, Part, Vs)
    ;   true
    ).

own_effects(assign(_, [T, E], _), P) :- !,
    target_base(T, V, Whole),
    target_uses(T, U1), expr_vars(E, U2), ord_union(U1, U2, Us),
    add_uses(P, Us),
    add_def(P, V, Whole).
own_effects(zero_assign(_, [T], _), P) :- !,
    target_base(T, V, Whole),
    target_uses(T, Us),
    add_uses(P, Us),
    add_def(P, V, Whole).
own_effects(S, P) :-
    ( S = for(_, [Var, F, T, _, _], _) ; S = omp_for(_, [Var, F, T, _, _, _], _) ), !,
    expr_vars(F-T, Us),
    add_uses(P, Us),
    var_node(Var, V),
    add_def(P, V, true).
own_effects(S, P) :-
    shallow_part(S, Part),
    expr_vars(Part, Us),
    add_uses(P, Us).

%   node_effects(+Label, +Cond, +CallVars): the condition of a repeat,
%   evaluated at the repeat's own node.
node_effects(P, C, Vs) :-
    expr_vars(C, Us),
    add_uses(P, Us),
    (   has_user_call(C)
    ->  call_effects(P, C, Vs)
    ;   true
    ).

%   shallow_part(+Stmt, -Part): the parts of Stmt evaluated at its own
%   node, excluding nested statements.
shallow_part(for(_, [V, F, T, _, _], _), V-F-T) :- !.
shallow_part(omp_for(_, [V, F, T, _, _, _], _), V-F-T) :- !.
shallow_part(while(_, [C, _], _), C) :- !.
shallow_part(if(_, [C, _, _], _), C) :- !.
shallow_part(compound(_, _, _), none) :- !.
shallow_part(S, S).

%   call_effects(+Label, +Part, +CallVars): a user call in Part may
%   read and modify CallVars and the variables passed as var arguments.
call_effects(P, Part, Vs) :-
    findall(V, ( sub_term(A, Part), compound(A), A = addr(_, [X], _),
                 target_base(X, V, _) ), VarArgs0),
    sort(VarArgs0, VarArgs),
    ord_union(Vs, VarArgs, Reach),
    add_uses(P, Reach),
    forall(member(V, Reach), add_def(P, V, false)).

add_uses(P, Us) :-
    forall(member(U, Us), assertz(use(P, U))).

add_def(P, V, true)  :- assertz(def(P, V, kill)).
add_def(P, V, false) :- assertz(def(P, V, nokill)).

                 /*******************************
                 *     REACHING DEFINITIONS     *
                 *******************************/

%!  reach(?Var, ?Def, ?Use) is nondet.
%
%   The value of Var assigned at statement Def may be read at
%   statement Use. Corresponds to the paper's reach/3 facts.
reach(V, S, U) :-
    use(U, V),
    reach_in(V, S, U).

%!  defines(?Label, ?Var, ?Kind) is nondet.
defines(P, V, K) :- def(P, V, K).

%   reach_in(V, S, N): the definition of V at S reaches the entry of N.
reach_in(V, S, N) :-
    edge(P, N),
    reach_out(V, S, P).

reach_out(V, P, P) :-
    def(P, V, _).
reach_out(V, S, P) :-
    reach_in(V, S, P),
    \+ def(P, V, kill).

%!  inside(+Loop, +Label) is semidet.
%
%   Label is strictly inside the statement labelled Loop.
inside(L, S) :-
    append(L, [_|_], S).

%!  carried(+Loop, +Var, -Use) is semidet.
%
%   A value of Var assigned inside Loop survives to the loop header
%   (through the back edge, or around an enclosing loop) and is then
%   read at Use inside Loop before being reassigned: a loop-carried
%   flow dependence.
carried(L, V, U) :-
    use(U, V),
    inside(L, U),
    reach_in(V, S, L),
    inside(L, S),
    \+ def(L, V, kill),
    clear(V, L, U),
    !.

%   clear(V, N, M): there is a path from the exit of N to the entry of
%   M on which no node kills V.
clear(_, N, M) :-
    edge(N, M).
clear(V, N, M) :-
    edge(N, P),
    \+ def(P, V, kill),
    clear(V, P, M).
