:- use_module(library(pppc/cost)).
:- use_module(library(pppc/semantic)).
:- use_module(library(readutil)).
:- use_module(library(apply)).
:- use_module(library(lists)).

:- begin_tests(cost).

unit_file('test/costs/unit.pl').

%   variant(+Drop, +Add, -File): a copy of the unit table without the
%   lines that start with Drop, plus the text Add.
variant(Drop, Add, File) :-
    unit_file(U),
    read_file_to_string(U, Text, []),
    split_string(Text, "\n", "", Lines),
    exclude(dropped(Drop), Lines, Kept),
    atomic_list_concat(Kept, '\n', Body),
    tmp_file_stream(text, File, S),
    format(S, "~w~n~w~n", [Body, Add]),
    close(S).

dropped(Drop, Line) :-
    Drop \== "",
    string_concat(Drop, _, Line).

test(unit_table_loads) :-
    unit_file(F),
    load_cost_table(F, T),
    op2_cost(T, +, real, real, C1), assertion(C1 == 1),
    unit_cost(T, write_item, C2), assertion(C2 == 1),
    trips(T, N), assertion(N == 25).

test(default_table_loads) :-
    default_cost_file(F),
    load_cost_table(F, T),
    unit_cost(T, loop, C),
    assertion(integer(C)).

%   The semantic pass's typing rules test membership rather than
%   enumerate, so the check runs over every operator of the language
%   and every pair of scalar types.
test(required_operators_match_semantic_pass) :-
    Types = [integer, real, boolean],
    forall(( member(Op, [+, -, *, /, div, mod, min, max, and, or,
                         =, '<>', <, '<=', >, '>=']),
             member(L, Types), member(R, Types) ),
           assertion(( pppc_semantic:op2_rule(Op, L, R, _)
                     ->  required_entry(op2(Op/L/R))
                     ;   \+ required_entry(op2(Op/L/R)) ))),
    forall(( member(Op, [-, not]), member(T, Types) ),
           assertion(( pppc_semantic:op1_rule(Op, T, _)
                     ->  required_entry(op1(Op/T))
                     ;   \+ required_entry(op1(Op/T)) ))),
    forall(required_entry(func(F)),
           assertion(pppc_semantic:builtin_name(F))).

test(negative_cost, throws(pppc(bad_cost_table(_, cost(index, -1))))) :-
    variant("cost(index", "cost(index, -1).", F),
    load_cost_table(F, _).

test(unknown_fact, throws(pppc(bad_cost_table(_, colour(blue))))) :-
    variant("", "colour(blue).", F),
    load_cost_table(F, _).

test(duplicate_entry, throws(pppc(bad_cost_table(_, duplicate(cost(loop, 3)))))) :-
    variant("", "cost(loop, 3).", F),
    load_cost_table(F, _).

test(missing_entry, throws(pppc(bad_cost_table(_, missing(func(sqrt)))))) :-
    variant("cost_func(sqrt", "", F),
    load_cost_table(F, _).

test(syntax_error_has_line, throws(pppc(bad_cost_table(_, syntax_error(2, _))))) :-
    tmp_file_stream(text, F, S),
    format(S, "cost(loop, 1).~ncost(loop, ).~n", []),
    close(S),
    load_cost_table(F, _).

test(directory, throws(pppc(cost_table_missing(_)))) :-
    tmp_file(costdir, D),
    make_directory(D),
    load_cost_table(D, _).

test(mistyped_type, throws(pppc(bad_cost_table(_, cost_op2(+, integr, integer, 1))))) :-
    variant("", "cost_op2(+, integr, integer, 1).", F),
    load_cost_table(F, _).

test(unknown_function, throws(pppc(bad_cost_table(_, cost_func(sine, 2))))) :-
    variant("", "cost_func(sine, 2).", F),
    load_cost_table(F, _).

test(missing_file, throws(pppc(cost_table_missing('no/such/table.pl')))) :-
    load_cost_table('no/such/table.pl', _).

test(overhead_measured) :-
    unit_file(F), load_cost_table(F, T),
    overhead(T, fork_join, 3, C),
    assertion(C == 300).

test(overhead_interpolated) :-
    % fork/join measured at 1 and 4 only: 100 + 300 * 1/3
    variant("overhead(fork_join", "overhead(fork_join, 1, 100).\noverhead(fork_join, 4, 400).", F),
    load_cost_table(F, T),
    overhead(T, fork_join, 2, C),
    assertion(C == 200).

test(overhead_extrapolated) :-
    unit_file(F), load_cost_table(F, T),
    overhead(T, reduction, 10, C),
    assertion(C == 100).

test(extrapolation_fits_every_point) :-
    % a dip at the last point must not set the slope: the least-squares
    % line through (1,100) (2,200) (3,300) (4,250) is 75 + 55 P
    variant("overhead(fork_join", "overhead(fork_join, 1, 100).\noverhead(fork_join, 2, 200).\n\c
             overhead(fork_join, 3, 300).\noverhead(fork_join, 4, 250).", F),
    load_cost_table(F, T),
    overhead(T, fork_join, 8, C),
    assertion(C == 515).

test(extrapolation_never_below_last_point) :-
    % falling measurements fit 60 - 10 P, which is 0 at P = 6
    variant("overhead(reduction", "overhead(reduction, 1, 50).\noverhead(reduction, 2, 40).\n\c
             overhead(reduction, 3, 30).", F),
    load_cost_table(F, T),
    overhead(T, reduction, 6, C),
    assertion(C == 30).

test(overhead_single_point) :-
    variant("overhead(reduction", "overhead(reduction, 1, 7).", F),
    load_cost_table(F, T),
    overhead(T, reduction, 6, C),
    assertion(C == 7).

:- end_tests(cost).
