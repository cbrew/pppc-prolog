:- module(pppc_semantic,
          [ check_program/3             % +Tree, -Typed, -Errors
          ]).
:- use_module(library(assoc)).
:- use_module(library(apply)).
:- use_module(library(lists)).

/** <module> TAU-Pascal semantic analysis

Builds the symbol table and produces the typed parse tree (spec
section 5.3). Every node gains a third argument holding its type;
statements have type `void`.

The checker is written as a DCG whose "string" is the list of errors
found: a check that finds a problem emits pppc(semantic(Line, Msg))
with report//2 and carries on, giving the offending node type `error`.
Operations on `error` operands are silently accepted, so one mistake
produces one message rather than a cascade.

Normalised types:

    integer | real | boolean | string | void | error
    array(Lo, Hi, Elem)            one dimension; a[1..n,1..m] nests
    record([Field-Type, ...])

Constants are replaced by their values; references to var parameters
become vparam/3 nodes; assignment to a function's own name becomes
fresult/3; integer-to-real widening is an explicit itor/3 node;
calls to standard functions are builtin/3 nodes, to user routines
fcall/3 or pcall/3, with var arguments wrapped in addr/3.
*/

%!  check_program(+Tree, -Typed, -Errors:list) is det.
%
%   Type check a parse tree. Errors is the list of
%   pppc(semantic(Line, Msg)) terms found, in source order; Typed is
%   only meaningful if Errors is [].

check_program(Tree, Typed, Errors) :-
    phrase(program(Tree, Typed), Errors).

report(L, Msg) --> [pppc(semantic(L, Msg))].

                 /*******************************
                 *        ENVIRONMENT           *
                 *******************************/

%   The environment is env(Scopes, Routine). Scopes is a list of
%   assocs from name to entry, innermost first: [Globals, Predefined]
%   in the main program, [Locals, Globals, Predefined] inside a
%   routine. Routine is `main`, proc(Name) or func(Name, ResultType),
%   naming the routine whose body is being checked.
%
%   Entries: var(T), vparam(T), const(T, V), type(T), proc(Params, R)
%   where Params is a list of p(Mode, T) and R is a type or `none`.

initial_env(env([Globals, Predefined], main)) :-
    empty_assoc(Globals),
    list_to_assoc([ integer-type(integer),
                    real-type(real),
                    boolean-type(boolean)
                  ], Predefined).

enter_routine(Routine, env(Scopes, _), env([Locals|Scopes], Routine)) :-
    empty_assoc(Locals).

lookup(Name, env(Scopes, _), Entry) :-
    member(Scope, Scopes),
    get_assoc(Name, Scope, Entry),
    !.

%   declare(+Line, +Name, +Entry, +Env0, -Env)// adds Name to the
%   innermost scope, reporting a redeclaration within that scope.

declare(L, Name, Entry, env([S0|Ss], R), env([S|Ss], R)) -->
    (   { get_assoc(Name, S0, _) }
    ->  report(L, redeclared(Name)), { S = S0 }
    ;   { put_assoc(Name, S0, Entry, S) }
    ).

                 /*******************************
                 *      PROGRAM & BLOCKS        *
                 *******************************/

program(program(L, [Name, Block]), program(L, [Name, TBlock], void)) -->
    { initial_env(Env0) },
    block(Block, Env0, TBlock).

block(block(L, [Consts, Types, Vars, Procs, Body]), Env0,
      block(L, [TVars, TProcs, TBody], void)) -->
    consts(Consts, Env0, Env1),
    types(Types, Env1, Env2),
    vars(Vars, Env2, Env3, TVars),
    proc_headers(Procs, Env3, Env4),
    proc_bodies(Procs, Env4, TProcs),
    stmt(Body, Env4, TBody).

consts([], Env, Env) --> [].
consts([const_decl(L, [Name, E])|Cs], Env0, Env) -->
    { const_result(E, Env0, R) },
    (   { R = ok(T, V) }
    ->  declare(L, Name, const(T, V), Env0, Env1)
    ;   { R = eval_error(Why) }
    ->  report(L, constant_error(Name, Why)), { Env1 = Env0 }
    ;   report(L, not_constant(Name)), { Env1 = Env0 }
    ),
    consts(Cs, Env1, Env).

