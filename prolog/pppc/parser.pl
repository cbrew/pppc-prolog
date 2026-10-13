:- module(pppc_parser,
          [ parse_program/2,            % +Tokens, -Tree
            parse_expression/2,         % +Tokens, -Tree
            parse_statement/2           % +Tokens, -Tree
          ]).
:- use_module(library(apply)).

/** <module> TAU-Pascal parser

A DCG over the token list produced by pppc_lexer. Builds the parse
tree in the paper's format name(Line, Args) (spec section 5.2).

Error handling: alternatives are tried only where the grammar is
genuinely ambiguous. Once a construct is recognised the parser is
committed and uses expect//1 (or must_* helpers), which throw
pppc(syntax(Line, Expected, Found)) if the next token is wrong.
*/

%!  parse_program(+Tokens, -Tree) is det.
%!  parse_expression(+Tokens, -Tree) is det.
%!  parse_statement(+Tokens, -Tree) is det.
%
%   Parse a complete token list (which ends in tok(_, eof)) as a
%   program, an expression or a single statement.  The last two exist
%   for unit testing.

parse_program(Tokens, Tree) :-
    phrase((program(Tree), expect(eof)), Tokens).
parse_expression(Tokens, Tree) :-
    phrase((expression(Tree), expect(eof)), Tokens).
parse_statement(Tokens, Tree) :-
    phrase((statement(Tree), expect(eof)), Tokens).

                 /*******************************
                 *        TOKEN HELPERS         *
                 *******************************/

kw(K, L)    --> [tok(L, kw(K))].
p(P, L)     --> [tok(L, punct(P))].
ident(N, L) --> [tok(L, id(N))].

%   line(-L)// unifies L with the line of the next token, consuming nothing.
line(L), [T] --> [T], { T = tok(L, _) }.

%   expect(+What)// consumes the expected token or throws a syntax error.
%   What is kw(K), punct P (an atom), eof, or ident(N).
expect(eof) --> [tok(_, eof)], !.
expect(kw(K)) --> kw(K, _), !.
expect(ident(N)) --> ident(N, _), !.
expect(P) --> { atom(P) }, p(P, _), !.
expect(What) --> syntax_error(What).

syntax_error(What), [tok(L, Found)] -->
    [tok(L, Found)],
    { expected_name(What, Name),
      throw(pppc(syntax(L, Name, Found)))
    }.

expected_name(kw(K), K) :- !.
expected_name(ident(_), identifier) :- !.
expected_name(X, X).

                 /*******************************
                 *     PROGRAM AND BLOCKS       *
                 *******************************/

program(program(L, [Name, Block])) -->
    ( kw(program, L) -> [] ; syntax_error(kw(program)) ),
    expect(ident(Name)), expect(;),
    block(Block),
    expect('.').

block(block(L, [Consts, Types, Vars, Procs, Body])) -->
    line(L),
    const_part(Consts),
    type_part(Types),
    var_part(Vars),
    proc_part(Procs),
    ( line(BL), kw(begin, _) -> [] ; syntax_error(kw(begin)) ),
    stmt_sequence(Stmts),
    expect(kw(end)),
    { Body = compound(BL, [Stmts]) }.

const_part(Cs) --> kw(const, _), !, const_decl(C), const_decls(Cs0), { Cs = [C|Cs0] }.
const_part([]) --> [].

const_decls([C|Cs]) --> const_decl(C), !, const_decls(Cs).
const_decls([]) --> [].

const_decl(const_decl(L, [Name, E])) -->
    ident(Name, L), expect(=), expression(E), expect(;).

type_part(Ts) --> kw(type, _), !, type_decl(T), type_decls(Ts0), { Ts = [T|Ts0] }.
type_part([]) --> [].

type_decls([T|Ts]) --> type_decl(T), !, type_decls(Ts).
type_decls([]) --> [].

type_decl(type_decl(L, [Name, T])) -->
    ident(Name, L), expect(=), type_expr(T), expect(;).

var_part(Vs) --> kw(var, _), !, var_decl(V), var_decls(Vs0), { Vs = [V|Vs0] }.
var_part([]) --> [].

var_decls([V|Vs]) --> var_decl(V), !, var_decls(Vs).
var_decls([]) --> [].

