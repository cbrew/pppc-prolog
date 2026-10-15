:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/transform)).
:- use_module(library(pppc/cost)).
:- use_module(library(pppc/predict)).
:- use_module(library(pppc)).

/*  Expected times are worked out by hand against test/costs/unit.pl:
    every operation and cost/2 key costs 1, default_trips is 25,
    fork/join costs 100 P and a reduction 10 P. */

:- begin_tests(predict).

predict(Text, N, Prediction, Routines) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P),
    check_program(P, Typed, []),
    analyse_program(Typed, Rs0),
    load_cost_table('test/costs/unit.pl', Table),
    decide(Rs0, Table, N, Routines, Prediction).

serial(Text, S) :-
    predict(Text, 4, prediction(_, S, _), _).

main_loops(Routines, Loops) :-
    memberchk(routine(program, _, Loops, _), Routines).

test(straight_line) :-
    % x := 1: store 1.  y := x + 2: op 1 + store 1.
    serial("program t;\nvar x, y: integer;\nbegin x := 1; y := x + 2 end.", S),
    assertion(S == 3).

test(if_takes_mean_of_branches) :-
    % cond 0 + if 1 + (then 1 + else 0) / 2
    serial("program t;\nvar x: integer; b: boolean;\nbegin if b then x := 1 end.", S),
    assertion(S == 3r2).

test(constant_for) :-
    % 10 trips * (body: op 1 + store 1, + loop 1)
    serial("program t;\nvar i, s: integer;\nbegin for i := 1 to 10 do s := s + i end.", S),
    assertion(S == 30).

test(downto_counts_trips) :-
    serial("program t;\nvar i, s: integer;\nbegin for i := 10 downto 1 do s := s + i end.", S),
    assertion(S == 30).

test(empty_range_costs_nothing) :-
    serial("program t;\nvar i, s: integer;\nbegin for i := 5 to 1 do s := s + i end.", S),
    assertion(S == 0).

test(unknown_bounds_use_default_trips) :-
    % 25 trips * 3
    serial("program t;\nvar i, n, s: integer;\nbegin for i := 1 to n do s := s + i end.", S),
    assertion(S == 75).

test(while_loop) :-
    % 25 * (body 2 + cond 1 + loop 1)
    serial("program t;\nvar x: integer;\nbegin while x < 10 do x := x + 1 end.", S),
    assertion(S == 100).

test(repeat_loop) :-
    serial("program t;\nvar x: integer;\nbegin repeat x := x + 1 until x >= 10 end.", S),
    assertion(S == 100).

test(whole_array_assignment) :-
    % one store per element
    serial("program t;\nvar a, b: array[1..10] of real;\nbegin a := b end.", S),
    assertion(S == 10).