types([], Env, Env) --> [].
types([type_decl(L, [Name, TE])|Ts], Env0, Env) -->
    type_expr(TE, Env0, T),
    declare(L, Name, type(T), Env0, Env1),
    types(Ts, Env1, Env).

vars([], Env, Env, []) --> [].
vars([var_decl(L, [Names, TE])|Vs], Env0, Env, [var_decl(L, [Names, T], void)|TVs]) -->
    type_expr(TE, Env0, T),
    declare_all(Names, L, var(T), Env0, Env1),
    vars(Vs, Env1, Env, TVs).

declare_all([], _, _, Env, Env) --> [].
declare_all([N|Ns], L, Entry, Env0, Env) -->
    declare(L, N, Entry, Env0, Env1),
    declare_all(Ns, L, Entry, Env1, Env).

                 /*******************************
                 *          CONSTANTS           *
                 *******************************/

%!  const_result(+Expr, +Env, -Result) is det.
%
%   Result is ok(Type, Value), not_constant, or eval_error(Why) when the
%   arithmetic itself fails (Why is e.g. zero_divisor, float_overflow).
const_result(E, Env, R) :-
    catch(( const_value(E, Env, T, V)
          ->  R = ok(T, V)
          ;   R = not_constant
          ),
          error(evaluation_error(Why), _),
          R = eval_error(Why)).

%!  const_value(+Expr, +Env, -Type, -Value) is semidet.
%
%   Evaluate a constant expression at compile time.

const_value(iconst(_, [N]), _, integer, N).
const_value(fconst(_, [R]), _, real, R).
const_value(bconst(_, [B]), _, boolean, B).
const_value(id(_, [N]), Env, T, V) :-
    lookup(N, Env, const(T, V)).
const_value(op1(_, [-, E]), Env, T, V) :-
    const_value(E, Env, T, V0),
    memberchk(T, [integer, real]),
    V is -V0.
const_value(op2(_, [Op, A, B]), Env, T, V) :-
    const_value(A, Env, TA, VA),
    const_value(B, Env, TB, VB),
    const_op(Op, TA, TB, VA, VB, T, V).

const_op(+, integer, integer, A, B, integer, V) :- V is A + B.
const_op(-, integer, integer, A, B, integer, V) :- V is A - B.
const_op(*, integer, integer, A, B, integer, V) :- V is A * B.
const_op(div, integer, integer, A, B, integer, V) :- V is A // B.
const_op(Op, TA, TB, A, B, real, V) :-
    memberchk(Op, [+, -, *, /]),
    memberchk(TA, [integer, real]), memberchk(TB, [integer, real]),
    ( TA == real ; TB == real ; Op == / ),
    F =.. [Op, A, B],
    V is float(F).

                 /*******************************
                 *            TYPES             *
                 *******************************/

type_expr(tname(L, [N]), Env, T) -->
    (   { lookup(N, Env, type(T0)) }
    ->  { T = T0 }
    ;   report(L, not_a_type(N)), { T = error }
    ).
type_expr(subrange(L, [Lo, Hi]), Env, T) -->
    bounds(L, Lo, Hi, Env, _, _),
    { T = integer }.
type_expr(array(L, [Ranges, ElemE]), Env, T) -->
    type_expr(ElemE, Env, Elem),
    array_type(Ranges, L, Elem, Env, T).
type_expr(record(_, [FieldDecls]), Env, record(Fields)) -->
    field_decls(FieldDecls, Env, Fields).

array_type([], _, Elem, _, Elem) --> [].
array_type([subrange(SL, [LoE, HiE])|Rs], L, Elem, Env, T) -->
    bounds(SL, LoE, HiE, Env, Lo, Hi),
    array_type(Rs, L, Elem, Env, Inner),
    { T = array(Lo, Hi, Inner) }.