var_decl(var_decl(L, [Names, T])) -->
    ident_list(Names, L), expect(:), type_expr(T), expect(;).

ident_list([N|Ns], L) --> ident(N, L), ident_list_rest(Ns).
ident_list_rest([N|Ns]) --> p(',', _), !, expect(ident(N)), ident_list_rest(Ns).
ident_list_rest([]) --> [].

proc_part([P|Ps]) --> proc_decl(P), !, proc_part(Ps).
proc_part([]) --> [].

proc_decl(proc(L, [Name, Params, none, Block])) -->
    kw(procedure, L), !,
    expect(ident(Name)), params(Params), expect(;),
    block(Block), expect(;).
proc_decl(proc(L, [Name, Params, tname(TL, [T]), Block])) -->
    kw(function, L),
    expect(ident(Name)), params(Params), expect(:),
    line(TL), expect(ident(T)), expect(;),
    block(Block), expect(;).

params(Ps) --> p('(', _), !, param(P), params_rest(Ps0), expect(')'), { Ps = [P|Ps0] }.
params([]) --> [].

params_rest([P|Ps]) --> p(;, _), !, param(P), params_rest(Ps).
params_rest([]) --> [].

param(param(L, [Mode, Names, tname(TL, [T])])) -->
    line(L),
    ( kw(var, _) -> { Mode = var } ; { Mode = value } ),
    ( ident_list(Names, _) -> [] ; syntax_error(ident(_)) ),
    expect(:), line(TL), expect(ident(T)).

                 /*******************************
                 *            TYPES             *
                 *******************************/

type_expr(array(L, [Ranges, Elem])) -->
    kw(array, L), !,
    expect('['), range(R), ranges(Rs), expect(']'),
    expect(kw(of)), type_expr(Elem),
    { Ranges = [R|Rs] }.
type_expr(record(L, [Fields])) -->
    kw(record, L), !,
    field_decl(F), field_decls(Fs), expect(kw(end)),
    { Fields = [F|Fs] }.
type_expr(T) -->
    line(L),
    simple_expression(E),
    (   p('..', _)
    ->  simple_expression(Hi), { T = subrange(L, [E, Hi]) }
    ;   { E = id(_, [Name]) }
    ->  { T = tname(L, [Name]) }
    ;   syntax_error(type)
    ).

range(R) --> line(L), simple_expression(Lo), expect('..'), simple_expression(Hi),
    { R = subrange(L, [Lo, Hi]) }.

ranges([R|Rs]) --> p(',', _), !, range(R), ranges(Rs).
ranges([]) --> [].

field_decl(field_decl(L, [Names, T])) -->
    ( ident_list(Names, L) -> [] ; syntax_error(ident(_)) ),
    expect(:), type_expr(T).

field_decls(Fs) --> p(;, _), !, ( field_decl(F) -> { Fs = [F|Fs0] }, field_decls(Fs0) ; { Fs = [] } ).
field_decls([]) --> [].

                 /*******************************
                 *          STATEMENTS          *
                 *******************************/

stmt_sequence([S|Ss]) --> statement(S), stmt_sequence_rest(Ss).

stmt_sequence_rest([S|Ss]) --> p(;, _), !, statement(S), stmt_sequence_rest(Ss).
stmt_sequence_rest([]) --> [].

statement(compound(L, [Ss])) -->
    kw(begin, L), !, stmt_sequence(Ss), expect(kw(end)).
statement(if(L, [C, Then, Else])) -->
    kw(if, L), !, expression(C), expect(kw(then)), statement(Then),
    (   kw(else, _)
    ->  statement(Else)
    ;   line(EL), { Else = empty(EL, []) }
    ).
statement(for(L, [Var, From, To, Dir, Body])) -->
    kw(for, L), !,
    line(VL), expect(ident(V)), { Var = id(VL, [V]) },
    expect(':='), expression(From),
    (   kw(to, _) -> { Dir = up }
    ;   kw(downto, _) -> { Dir = down }
    ;   syntax_error(kw(to))
    ),
    expression(To), expect(kw(do)), statement(Body).
statement(while(L, [C, Body])) -->
    kw(while, L), !, expression(C), expect(kw(do)), statement(Body).