test(zero_assignment) :-
    % 3 records of 2 reals: 6 stores
    serial("program t;\ntype pt = record x, y: real end;\nvar r: array[1..3] of pt;\n\c
            begin r := 0 end.", S),
    assertion(S == 6).

test(procedure_call) :-
    % body of p: op 1 + store 1 = 2; a call: 2 + call 1 + param 1 = 4
    serial("program t;\nprocedure p(x: integer); var y: integer;\n\c
            begin y := x * 2 end;\nbegin p(3); p(4) end.", S),
    assertion(S == 8).

test(function_call) :-
    % body of f: 2; call 2 + 1 + 1 = 4; assignment 4 + store 1
    serial("program t;\nvar y: integer;\nfunction f(x: integer): integer;\n\c
            begin f := x + 1 end;\nbegin y := f(2) end.", S),
    assertion(S == 5).

test(recursion_terminates) :-
    % body of f: cond 1 + if 1 + (then 1 + else 5) / 2 = 5, where the
    % else branch is n * f(n - 1) := op 1 + (recursive call: 0 + call 1
    % + arg 1 + param 1) + store 1. Main: call 5 + 1 + 1, store 1.
    serial("program t;\nvar y: integer;\nfunction f(n: integer): integer;\n\c
            begin if n = 0 then f := 1 else f := n * f(n - 1) end;\n\c
            begin y := f(5) end.", S),
    assertion(S == 8).

test(constant_expression_bounds) :-
    % n is the constant 10, so 0 .. n - 1 is 10 trips * 3 = 30, plus
    % 1 for evaluating the bound n - 1
    serial("program t;\nconst n = 10;\nvar i, s: integer;\n\c
            begin for i := 0 to n - 1 do s := s + i end.", S),
    assertion(S == 31).

test(negated_constant_bound) :-
    % n downto -n is 21 trips * 3 = 63, plus 1 for the negation
    serial("program t;\nconst n = 10;\nvar i, s: integer;\n\c
            begin for i := n downto -n do s := s + i end.", S),
    assertion(S == 64).

%   chain(+K, -Text): procedures f0 .. fK, each fJ calling f(J-1) twice.
chain(K, Text) :-
    numlist(1, K, Js),
    maplist(chain_proc, Js, Procs),
    atomic_list_concat(Procs, Body),
    format(string(Text),
           "program t;\nprocedure f0; var x: integer; begin x := 1 end;\n~w\c
            begin f~d end.", [Body, K]).

chain_proc(J, Text) :-
    J0 is J - 1,
    format(string(Text), "procedure f~d; begin f~d; f~d end;\n", [J, J0, J0]).

test(call_chain_costed_once_per_routine, [timeout(10)]) :-
    % f0 = 1, fJ = 2 * (f(J-1) + call 1) = 3 * 2^J - 2; main adds a call.
    % Costing each call afresh would visit f0 2^24 times.
    chain(24, Text),
    serial(Text, S),
    assertion(S =:= 3 * 2^24 - 1).

test(mutual_recursion_terminates) :-
    % p: if 1 + (q's body + call 1) / 2, q: if 1 + (0 + call 1) / 2
    % when called from p, so p = 1 + (3/2 + 1) / 2 = 9/4; main + call 1.
    serial("program t;\nvar b: boolean;\nprocedure p; begin if b then q end;\n\c
            procedure q; begin if b then p end;\nbegin p end.", S),
    assertion(S == 13r4).

big_loop("program t;\nvar i: integer; a: array[1..1000] of real;\n\c
          begin\nfor i := 1 to 1000 do a[i] := i * 2.0 end.").

test(profitable_loop_stays_parallel) :-
    % body: index 1 + (itor 1 + op 1) + store 1 = 4, iteration 5;
    % serial 1000 * 5; parallel at 4: 250 * 5 + fork/join 400
    big_loop(Text),
    predict(Text, 4, prediction(Times, S, _), Rs),
    main_loops(Rs, [loop(_, 4, V, _)]),
    assertion(V == parallel),
    assertion(S == 5000),
    assertion(Times == [loop_time(program, 4, 5000, 1650)]).

test(unprofitable_at_one_thread) :-
    % parallel at 1: 1000 * 5 + 100 = 5100, not less than 5000
    big_loop(Text),
    predict(Text, 1, _, Rs),
    main_loops(Rs, [loop(_, 4, V, _)]),
    assertion(V == serial([unprofitable(5000, 5100)])).

test(speedups) :-
    % P=1: 5000/5100; P=2: 5000/(500*5+200); P=3: 5000/(334*5+300);
    % P=4: 5000/1650
    big_loop(Text),
    predict(Text, 4, prediction(_, _, Speedups), _),
    assertion(Speedups == [1-50r51, 2-50r27, 3-500r197, 4-100r33]).

test(speedups_thin_out_beyond_eight) :-
    % every P up to 8, then powers of two, then N
    big_loop(Text),
    predict(Text, 20, prediction(_, _, Speedups), _),
    pairs_keys(Speedups, Ps),
    assertion(Ps == [1, 2, 3, 4, 5, 6, 7, 8, 16, 20]).

test(overheads_extrapolate_beyond_table) :-
    % at 8: 125 * 5 + fork/join extrapolated to 800
    big_loop(Text),
    predict(Text, 8, prediction([loop_time(_, _, _, Par)], _, _), _),
    assertion(Par == 1425).

test(reductions_add_overhead) :-
    % body: index 1 + op 1 + store 1 = 3, iteration 4;
    % parallel at 4: 250 * 4 + 400 + one reduction 40
    predict("program t;\nvar i: integer; s: real; a: array[1..1000] of real;\n\c
             begin\nfor i := 1 to 1000 do s := s + a[i] end.", 4,
            prediction(Times, _, _), _),
    assertion(Times == [loop_time(program, 4, 4000, 1440)]).

test(small_loop_unprofitable) :-
    % 10 * 3 = 30 serial; parallel 3 * 3 + 400 + 40 = 449
    predict("program t;\nvar i, s: integer;\nbegin\nfor i := 1 to 10 do s := s + i end.",
            4, _, Rs),
    main_loops(Rs, [loop(_, 4, V, _)]),
    assertion(V == serial([unprofitable(30, 449)])).

test(inner_loops_stay_nested) :-
    % inner: 2 * (index 2 + store 1 + loop 1) = 8; outer 2 * 9 = 18;
    % parallel 1 * 9 + 400
    predict("program t;\nvar i, j: integer; a: array[1..2, 1..2] of real;\nbegin\n\c
             for i := 1 to 2 do\nfor j := 1 to 2 do a[i, j] := 0.0 end.", 4, _, Rs),
    main_loops(Rs, Loops),
    assertion(Loops = [loop(_, 4, serial([unprofitable(18, 409)]), _),
                       loop(_, 5, nested(4), [])]).

test(loops_in_routines_decided) :-
    predict("program t;\nprocedure p; var i: integer; a: array[1..1000] of real;\n\c
             begin\nfor i := 1 to 1000 do a[i] := i * 2.0 end;\nbegin p end.", 4,
            prediction(Times, S, _), Rs),
    memberchk(routine(p, _, [loop(_, 4, V, _)], _), Rs),
    assertion(V == parallel),
    assertion(Times == [loop_time(p, 4, 5000, 1650)]),
    % main: the body of p + call 1
    assertion(S == 5001).

%   points(Ps) asks for speedups at thread counts that are not speedup
%   points of N; the loops are still chosen at N.
test(speedups_at_any_points) :-
    pppc_predict('test/programs/pi.pas', [threads(12), points([1, 10, 12])],
                 prediction(_, _, Speedups)),
    pairs_keys(Speedups, Ps),
    assertion(Ps == [1, 10, 12]),
    pppc_predict('test/programs/pi.pas', [threads(12)], prediction(_, _, Default)),
    memberchk(12-S12, Default),
    assertion(memberchk(12-S12, Speedups)).

test(bad_points, throws(pppc(bad_threads([0, 2])))) :-
    pppc_predict('test/programs/pi.pas', [points([0, 2])], _).

:- end_tests(predict).