bounds(L, LoE, HiE, Env, Lo, Hi) -->
    (   { const_result(LoE, Env, ok(integer, Lo)),
          const_result(HiE, Env, ok(integer, Hi)),
          Lo =< Hi }
    ->  []
    ;   report(L, bad_bounds), { Lo = 1, Hi = 1 }
    ).

field_decls([], _, []) --> [].
field_decls([field_decl(_, [Names, TE])|Ds], Env, Fields) -->
    type_expr(TE, Env, T),
    { findall(N-T, member(N, Names), Fs1) },
    field_decls(Ds, Env, Fs2),
    { append(Fs1, Fs2, Fields) }.

numeric(integer).
numeric(real).

%   all_numeric(+Type): every leaf of the compound type is numeric.
all_numeric(array(_, _, E)) :- all_numeric(E).
all_numeric(record(Fs)) :- forall(member(_-T, Fs), all_numeric(T)).
all_numeric(T) :- numeric(T).

compound_type(array(_, _, _)).
compound_type(record(_)).

                 /*******************************
                 *          ROUTINES            *
                 *******************************/

proc_headers([], Env, Env) --> [].
proc_headers([proc(L, [Name, Params, ResE, _])|Ps], Env0, Env) -->
    params(Params, Env0, PTypes),
    result_type(ResE, Env0, R),
    declare(L, Name, proc(PTypes, R), Env0, Env1),
    proc_headers(Ps, Env1, Env).

params([], _, []) --> [].
params([param(_, [Mode, Names, TE])|Ps], Env, PTypes) -->
    type_expr(TE, Env, T),
    { findall(p(Mode, T), member(_, Names), P1) },
    params(Ps, Env, P2),
    { append(P1, P2, PTypes) }.

result_type(none, _, none) --> [].
result_type(tname(L, N), Env, T) --> type_expr(tname(L, N), Env, T).

proc_bodies([], _, []) --> [].
proc_bodies([P|Ps], Env, [TP|TPs]) -->
    proc_body(P, Env, TP),
    proc_bodies(Ps, Env, TPs).

proc_body(proc(L, [Name, Params, _, Block]), Env0, TProc) -->
    { lookup(Name, Env0, proc(_, R)),
      (   R == none
      ->  Routine = proc(Name)
      ;   Routine = func(Name, R)
      ),
      enter_routine(Routine, Env0, EnvR)
    },
    typed_params(Params, Env0, EnvR, Env1, TParams),
    { Block = block(_, [_, _, _, Nested, _]) },
    (   { Nested == [] }
    ->  []
    ;   { Nested = [proc(NL, [NN|_])|_] }, report(NL, nested_routine(NN))
    ),
    { Block = block(BL, [Cs, Ts, Vs, _, Body]) },
    block(block(BL, [Cs, Ts, Vs, [], Body]), Env1, TBlock),
    { TProc = proc(L, [Name, TParams, R, TBlock], void) }.

typed_params([], _, Env, Env, []) --> [].
typed_params([param(L, [Mode, Names, TE])|Ps], TEnv, Env0, Env,
             [param(L, [Mode, Names, T], void)|TPs]) -->
    type_expr(TE, TEnv, T),
    { mode_entry(Mode, T, Entry) },
    declare_all(Names, L, Entry, Env0, Env1),
    typed_params(Ps, TEnv, Env1, Env, TPs).

mode_entry(value, T, var(T)).
mode_entry(var, T, vparam(T)).

                 /*******************************
                 *          STATEMENTS          *
                 *******************************/

stmt(compound(L, [Ss]), Env, compound(L, [TSs], void)) -->
    stmts(Ss, Env, TSs).
stmt(empty(L, []), _, empty(L, [], void)) --> [].
stmt(assign(L, [Target, E]), Env, TS) -->
    variable(Target, Env, TT),
    expr(E, Env, TE),
    assignment(L, TT, TE, TS).
stmt(if(L, [C, Then, Else]), Env, if(L, [TC, TThen, TElse], void)) -->
    condition(C, Env, TC),
    stmt(Then, Env, TThen),
    stmt(Else, Env, TElse).
stmt(while(L, [C, Body]), Env, while(L, [TC, TBody], void)) -->
    condition(C, Env, TC),
    stmt(Body, Env, TBody).
