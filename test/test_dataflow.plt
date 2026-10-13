:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/label)).
:- use_module(library(pppc/dataflow)).

:- begin_tests(dataflow).

%   main_body(+Text, -Labelled, -Vars)
main_body(Text, LSs, Vars) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P),
    check_program(P, program(_, [_, block(_, [Decls, _, Body], _)], _), []),
    findall(V, (member(var_decl(_, [Ns, _], _), Decls), member(V, Ns)), Vars),
    label_body(Body, LSs).

%   The fragment of section 4.4.6.
paper_fragment(
    "program t;\n\c
     var i, n: integer; x, y, z, w: real;\n\c
     begin\n\c
       for i := 1 to n do\n\c
       begin\n\c
         x := y / z;\n\c
         if x > w then y := x\n\c
         else z := x\n\c
       end\n\c
     end.").

test(paper_labels) :-
    paper_fragment(T), main_body(T, LSs, _),
    assertion(LSs = [lbl([1], for(_, [_, _, _, up,
                       [ lbl([1,1], assign(_, _, _)),
                         lbl([1,2], if(_, [_, lbl([1,2,1], assign(_, _, _)),
                                              lbl([1,2,2], assign(_, _, _))], _))
                       ]], _))]).

test(paper_reach_facts) :-
    paper_fragment(T), main_body(T, LSs, Vars),
    with_dataflow(LSs, Vars, [],
                  findall(V-S-U, (member(V, [x, y, z]), reach(V, S, U),
                                  inside([1], S), inside([1], U)), Facts0)),
    sort(Facts0, Facts),
    assertion(Facts == [ x-[1,1]-[1,2], x-[1,1]-[1,2,1], x-[1,1]-[1,2,2],
                         y-[1,2,1]-[1,1], z-[1,2,2]-[1,1] ]).

test(carried) :-
    paper_fragment(T), main_body(T, LSs, Vars),
    with_dataflow(LSs, Vars, [],
                  ( assertion(\+ carried([1], x, _)),
                    assertion(carried([1], y, [1,1])),
                    assertion(carried([1], z, [1,1])) )).

test(reset_inside_loop_not_carried) :-
    main_body("program t;\nvar i, j, n: integer; s: real; a: array[1..5] of real;\n\c
               begin for i := 1 to n do begin s := 0; for j := 1 to n do s := s + j;\n\c
               a[i] := s end end.", LSs, Vars),
    with_dataflow(LSs, Vars, [],
                  ( assertion(\+ carried([1], s, _)),
                    assertion(carried([1,2], s, [1,2,1])) )).

test(tables_reset_between_runs) :-
    paper_fragment(T), main_body(T, LSs, Vars),
    with_dataflow(LSs, Vars, [], true),
    main_body("program t;\nvar a: integer;\nbegin a := 1 end.", LSs2, Vars2),
    with_dataflow(LSs2, Vars2, [], findall(S-U, reach(x, S, U), R)),
    assertion(R == []).

:- end_tests(dataflow).
