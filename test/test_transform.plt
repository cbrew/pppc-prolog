:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/transform)).

:- begin_tests(transform).

typed(Text, Typed) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P),
    check_program(P, Typed, []).

test(parallel_loop_becomes_omp_for) :-
    typed("program t;\nvar i, n: integer; s, x: real; a: array[1..9] of real;\n\c
           begin for i := 1 to n do begin x := i; a[i] := x; s := s + x end end.", T),
    parallelize_program(T, P, _),
    P = program(_, [t, block(_, [_, [], compound(_, [[S]], void)], void)], void),
    assertion(S = omp_for(3, [id(_, [i], _), _, _, up, compound(3, [_], void),
                              [private([x]), shared([a]), reduction(+, [s])]], void)).

test(serial_loop_unchanged) :-
    typed("program t;\nvar i: integer;\nbegin for i := 1 to 3 do writeln(i) end.", T),
    parallelize_program(T, P, _),
    P = program(_, [t, block(_, [_, [], compound(_, [[S]], void)], void)], void),
    assertion(S = for(3, _, void)).

test(loops_inside_procedures) :-
    typed("program t;\nconst n = 5; type v = array[1..n] of real;\n\c
           function sum(a: v): real; var i: integer; s: real;\n\c
           begin s := 0; for i := 1 to n do s := s + a[i]; sum := s end;\n\c
           begin end.", T),
    analyse_program(T, Rs),
    assertion(Rs = [routine(program, [], [], _), routine(sum, _, [loop(_, 4, parallel, _)], _)]).

test(result_and_var_params_escape) :-
    typed("program t;\nprocedure p(var x: integer; n: integer); var i, t: integer;\n\c
           begin for i := 1 to n do t := i; x := t end;\nbegin end.", T),
    analyse_program(T, [_, routine(p, _, [loop(_, 3, V, _)], _)]),
    assertion(V == serial([dependent(t)])).

%   The main program is keyed `program`, a reserved word, so a user
%   procedure called main keeps its own body.
test(procedure_named_main) :-
    typed("program t;\nvar x: integer;\nprocedure main; begin x := x + 1 end;\n\c
           begin x := 10; main end.", T),
    parallelize_program(T, P, Rs),
    assertion(Rs = [routine(program, _, _, _), routine(main, _, _, _)]),
    P = program(_, [t, block(_, [_, [proc(_, [main, [], none, block(_, [_, _, PBody], _)], _)],
                                  MBody], _)], _),
    assertion(PBody = compound(3, [[assign(3, _, _)]], void)),
    assertion(MBody = compound(4, [[assign(4, _, _), pcall(4, [main, []], void)]], void)).

:- end_tests(transform).