stmt(repeat(L, [Ss, C]), Env, repeat(L, [TSs, TC], void)) -->
    stmts(Ss, Env, TSs),
    condition(C, Env, TC).
stmt(for(L, [Var, From, To, Dir, Body]), Env,
     for(L, [TVar, TFrom, TTo, Dir, TBody], void)) -->
    variable(Var, Env, TVar),
    (   { type_of(TVar, T), memberchk(T, [integer, error]),
          TVar = id(_, _, _) }
    ->  []
    ;   report(L, bad_for_variable)
    ),
    integer_expr(From, Env, TFrom),
    integer_expr(To, Env, TTo),
    stmt(Body, Env, TBody).
stmt(pcall(L, [Name, Args]), Env, TS) -->
    (   { lookup(Name, Env, proc(Ps, none)) }
    ->  call_args(L, Name, Ps, Args, Env, TArgs),
        { TS = pcall(L, [Name, TArgs], void) }
    ;   report(L, not_a_procedure(Name)),
        { TS = empty(L, [], void) }
    ).
stmt(write(L, [NL, Args]), Env, write(L, [NL, TArgs], void)) -->
    write_args(Args, Env, TArgs).

stmts([], _, []) --> [].
stmts([S|Ss], Env, [TS|TSs]) --> stmt(S, Env, TS), stmts(Ss, Env, TSs).

assignment(L, TT, TE, TS) -->
    { type_of(TT, VT), type_of(TE, ET) },
    (   { compound_type(VT), TE = iconst(_, [0], integer) }
    ->  (   { all_numeric(VT) }
        ->  { TS = zero_assign(L, [TT], void) }
        ;   report(L, bad_zero_assignment), { TS = empty(L, [], void) }
        )
    ;   { assignable(VT, ET, TE, TE1) }
    ->  { TS = assign(L, [TT, TE1], void) }
    ;   report(L, assign_mismatch(VT, ET)), { TS = empty(L, [], void) }
    ).

%!  assignable(+VarType, +ExprType, +Expr, -Expr1) is semidet.
assignable(error, _, E, E) :- !.
assignable(_, error, E, E) :- !.
assignable(T, T, E, E) :- !.
assignable(real, integer, E, itor(L, [E], real)) :- arg(1, E, L).

condition(C, Env, TC) -->
    expr(C, Env, TC),
    (   { type_of(TC, T), memberchk(T, [boolean, error]) }
    ->  []
    ;   { arg(1, C, L) }, report(L, not_boolean)
    ).

integer_expr(E, Env, TE) -->
    expr(E, Env, TE),
    (   { type_of(TE, T), memberchk(T, [integer, error]) }
    ->  []
    ;   { arg(1, E, L) }, report(L, not_integer)
    ).

write_args([], _, []) --> [].
write_args([A|As], Env, [TA|TAs]) -->
    expr(A, Env, TA),
    (   { type_of(TA, T), memberchk(T, [integer, real, boolean, string, error]) }
    ->  []
    ;   { arg(1, A, L) }, report(L, not_writable)
    ),
    write_args(As, Env, TAs).

                 /*******************************
                 *          VARIABLES           *
                 *******************************/

%   variable(+Expr, +Env, -Typed)// checks an assignable designator.

variable(id(L, [N]), Env, TV) -->
    !,
    (   { lookup(N, Env, var(T)) }
    ->  { TV = id(L, [N], T) }
    ;   { lookup(N, Env, vparam(T)) }
    ->  { TV = vparam(L, [N], T) }
    ;   { Env = env(_, func(N, R)) }
    ->  { TV = fresult(L, [N], R) }
    ;   { lookup(N, Env, _) }
    ->  report(L, not_a_variable(N)), { TV = id(L, [N], error) }
    ;   report(L, undeclared(N)), { TV = id(L, [N], error) }
    ).
variable(index(L, [Base, Is]), Env, TV) -->
    !,
    variable(Base, Env, TB),
    indices(Is, L, TB, Env, TV).
