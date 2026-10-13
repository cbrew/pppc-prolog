:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/label)).
:- use_module(library(pppc/dataflow)).
:- use_module(library(pppc/parloop)).

:- begin_tests(parloop).

loops(Text, Loops) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P),
    check_program(P, program(_, [_, block(_, [Decls, _, Body], _)], _), []),
    findall(V, (member(var_decl(_, [Ns, _], _), Decls), member(V, Ns)), Vars),
    label_body(Body, LSs),
    with_dataflow(LSs, Vars, [], classify_loops(LSs, Loops)).

jacobi(
    "program jacobi;\n\c
     const n = 4; eps = 1.0e-6;\n\c
     var a: array[1..n, 1..n] of real; b: array[1..n] of real;\n\c
         x, new_x: array[1..n] of real;\n\c
         i, j: integer; sum, error: real;\n\c
     begin\n\c
       repeat\n\c
         error := 0;\n\c
         for i := 1 to n do\n\c
         begin\n\c
           sum := 0;\n\c
           for j := 1 to n do\n\c
             sum := sum + a[i, j] * x[j];\n\c
           new_x[i] := x[i] + (b[i] - sum) / a[i, i];\n\c
           error := error max abs(b[i] - sum)\n\c
         end;\n\c
         x := new_x\n\c
       until error < eps\n\c
     end.").

test(jacobi_classification) :-
    jacobi(T), loops(T, Loops),
    Loops = [loop([1,2], 9, parallel, Classes), loop([1,2,2], 12, nested(9), [])],
    msort(Classes, Sorted),
    assertion(Sorted == [ a-read_only, b-read_only, error-associative(max), i-index,
                          j-local, new_x-distributed, sum-local, x-read_only ]).

body_loops(Decls, Body, Loops) :-
    format(string(T), "program t;~nvar ~w~nbegin~n~w~nend.", [Decls, Body]),
    loops(T, Loops).

test(carried_array_dependence) :-
    body_loops("i, n: integer; a: array[1..10] of integer;",
               "for i := 2 to n do a[i] := a[i-1] + 1", [loop(_, _, V, _)]),
    assertion(V == serial([dependent(a)])).

test(non_index_subscript) :-
    body_loops("i, n: integer; a: array[1..20] of integer;",
               "for i := 1 to n do a[2*i] := i", [loop(_, _, V, _)]),
    assertion(V == serial([dependent(a)])).

test(scalar_read_before_write) :-
    body_loops("i, n, t: integer; a: array[1..10] of integer;",
               "for i := 1 to n do begin a[i] := t; t := i end", [loop(_, _, V, _)]),
    assertion(V == serial([dependent(t)])).

test(write_in_loop) :-
    body_loops("i, n: integer;", "for i := 1 to n do writeln(i)", [loop(_, _, V, _)]),
    assertion(V == serial([io])).

test(user_call_in_loop) :-
    loops("program t;\nvar i, n: integer; s: real;\n\c
           function f(k: integer): real; begin f := k end;\n\c
           begin for i := 1 to n do s := s + f(i) end.", [loop(_, _, V, _)]),
    assertion(V = serial(Rs)), assertion(memberchk(call, Rs)).

test(mixed_operators_not_associative) :-
    body_loops("i, n: integer; s: real;",
               "for i := 1 to n do begin s := s + i; s := s * 2 end", [loop(_, _, V, _)]),
    assertion(V == serial([dependent(s)])).

test(sum_reduction) :-
    body_loops("i, n: integer; s: real;", "for i := 1 to n do s := s + 1.0 / i",
               [loop(_, _, parallel, Cs)]),
    assertion(memberchk(s-associative(+), Cs)).

test(local_escaping_is_dependent) :-
    body_loops("i, n: integer; t: real; a: array[1..10] of real;",
               "for i := 1 to n do begin t := i; a[i] := t end; writeln(t)",
               [loop(_, _, V, _)]),
    assertion(V == serial([dependent(t)])).

:- end_tests(parloop).