statement(repeat(L, [Ss, C])) -->
    kw(repeat, L), !, stmt_sequence(Ss), expect(kw(until)), expression(C).
statement(S) -->
    ident(Name, L), !,
    (   selectors(id(L, [Name]), Target), p(':=', _)
    ->  expression(E), { S = assign(L, [Target, E]) }
    ;   { memberchk(Name, [write, writeln]) }
    ->  optional_args(Args),
        { ( Name == writeln -> NL = true ; NL = false ),
          S = write(L, [NL, Args]) }
    ;   optional_args(Args),
        { S = pcall(L, [Name, Args]) }
    ).
statement(empty(L, [])) -->
    line(L).

optional_args(Args) --> p('(', _), !, expression(A), expr_list_rest(As), expect(')'),
    { Args = [A|As] }.
optional_args([]) --> [].

expr_list_rest([E|Es]) --> p(',', _), !, expression(E), expr_list_rest(Es).
expr_list_rest([]) --> [].

%   selectors(+Base, -Var)// parses any [..] and .field suffixes.
selectors(Base, Var) -->
    p('[', L), !, expression(I), expr_list_rest(Is), expect(']'),
    selectors(index(L, [Base, [I|Is]]), Var).
selectors(Base, Var) -->
    p('.', L), [tok(_, id(F))], !,
    selectors(field(L, [Base, F]), Var).
selectors(Var, Var) --> [].

                 /*******************************
                 *          EXPRESSIONS         *
                 *******************************/

%   Precedence, lowest first:
%     relational  = <> < <= > >=  min max   (non-associative ... left here)
%     additive    + - or
%     multiplicative * / div mod and
%     unary       not, sign
%
%   Left-associative levels are parsed iteratively to avoid left recursion.

expression(E) -->
    simple_expression(L0),
    relational_rest(L0, E).

relational_rest(L0, E) -->
    rel_op(Op, L), !, simple_expression(R),
    relational_rest(op2(L, [Op, L0, R]), E).
relational_rest(E, E) --> [].

simple_expression(E) -->
    (   p(-, L)
    ->  term(T0), { T1 = op1(L, [-, T0]) }
    ;   p(+, _)
    ->  term(T1)
    ;   term(T1)
    ),
    additive_rest(T1, E).

additive_rest(L0, E) -->
    add_op(Op, L), !, term(R),
    additive_rest(op2(L, [Op, L0, R]), E).
additive_rest(E, E) --> [].

term(E) -->
    factor(F0),
    multiplicative_rest(F0, E).

multiplicative_rest(L0, E) -->
    mul_op(Op, L), !, factor(R),
    multiplicative_rest(op2(L, [Op, L0, R]), E).
multiplicative_rest(E, E) --> [].

factor(iconst(L, [N]))  --> [tok(L, int(N))], !.
factor(fconst(L, [R]))  --> [tok(L, real(R))], !.
factor(string(L, [Cs])) --> [tok(L, str(Cs))], !.
factor(bconst(L, [true]))  --> kw(true, L), !.
factor(bconst(L, [false])) --> kw(false, L), !.
factor(op1(L, [not, F])) --> kw(not, L), !, factor(F).
factor(E) --> p('(', _), !, expression(E), expect(')').
factor(E) -->
    ident(Name, L), !,
    (   p('(', _)
    ->  expression(A), expr_list_rest(As), expect(')'),
        { E = fcall(L, [Name, [A|As]]) }
    ;   selectors(id(L, [Name]), E)
    ).
factor(_) --> syntax_error(expression).

rel_op(Op, L) --> p(P, L), { rel_punct(P, Op) }, !.
rel_op(min, L) --> kw(min, L).
rel_op(max, L) --> kw(max, L).

rel_punct(=, =). rel_punct('<>', '<>'). rel_punct(<, <).
rel_punct('<=', '<='). rel_punct(>, >). rel_punct('>=', '>=').

add_op(+, L)  --> p(+, L).
add_op(-, L)  --> p(-, L).
add_op(or, L) --> kw(or, L).

mul_op(*, L)   --> p(*, L).
mul_op(/, L)   --> p(/, L).
mul_op(div, L) --> kw(div, L).
mul_op(mod, L) --> kw(mod, L).
mul_op(and, L) --> kw(and, L).