variable(field(L, [Base, F]), Env, TV) -->
    !,
    variable(Base, Env, TB),
    field_ref(L, TB, F, TV).
variable(E, _, id(L, ['?'], error)) -->
    { arg(1, E, L) }, report(L, not_a_variable(expression)).

indices([], _, TV, _, TV) --> [].
indices([I|Is], L, TB, Env, TV) -->
    integer_expr(I, Env, TI),
    { type_of(TB, BT) },
    (   { BT = array(_, _, Elem) }
    ->  []
    ;   { BT == error }
    ->  { Elem = error }
    ;   report(L, not_an_array), { Elem = error }
    ),
    indices(Is, L, index(L, [TB, TI], Elem), Env, TV).

field_ref(L, TB, F, field(L, [TB, F], T)) -->
    { type_of(TB, BT) },
    (   { BT = record(Fs), memberchk(F-T0, Fs) }
    ->  { T = T0 }
    ;   { BT == error }
    ->  { T = error }
    ;   { BT = record(_) }
    ->  report(L, no_such_field(F)), { T = error }
    ;   report(L, not_a_record), { T = error }
    ).

                 /*******************************
                 *          EXPRESSIONS         *
                 *******************************/

expr(iconst(L, [N]), _, iconst(L, [N], integer)) --> [].
expr(fconst(L, [R]), _, fconst(L, [R], real)) --> [].
expr(bconst(L, [B]), _, bconst(L, [B], boolean)) --> [].
expr(string(L, [Cs]), _, string(L, [Cs], string)) --> [].
expr(id(L, [N]), Env, TE) -->
    (   { lookup(N, Env, const(T, V)) }
    ->  { const_node(T, L, V, TE) }
    ;   { lookup(N, Env, proc([], R)), R \== none }
    ->  { TE = fcall(L, [N, []], R) }
    ;   { \+ lookup(N, Env, _), builtin_sig(N, [], R) }
    ->  { TE = builtin(L, [N, []], R) }
    ;   variable(id(L, [N]), Env, TE0),
        (   { TE0 = fresult(_, _, _) }
        ->  report(L, function_result_read(N)), { TE = id(L, [N], error) }
        ;   { TE = TE0 }
        )
    ).
expr(index(L, Args), Env, TE) -->
    variable(index(L, Args), Env, TE).
expr(field(L, Args), Env, TE) -->
    variable(field(L, Args), Env, TE).
expr(op1(L, [Op, A]), Env, TE) -->
    expr(A, Env, TA),
    { type_of(TA, T) },
    (   { op1_rule(Op, T, R) }
    ->  { TE = op1(L, [Op, TA], R) }
    ;   { T == error }
    ->  { TE = op1(L, [Op, TA], error) }
    ;   report(L, type_clash(Op, T)), { TE = op1(L, [Op, TA], error) }
    ).
expr(op2(L, [Op, A, B]), Env, TE) -->
    expr(A, Env, TA),
    expr(B, Env, TB),
    { type_of(TA, T1), type_of(TB, T2) },
    (   { check_op2(Op, TA, T1, TB, T2, TA1, TB1, R) }
    ->  { TE = op2(L, [Op, TA1, TB1], R) }
    ;   { ( T1 == error ; T2 == error ) }
    ->  { TE = op2(L, [Op, TA, TB], error) }
    ;   report(L, type_clash(Op, T1, T2)), { TE = op2(L, [Op, TA, TB], error) }
    ).
expr(fcall(L, [N, Args]), Env, TE) -->
    (   { lookup(N, Env, proc(Ps, R)), R \== none }
    ->  call_args(L, N, Ps, Args, Env, TArgs),
        { TE = fcall(L, [N, TArgs], R) }
    ;   { \+ lookup(N, Env, _) }, { builtin_name(N) }
    ->  exprs(Args, Env, TArgs),
        builtin_call(L, N, TArgs, TE)
    ;   report(L, not_a_function(N)), { TE = fcall(L, [N, []], error) }
    ).

exprs([], _, []) --> [].
exprs([E|Es], Env, [T|Ts]) --> expr(E, Env, T), exprs(Es, Env, Ts).

