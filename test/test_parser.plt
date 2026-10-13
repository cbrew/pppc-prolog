:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).

:- begin_tests(parser).

expr(Text, E) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_expression(Ts, E).
stmt(Text, S) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_statement(Ts, S).
prog(Text, P) :-
    string_codes(Text, Cs), tokenize(Cs, Ts), parse_program(Ts, P).

test(precedence) :-
    expr("a + b * c", E),
    assertion(E == op2(1, [+, id(1, [a]), op2(1, [*, id(1, [b]), id(1, [c])])])).

test(left_assoc) :-
    expr("a - b - c", E),
    assertion(E == op2(1, [-, op2(1, [-, id(1, [a]), id(1, [b])]), id(1, [c])])).

test(min_max_relational_level) :-
    expr("e max abs(x - s)", E),
    assertion(E == op2(1, [max, id(1, [e]),
                           fcall(1, [abs, [op2(1, [-, id(1, [x]), id(1, [s])])]])])).

test(unary_minus_binds_term) :-
    expr("-a * b", E),
    assertion(E == op1(1, [-, op2(1, [*, id(1, [a]), id(1, [b])])])).

test(index_and_field) :-
    expr("a[i, j] + c.re", E),
    assertion(E == op2(1, [+, index(1, [id(1, [a]), [id(1, [i]), id(1, [j])]]),
                           field(1, [id(1, [c]), re])])).

test(paper_if_example) :-
    stmt("if a > b then\n c.re := a + b\nelse c.im := 2.0 * sin(a)", S),
    assertion(S == if(1, [ op2(1, [>, id(1, [a]), id(1, [b])]),
                           assign(2, [field(2, [id(2, [c]), re]),
                                      op2(2, [+, id(2, [a]), id(2, [b])])]),
                           assign(3, [field(3, [id(3, [c]), im]),
                                      op2(3, [*, fconst(3, [2.0]),
                                              fcall(3, [sin, [id(3, [a])]])])])
                         ])).

test(if_without_else) :-
    stmt("if p then x := 1", S),
    assertion(S = if(1, [_, _, empty(1, [])])).

test(for_downto) :-
    stmt("for i := n downto 1 do s := s + i", S),
    assertion(S = for(1, [id(1, [i]), id(1, [n]), iconst(1, [1]), down, assign(1, _)])).

test(repeat_and_writeln) :-
    stmt("repeat x := x + 1; writeln('x=', x) until x > 9", S),
    assertion(S = repeat(1, [[assign(1, _), write(1, [true, [string(1, [`x=`]), id(1, [x])]])],
                             op2(1, [>, _, _])])).

test(pcall_no_args) :-
    stmt("init", S),
    assertion(S == pcall(1, [init, []])).

test(program) :-
    prog("program t;\nconst n = 10;\ntype vec = array[1..n] of real;\n\c
          var v: vec; i: integer;\n\c
          function sq(x: real): real; begin sq := x * x end;\n\c
          begin for i := 1 to n do v[i] := sq(i) end.", P),
    assertion(P = program(1, [t, block(2, [ [const_decl(2, [n, iconst(2, [10])])],
                                             [type_decl(3, [vec, array(3, _)])],
                                             [var_decl(4, [[v], tname(4, [vec])]),
                                              var_decl(4, [[i], tname(4, [integer])])],
                                             [proc(5, [sq, [param(5, [value, [x], tname(5, [real])])],
                                                       tname(5, [real]), block(5, _)])],
                                             compound(6, [[for(6, _)]]) ])])).

test(missing_then, throws(pppc(syntax(1, then, id(x))))) :-
    stmt("if p x := 1", _).

test(missing_semicolon_reports_found, throws(pppc(syntax(2, ;, kw(begin))))) :-
    prog("program t\nbegin end.", _).

test(bad_factor, throws(pppc(syntax(1, expression, punct(*))))) :-
    expr("a + * b", _).

:- end_tests(parser).
