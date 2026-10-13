:- use_module(library(pppc/codegen)).

:- begin_tests(codegen).

test(arithmetic_parenthesised) :-
    c_expr(op2(1, [+, id(1, [a], integer), op2(1, [*, id(1, [b], integer),
                                                   iconst(1, [2], integer)], integer)],
               integer), C),
    assertion(C == "(a + (b * 2))").

test(pascal_operators) :-
    c_expr(op2(1, [and, op2(1, ['<>', id(1, [i], integer), iconst(1, [0], integer)], boolean),
                   op1(1, [not, id(1, [p], boolean)], boolean)], boolean), C),
    assertion(C == "((i != 0) && (!p))").

test(div_mod_and_widening) :-
    c_expr(op2(1, [div, id(1, [i], integer),
                   op2(1, [mod, id(1, [j], integer), iconst(1, [3], integer)], integer)],
               integer), C1),
    assertion(C1 == "(i / (j % 3))"),
    c_expr(itor(1, [id(1, [i], integer)], real), C2),
    assertion(C2 == "((double)i)").

test(min_max_by_type) :-
    c_expr(op2(1, [max, id(1, [e], real), fconst(1, [0.5], real)], real), C),
    assertion(C == "pppc_max_r(e, 0.5)").

test(nested_index_offsets) :-
    A = id(1, [a], array(1, 3, array(0, 3, real))),
    c_expr(index(1, [index(1, [A, id(1, [i], integer)], array(0, 3, real)),
                     iconst(1, [2], integer)], real), C),
    assertion(C == "a.e[i - 1].e[2]").

test(var_param_and_reserved_names) :-
    c_expr(op2(1, [+, vparam(1, [x], integer), id(1, [int], integer)], integer), C),
    assertion(C == "((*x) + int_)").

test(builtins) :-
    c_expr(builtin(1, [ln, [id(1, [x], real)]], real), C1), assertion(C1 == "log(x)"),
    c_expr(builtin(1, [abs, [id(1, [i], integer)]], integer), C2), assertion(C2 == "labs(i)"),
    c_expr(builtin(1, [random, []], real), C3), assertion(C3 == "pppc_random()").

test(string_escapes) :-
    c_expr(string(1, [`say "hi"\\`], string), C),
    assertion(C == "\"say \\\"hi\\\"\\\\\"").

test(serial_for) :-
    c_stmt(for(4, [id(4, [i], integer), iconst(4, [1], integer), id(4, [n], integer), up,
                   assign(5, [id(5, [s], integer), id(5, [i], integer)], void)], void), C),
    lines(C, Lines),
    assertion(Lines == [ "{",
                         "    long pppc_hi = n;",
                         "    for (i = 1; i <= pppc_hi; i++) { /* line 4 */",
                         "        s = i; /* line 5 */",
                         "    }",
                         "}" ]).

test(omp_for_pragma) :-
    c_stmt(omp_for(4, [id(4, [i], integer), id(4, [n], integer), iconst(4, [1], integer), down,
                       empty(4, [], void),
                       [private([t]), shared([a, b]), reduction(max, [e])]], void), C),
    assertion(sub_string(C, _, _, _, "long pppc_lo = 1;\n    #pragma omp parallel for private(t) shared(a, b) reduction(max:e)\n    for (i = n; i >= pppc_lo; i--) {")).

test(zero_assignment) :-
    c_stmt(zero_assign(3, [id(3, [v], array(1, 5, real))], void), C),
    assertion(C == "memset(&v, 0, sizeof v); /* line 3 */\n").

test(writeln) :-
    c_stmt(write(2, [true, [string(2, [`x=`], string), id(2, [x], real), id(2, [b], boolean)]],
                 void), C),
    lines(C, Lines),
    assertion(Lines == [ "fputs(\"x=\", stdout); /* line 2 */",
                         "printf(\"%.15g\", x); /* line 2 */",
                         "fputs(b ? \"TRUE\" : \"FALSE\", stdout); /* line 2 */",
                         "putchar('\\n'); /* line 2 */" ]).

test(typedefs_inner_first) :-
    generate_c(program(1, [t, block(1, [[var_decl(2, [[m], array(1, 2, array(1, 3, real))], void)],
                                         [], compound(3, [[]], void)], void)], void), C),
    once(sub_string(C, B1, _, _, "typedef struct { double e[3]; } pppc_t1;")),
    once(sub_string(C, B2, _, _, "typedef struct { pppc_t1 e[2]; } pppc_t2;")),
    assertion(B1 < B2),
    assertion(sub_string(C, _, _, _, "static pppc_t2 m;")).

%   lines(+Text, -Lines): split generated code into lines, dropping the
%   empty string after the final newline.
lines(Text, Lines) :-
    split_string(Text, "\n", "", Parts),
    once(append(Lines, [""], Parts)).

:- end_tests(codegen).