const_node(integer, L, V, iconst(L, [V], integer)).
const_node(real, L, V, fconst(L, [V], real)).
const_node(boolean, L, V, bconst(L, [V], boolean)).

type_of(Node, T) :- arg(3, Node, T).

%   Operator typing, as a table in the style of the paper's op2/4.

op1_rule(-, integer, integer).
op1_rule(-, real, real).
op1_rule(not, boolean, boolean).

op2_rule(Op, integer, integer, integer) :- memberchk(Op, [+, -, *, div, mod, min, max]).
op2_rule(Op, real, real, real) :- memberchk(Op, [+, -, *, /, min, max]).
op2_rule(Op, boolean, boolean, boolean) :- memberchk(Op, [and, or]).
op2_rule(Op, integer, integer, boolean) :- memberchk(Op, [=, '<>', <, '<=', >, '>=']).
op2_rule(Op, real, real, boolean) :- memberchk(Op, [=, '<>', <, '<=', >, '>=']).
op2_rule(Op, boolean, boolean, boolean) :- memberchk(Op, [=, '<>']).

%!  check_op2(+Op, +A, +TA, +B, +TB, -A1, -B1, -Result) is semidet.
%
%   Find the first operand typing for which Op is defined, widening
%   integer operands to real where needed.
check_op2(Op, A, TA, B, TB, A1, B1, R) :-
    member(WA-WB, [TA-TB, real-TB, TA-real, real-real]),
    op2_rule(Op, WA, WB, R),
    widen(TA, WA, A, A1),
    widen(TB, WB, B, B1),
    !.

widen(T, T, E, E) :- !.
widen(integer, real, E, itor(L, [E], real)) :- arg(1, E, L).

%   Standard functions: builtin_sig(Name, ArgTypes, Result).

builtin_sig(abs, [integer], integer).
builtin_sig(abs, [real], real).
builtin_sig(sqr, [integer], integer).
builtin_sig(sqr, [real], real).
builtin_sig(F, [real], real) :- memberchk(F, [sqrt, sin, cos, exp, ln]).
builtin_sig(trunc, [real], integer).
builtin_sig(round, [real], integer).
builtin_sig(odd, [integer], boolean).
builtin_sig(random, [], real).
builtin_sig(random, [integer], integer).

builtin_name(N) :- builtin_sig(N, _, _), !.

builtin_call(L, N, TArgs, TE) -->
    { maplist(type_of, TArgs, Ts) },
    (   { builtin_sig(N, Sig, R),
          maplist(widen, Ts, Sig, TArgs, TArgs1) }
    ->  { TE = builtin(L, [N, TArgs1], R) }
    ;   { memberchk(error, Ts) }
    ->  { TE = builtin(L, [N, TArgs], error) }
    ;   report(L, bad_arguments(N)), { TE = builtin(L, [N, TArgs], error) }
    ).

%   User routine arguments.

call_args(L, Name, Ps, Args, Env, TArgs) -->
    { length(Ps, NP), length(Args, NA) },
    (   { NP =:= NA }
    ->  call_args(Ps, Args, Env, TArgs)
    ;   report(L, arg_count(Name, NP, NA)), { TArgs = [] }
    ).

call_args([], [], _, []) --> [].
call_args([p(Mode, PT)|Ps], [A|As], Env, [TA|TAs]) -->
    call_arg(Mode, PT, A, Env, TA),
    call_args(Ps, As, Env, TAs).

call_arg(value, PT, A, Env, TA1) -->
    expr(A, Env, TA),
    { type_of(TA, AT) },
    (   { assignable(PT, AT, TA, TA1) }
    ->  []
    ;   { arg(1, A, L) }, report(L, arg_mismatch(PT, AT)), { TA1 = TA }
    ).
call_arg(var, PT, A, Env, addr(L, [TA], PT)) -->
    { arg(1, A, L) },
    variable(A, Env, TA),
    { type_of(TA, AT) },
    (   { AT == PT ; AT == error }
    ->  []
    ;   report(L, arg_mismatch(PT, AT))
    ).
