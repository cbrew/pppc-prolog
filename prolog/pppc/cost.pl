:- module(pppc_cost,
          [ load_cost_table/2,          % +File, -Table
            default_cost_file/1,        % -File
            required_entry/1,           % ?Key
            op2_cost/5,                 % +Table, +Op, +Left, +Right, -Cost
            op1_cost/4,                 % +Table, +Op, +Type, -Cost
            func_cost/3,                % +Table, +Name, -Cost
            unit_cost/3,                % +Table, +Key, -Cost
            trips/2,                    % +Table, -Trips
            overhead/4                  % +Table, +Kind, +P, -Cost
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).

/** <module> Target cost table

The cost table of the paper (section 4.4.6, "Run Time Prediction"):
the execution time of every construct, in units of one integer
addition, plus the cost of the parallel run time's services.

A table file holds facts, read as data with read_term/3 (never
consulted):

    cost_op2(Op, LeftType, RightType, Cost).
    cost_op1(Op, Type, Cost).
    cost_func(Name, Cost).
    cost(Key, Cost).          % Key: index store loop if call param itor write_item
    default_trips(Trips).     % iterations assumed for unknown loop bounds
    overhead(Kind, P, Cost).  % Kind: fork_join | reduction; one fact per measured P

load_cost_table/2 checks every fact and that every required entry is
present, and returns the table as a dict `cost{...}` from kind to a
list of Key-Cost pairs. The table is passed explicitly to the
predicates that need it: nothing is asserted.
*/

%!  default_cost_file(-File) is det.
%
%   The shipped table, produced by pppc_calibrate on the development
%   machine.
default_cost_file(File) :-
    absolute_file_name(library(pppc/cost/default), File,
                       [file_type(prolog), access(read)]).

%!  load_cost_table(+File, -Table) is det.
%
%   Throws pppc(cost_table_missing(File)) if File cannot be read and
%   pppc(bad_cost_table(File, Culprit)) if it holds a term that is not
%   a valid fact, a duplicate, or lacks a required entry (Culprit is
%   then missing(Key)).
load_cost_table(File, Table) :-
    read_facts(File, Facts),
    foldl(add_fact(File), Facts,
          cost{op2:[], op1:[], func:[], unit:[], trips:[], overhead:[]}, T0),
    forall(required_entry(Key), present(File, T0, Key)),
    get_dict(overhead, T0, Os0),
    msort(Os0, Os),
    put_dict(overhead, T0, Os, Table).

read_facts(File, Facts) :-
    catch(setup_call_cleanup(open(File, read, S),
                             read_all(S, Facts),
                             close(S)),
          E, read_error(File, E)).

read_all(S, Facts) :-
    read_term(S, T, []),
    (   T == end_of_file
    ->  Facts = []
    ;   Facts = [T|Ts],
        read_all(S, Ts)
    ).

read_error(File, error(syntax_error(What), _)) :- !,
    throw(pppc(bad_cost_table(File, syntax_error(What)))).
read_error(File, error(existence_error(source_sink, _), _)) :- !,
    throw(pppc(cost_table_missing(File))).
read_error(File, error(permission_error(_, _, _), _)) :- !,
    throw(pppc(cost_table_missing(File))).
read_error(_, E) :-
    throw(E).

add_fact(File, Fact, T0, T) :-
    (   entry(Fact, Kind, Key, Cost)
    ->  get_dict(Kind, T0, Es),
        (   memberchk(Key-_, Es)
        ->  throw(pppc(bad_cost_table(File, duplicate(Fact))))
        ;   put_dict(Kind, T0, [Key-Cost|Es], T)
        )
    ;   throw(pppc(bad_cost_table(File, Fact)))
    ).

%   entry(+Fact, -Kind, -Key, -Cost) is semidet: Fact is a valid table
%   fact. Its Key is what lookups and required_entry/1 use.
entry(Fact, _, _, _) :-
    \+ ground(Fact), !, fail.
entry(cost_op2(Op, L, R, C), op2, Op/L/R, C) :- cost(C), atom(Op), atom(L), atom(R).
entry(cost_op1(Op, T, C), op1, Op/T, C)      :- cost(C), atom(Op), atom(T).
entry(cost_func(F, C), func, F, C)           :- cost(C), atom(F).
entry(cost(K, C), unit, K, C)                :- cost(C), unit_key(K).
entry(default_trips(N), trips, trips, N)     :- integer(N), N > 0.
entry(overhead(K, P, C), overhead, K/P, C)   :-
    cost(C), memberchk(K, [fork_join, reduction]), integer(P), P > 0.

cost(C) :- integer(C), C >= 0.

unit_key(K) :- member(K, [index, store, loop, if, call, param, itor, write_item]).

%!  required_entry(?Key) is nondet.
%
%   Key is an entry every table must have: op2(Op/L/R), op1(Op/T),
%   func(F), unit(K), trips, or overhead(Kind/1). The operator and
%   function entries are exactly the typings the semantic pass accepts
%   (a unit test checks this).
required_entry(op2(Op/T/T)) :-
    member(T-Ops, [ integer-[+, -, *, div, mod, min, max, =, '<>', <, '<=', >, '>='],
                    real-[+, -, *, /, min, max, =, '<>', <, '<=', >, '>='],
                    boolean-[and, or, =, '<>'] ]),
    member(Op, Ops).
required_entry(op1(Op/T)) :-
    member(Op/T, [(-)/integer, (-)/real, not/boolean]).
required_entry(func(F)) :-
    member(F, [abs, sqr, sqrt, sin, cos, exp, ln, trunc, round, odd, random]).
required_entry(unit(K)) :-
    unit_key(K).
required_entry(trips).
required_entry(overhead(K/1)) :-
    member(K, [fork_join, reduction]).

present(File, T, Entry) :-
    Entry =.. [Kind|Rest],
    ( Rest = [Key] -> true ; Key = Kind ),
    get_dict(Kind, T, Es),
    (   memberchk(Key-_, Es)
    ->  true
    ;   throw(pppc(bad_cost_table(File, missing(Entry))))
    ).

                 /*******************************
                 *           LOOKUPS            *
                 *******************************/

%!  op2_cost(+Table, +Op, +Left, +Right, -Cost) is det.
op2_cost(T, Op, L, R, C) :- lookup(T, op2, Op/L/R, C).

%!  op1_cost(+Table, +Op, +Type, -Cost) is det.
op1_cost(T, Op, Ty, C) :- lookup(T, op1, Op/Ty, C).

%!  func_cost(+Table, +Name, -Cost) is det.
func_cost(T, F, C) :- lookup(T, func, F, C).

%!  unit_cost(+Table, +Key, -Cost) is det.
unit_cost(T, K, C) :- lookup(T, unit, K, C).

%!  trips(+Table, -Trips) is det.
trips(T, N) :- lookup(T, trips, trips, N).

lookup(T, Kind, Key, C) :-
    get_dict(Kind, T, Es),
    memberchk(Key-C, Es).

%!  overhead(+Table, +Kind, +P, -Cost) is det.
%
%   The overhead of Kind at P threads: the measured value, or a linear
%   interpolation between the nearest measured points, or beyond the
%   largest measured P a linear extrapolation from the last two (the
%   last one alone if only one is measured). Cost may be a rational;
%   it is never negative.
overhead(T, Kind, P, C) :-
    get_dict(overhead, T, Es),
    findall(Q-X, member(Kind/Q-X, Es), Points),
    (   memberchk(P-C, Points)
    ->  true
    ;   append(_, [P1-C1, P2-C2|_], Points), P1 < P, P < P2
    ->  C is C1 + (C2 - C1) * (P - P1) rdiv (P2 - P1)
    ;   last(Points, P2-C2),
        (   append(_, [P1-C1, P2-C2], Points)
        ->  C is max(0, C2 + (C2 - C1) * (P - P2) rdiv (P2 - P1))
        ;   C = C2
        )
    ).
