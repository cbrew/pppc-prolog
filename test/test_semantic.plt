:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).

:- begin_tests(semantic).

check(Text, Typed, Errors) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P),
    check_program(P, Typed, Errors).

%   body_stmts(+Text, -Stmts): wrap declarations + body in a program
%   and return the typed statements of the main body.
body(Decls, Body, Stmts, Errors) :-
    format(string(Text), "program t;~n~w~nbegin~n~w~nend.", [Decls, Body]),
    check(Text, program(_, [t, block(_, [_, _, compound(_, [Stmts], void)], void)], void),
          Errors).

test(paper_typed_if) :-
    body("var a, b: real; c: record re, im: real end;",
         "if a > b then c.re := a + b else c.im := 2.0 * sin(a)",
         [S], Errs),
    assertion(Errs == []),
    C = record([re-real, im-real]),
    assertion(S == if(4, [ op2(4, [>, id(4, [a], real), id(4, [b], real)], boolean),
                           assign(4, [field(4, [id(4, [c], C), re], real),
                                      op2(4, [+, id(4, [a], real), id(4, [b], real)], real)],
                                  void),
                           assign(4, [field(4, [id(4, [c], C), im], real),
                                      op2(4, [*, fconst(4, [2.0], real),
                                              builtin(4, [sin, [id(4, [a], real)]], real)],
                                          real)],
                                  void)
                         ], void)).

test(widening) :-
    body("var x: real; i: integer;", "x := i + x", [S], []),
    assertion(S == assign(4, [id(4, [x], real),
                              op2(4, [+, itor(4, [id(4, [i], integer)], real),
                                      id(4, [x], real)], real)], void)).

test(slash_widens_both) :-
    body("var x: real; i: integer;", "x := i / 2", [S], []),
    assertion(S = assign(_, [_, op2(_, [/, itor(_, _, real), itor(_, _, real)], real)], void)).

test(constants_substituted) :-
    body("const n = 10; m = n * 2 + 1; eps = 1.0e-6; var x: real;",
         "x := m * eps", [S], []),
    assertion(S == assign(4, [id(4, [x], real),
                              op2(4, [*, itor(4, [iconst(4, [21], integer)], real),
                                      fconst(4, [1.0e-6], real)], real)], void)).

test(multi_dim_arrays_nest) :-
    body("const n = 3; var a: array[1..n, 0..n] of real; i: integer;",
         "a[i, 2] := 0.0", [S], []),
    assertion(S == assign(4, [index(4, [index(4, [id(4, [a], array(1, 3, array(0, 3, real))),
                                                  id(4, [i], integer)],
                                            array(0, 3, real)),
                                        iconst(4, [2], integer)], real),
                              fconst(4, [0.0], real)], void)).

test(zero_assignment) :-
    body("var a: array[1..5] of record x: real; n: integer end;", "a := 0", [S], []),
    assertion(S = zero_assign(4, [id(4, [a], _)], void)).

test(min_max) :-
    body("var e: real; i: integer;", "e := e max i", [S], []),
    assertion(S == assign(4, [id(4, [e], real),
                              op2(4, [max, id(4, [e], real), itor(4, [id(4, [i], integer)], real)],
                                  real)], void)).

test(routines) :-
    check("program t;\nvar g: integer;\n\c
           procedure p(var x: integer; y: integer); begin x := y end;\n\c
           function f(n: integer): integer; begin f := n + g end;\n\c
           begin p(g, f(2)) end.", program(_, [t, block(_, [_, [P, F], Body], void)], void), Errs),
    assertion(Errs == []),
    assertion(P = proc(3, [p, [param(3, [var, [x], integer], void),
                               param(3, [value, [y], integer], void)], none,
                           block(3, [[], [], compound(3, [[assign(3, [vparam(3, [x], integer),
                                                                     id(3, [y], integer)], void)]],
                                                     void)], void)], void)),
    assertion(F = proc(4, [f, _, integer,
                           block(4, [[], [], compound(4, [[assign(4, [fresult(4, [f], integer), _],
                                                                  void)]], void)], void)], void)),
    assertion(Body == compound(5, [[pcall(5, [p, [addr(5, [id(5, [g], integer)], integer),
                                                  fcall(5, [f, [iconst(5, [2], integer)]], integer)]],
                                         void)]], void)).

test(errors_collected) :-
    body("var x: real; b: boolean;",
         "x := b;\nif x then y := 1;\nx := sqrt(b)",
         _, Errs),
    assertion(Errs == [ pppc(semantic(4, assign_mismatch(real, boolean))),
                        pppc(semantic(5, not_boolean)),
                        pppc(semantic(5, undeclared(y))),
                        pppc(semantic(6, bad_arguments(sqrt)))
                      ]).

test(no_cascade) :-
    body("var x: real;", "x := (y + 1) * 2", _, Errs),
    assertion(Errs == [pppc(semantic(4, undeclared(y)))]).

test(redeclared_and_shadowing) :-
    check("program t;\nvar x, x: integer;\nprocedure p; var x: real; begin x := 1.5 end;\n\c
           begin end.", _, Errs),
    assertion(Errs == [pppc(semantic(2, redeclared(x)))]).

test(bad_zero_assignment) :-
    body("var a: array[1..2] of boolean;", "a := 0", _, Errs),
    assertion(Errs == [pppc(semantic(4, bad_zero_assignment))]).

test(arg_count) :-
    check("program t;\nprocedure p(a: integer); begin end;\nbegin p(1, 2) end.", _, Errs),
    assertion(Errs == [pppc(semantic(3, arg_count(p, 1, 2)))]).

%   A var parameter cannot be a for control variable (ISO Pascal
%   requires a variable of the routine; OpenMP cannot iterate (*k)).
test(var_param_for_variable) :-
    check("program t;\nvar s: integer;\nprocedure p(var k: integer);\n\c
           begin for k := 1 to 10 do s := s + k end;\nbegin end.", _, Errs),
    assertion(Errs == [pppc(semantic(4, bad_for_variable))]).

:- end_tests(semantic).
