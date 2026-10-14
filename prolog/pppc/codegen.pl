:- module(pppc_codegen,
          [ generate_c/2,               % +Typed, -CText
            c_expr/2,                   % +TypedExpr, -CText (testing)
            c_stmt/2                    % +TypedStmt, -CText (testing)
          ]).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

/** <module> C code generation

Emits C99 + OpenMP from a typed tree (with or without omp_for nodes).
Written as a DCG over the output codes, so each generator is a pure
relation from tree to text and can be unit tested.

Mapping (spec section 6.5):

  - integer, real, boolean   -> long, double, bool
  - array(Lo, Hi, E)          -> typedef struct { E e[Hi-Lo+1]; } pppc_tN
                                 (a struct so arrays have value semantics:
                                 assignment and value parameters copy)
  - record([F-T, ...])        -> typedef struct { T F; ... } pppc_tN
  - main program variables    -> file-scope static variables
  - Pascal names              -> p_name (see c_name/2)
  - var parameters            -> pointers, referenced as (*p_x)
  - function result           -> local pppc_result, returned at the end
  - for bounds                -> evaluated once into pppc_hi / pppc_lo
*/

%!  generate_c(+Typed, -CText:string) is det.
generate_c(Typed, Text) :-
    type_names(Typed, Types),
    phrase(program(Typed, Types), Codes),
    string_codes(Text, Codes).

%!  c_expr(+TypedExpr, -CText:string) is det.
%!  c_stmt(+TypedStmt, -CText:string) is det.
%
%   Generate code for a single expression or statement (indent 0),
%   for testing. Types used are declared on the fly.
c_expr(E, Text) :-
    type_names(E, Types),
    phrase(expr(E, Types), Codes),
    string_codes(Text, Codes).
c_stmt(S, Text) :-
    type_names(S, Types),
    phrase(stmt(S, 0, Types), Codes),
    string_codes(Text, Codes).

                 /*******************************
                 *        OUTPUT HELPERS        *
                 *******************************/

%   fmt(+Format, +Args)// emits format/2 output into the DCG list.
fmt(F, As, S0, S) :- format(codes(S0, S), F, As).

atom(A) --> fmt("~w", [A]).

indent(N) --> { N =< 0 }, !.
indent(N) --> "    ", { N1 is N - 1 }, indent(N1).

line_comment(L) --> fmt(" /* line ~d */", [L]).

sep_list([], _, _) --> [].
sep_list([X], G, _) --> !, call(G, X).
sep_list([X|Xs], G, Sep) --> call(G, X), Sep, sep_list(Xs, G, Sep).

                 /*******************************
                 *            TYPES             *
                 *******************************/

%   type_names(+Tree, -Types): an assoc from every compound type
%   occurring in Tree to its typedef name, plus `order` mapped to the
%   types in an order where components precede their users.

type_names(Tree, Types) :-
    findall(T, (sub_term(T, Tree), compound_type(T)), Ts0),
    foldl(add_type, Ts0, []-0, Ordered-_),
    reverse(Ordered, Order),
    pairs_to_assoc(Order, A0),
    type_keys(Order, Keys),
    put_assoc('$order', A0, Keys, Types).

compound_type(array(_, _, _)).
compound_type(record(_)).

add_type(T, Acc0-N0, Acc-N) :-
    (   memberchk(T-_, Acc0)
    ->  Acc = Acc0, N = N0
    ;   components(T, Cs),
        foldl(add_type, Cs, Acc0-N0, Acc1-N1),
        N is N1 + 1,
        format(atom(Name), "pppc_t~d", [N]),
        Acc = [T-Name|Acc1]
    ).

components(array(_, _, E), Cs) :- ( compound_type(E) -> Cs = [E] ; Cs = [] ).
components(record(Fs), Cs) :- findall(T, (member(_-T, Fs), compound_type(T)), Cs).

pairs_to_assoc(Pairs, A) :- list_to_assoc(Pairs, A).
type_keys(Pairs, Ks) :- findall(K, member(K-_, Pairs), Ks).

ctype(integer, _) --> !, "long".
ctype(real, _)    --> !, "double".
ctype(boolean, _) --> !, "bool".
ctype(T, Types)   --> { get_assoc(T, Types, Name) }, atom(Name).

typedefs(Types) -->
    { get_assoc('$order', Types, Order) },
    typedef_list(Order, Types).

typedef_list([], _) --> [].
typedef_list([T|Ts], Types) --> typedef(T, Types), typedef_list(Ts, Types).

typedef(array(Lo, Hi, E), Types) -->
    { get_assoc(array(Lo, Hi, E), Types, Name), Size is Hi - Lo + 1 },
    "typedef struct { ", ctype(E, Types), fmt(" e[~d]; } ~w;~n", [Size, Name]).
typedef(record(Fs), Types) -->
    { get_assoc(record(Fs), Types, Name) },
    "typedef struct { ", fields(Fs, Types), fmt("} ~w;~n", [Name]).

fields([], _) --> [].
fields([F-T|Fs], Types) --> ctype(T, Types), " ", cname(F), "; ", fields(Fs, Types).

                 /*******************************
                 *            NAMES             *
                 *******************************/

cname(N) --> { c_name(N, C) }, atom(C).

%   Every Pascal name (variables, routines, record fields) gets the
%   prefix p_. A blacklist of C names cannot be complete: <math.h>,
%   <string.h> and gcc's predefined macros (y1, index, floor, linux, ...)
%   all clash, and renaming only some names lets two Pascal names (int
%   and int_) map to one C name. A uniform prefix is injective, and
%   cannot produce the pppc_ prefix used by the runtime.
c_name(N, C) :-
    atom_concat(p_, N, C).

                 /*******************************
                 *           PROGRAM            *
                 *******************************/

program(program(_, [Name, block(_, [Decls, Procs, Body], _)], _), Types) -->
    fmt("/* Generated by pppc from program ~w */~n~n", [Name]),
    runtime,
    "\n", typedefs(Types), "\n",
    var_decls(Decls, "static ", 0, Types),
    "\n",
    prototypes(Procs, Types),
    proc_defs(Procs, Types),
    "int main(void)\n{\n",
    stmt(Body, 1, Types),
    "    return 0;\n}\n".

var_decls([], _, _, _) --> [].
var_decls([var_decl(_, [Ns, T], _)|Ds], Storage, Ind, Types) -->
    var_names(Ns, T, Storage, Ind, Types),
    var_decls(Ds, Storage, Ind, Types).

var_names([], _, _, _, _) --> [].
var_names([N|Ns], T, Storage, Ind, Types) -->
    indent(Ind), Storage, ctype(T, Types), " ", cname(N), ";\n",
    var_names(Ns, T, Storage, Ind, Types).

prototypes([], _) --> [].
prototypes([P|Ps], Types) --> proc_head(P, Types), ";\n", prototypes(Ps, Types).

proc_head(proc(_, [Name, Params, R, _], _), Types) -->
    "static ",
    ( { R == none } -> "void" ; ctype(R, Types) ),
    " ", cname(Name), "(",
    { findall(M-N-T, (member(param(_, [M, Ns, T], _), Params), member(N, Ns)), Ps) },
    ( { Ps == [] } -> "void" ; sep_list(Ps, param_decl(Types), ", ") ),
    ")".

param_decl(Types, value-N-T) --> ctype(T, Types), " ", cname(N).
param_decl(Types, var-N-T)   --> ctype(T, Types), " *", cname(N).

proc_defs([], _) --> [].
proc_defs([P|Ps], Types) --> "\n", proc_def(P, Types), "\n", proc_defs(Ps, Types).

proc_def(proc(L, [Name, Params, R, block(_, [Decls, _, Body], _)], _), Types) -->
    proc_head(proc(L, [Name, Params, R, _], _), Types), "\n{\n",
    (   { R == none }
    ->  []
    ;   "    ", ctype(R, Types), " pppc_result;\n"
    ),
    var_decls(Decls, "", 1, Types),
    stmt(Body, 1, Types),
    (   { R == none }
    ->  []
    ;   "    return pppc_result;\n"
    ),
    "}\n".

                 /*******************************
                 *          RUNTIME             *
                 *******************************/

runtime --> { runtime_text(T), string_codes(T, Cs) }, Cs.

runtime_text(
"#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdbool.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static inline long pppc_min_i(long a, long b) { return a < b ? a : b; }
static inline long pppc_max_i(long a, long b) { return a > b ? a : b; }
static inline double pppc_min_r(double a, double b) { return a < b ? a : b; }
static inline double pppc_max_r(double a, double b) { return a > b ? a : b; }
static inline long pppc_sqr_i(long a) { return a * a; }
static inline double pppc_sqr_r(double a) { return a * a; }
static inline bool pppc_odd(long a) { return a % 2 != 0; }

/* random: xorshift64*, one generator per thread, seeded by thread number */
static _Thread_local unsigned long long pppc_rng = 0;
static unsigned long long pppc_next(void)
{
    if (pppc_rng == 0) {
        unsigned long long t = 0;
#ifdef _OPENMP
        t = (unsigned long long)omp_get_thread_num();
#endif
        pppc_rng = 0x9E3779B97F4A7C15ULL * (t + 1);
    }
    pppc_rng ^= pppc_rng >> 12;
    pppc_rng ^= pppc_rng << 25;
    pppc_rng ^= pppc_rng >> 27;
    return pppc_rng * 2685821657736338717ULL;
}
static inline double pppc_random(void) { return (double)(pppc_next() >> 11) * 0x1.0p-53; }
static inline long pppc_random_int(long n) { return (long)(pppc_random() * (double)n); }
").

                 /*******************************
                 *          STATEMENTS          *
                 *******************************/

stmt(compound(_, [Ss], _), Ind, Types) --> !, stmts(Ss, Ind, Types).
stmt(empty(_, _, _), _, _) --> !.
stmt(assign(L, [T, E], _), Ind, Types) --> !,
    indent(Ind), expr(T, Types), " = ", expr(E, Types), ";", line_comment(L), "\n".
stmt(zero_assign(L, [T], _), Ind, Types) --> !,
    indent(Ind), "memset(&", expr(T, Types), ", 0, sizeof ", expr(T, Types), ");",
    line_comment(L), "\n".
stmt(if(L, [C, Then, Else], _), Ind, Types) --> !,
    { Ind1 is Ind + 1 },
    indent(Ind), "if (", expr(C, Types), ") {", line_comment(L), "\n",
    stmt(Then, Ind1, Types),
    (   { Else = empty(_, _, _) }
    ->  []
    ;   indent(Ind), "} else {\n",
        stmt(Else, Ind1, Types)
    ),
    indent(Ind), "}\n".
stmt(while(L, [C, Body], _), Ind, Types) --> !,
    { Ind1 is Ind + 1 },
    indent(Ind), "while (", expr(C, Types), ") {", line_comment(L), "\n",
    stmt(Body, Ind1, Types),
    indent(Ind), "}\n".
stmt(repeat(L, [Ss, C], _), Ind, Types) --> !,
    { Ind1 is Ind + 1 },
    indent(Ind), "do {", line_comment(L), "\n",
    stmts(Ss, Ind1, Types),
    indent(Ind), "} while (!", expr(C, Types), ");\n".
stmt(for(L, [V, F, T, D, Body], _), Ind, Types) --> !,
    for_loop(L, V, F, T, D, Body, [], Ind, Types).
stmt(omp_for(L, [V, F, T, D, Body, Clauses], _), Ind, Types) --> !,
    for_loop(L, V, F, T, D, Body, pragma(Clauses), Ind, Types).
stmt(pcall(L, [Name, Args], _), Ind, Types) --> !,
    indent(Ind), cname(Name), "(", sep_list(Args, call_arg(Types), ", "), ");",
    line_comment(L), "\n".
stmt(write(L, [NL, Args], _), Ind, Types) --> !,
    write_args(Args, L, Ind, Types),
    (   { NL == true }
    ->  indent(Ind), "putchar('\\n');", line_comment(L), "\n"
    ;   []
    ).

stmts([], _, _) --> [].
stmts([S|Ss], Ind, Types) --> stmt(S, Ind, Types), stmts(Ss, Ind, Types).

%   Pascal evaluates the bounds once; the limit is kept in a temporary.
for_loop(L, V, F, T, D, Body, Pragma, Ind, Types) -->
    { Ind1 is Ind + 1, Ind2 is Ind + 2,
      direction(D, Lim, Cmp, Step) },
    indent(Ind), "{\n",
    indent(Ind1), fmt("long ~w = ", [Lim]), expr(T, Types), ";\n",
    pragma(Pragma, Ind1),
    indent(Ind1), "for (", expr(V, Types), " = ", expr(F, Types), "; ",
    expr(V, Types), fmt(" ~w ~w; ", [Cmp, Lim]), expr(V, Types), Step, ") {",
    line_comment(L), "\n",
    stmt(Body, Ind2, Types),
    indent(Ind1), "}\n",
    indent(Ind), "}\n".

direction(up, pppc_hi, '<=', "++").
direction(down, pppc_lo, '>=', "--").

pragma([], _) --> [].
pragma(pragma(Clauses), Ind) -->
    indent(Ind), "#pragma omp parallel for",
    omp_clauses(Clauses), "\n".

omp_clauses([]) --> [].
omp_clauses([C|Cs]) --> " ", omp_clause(C), omp_clauses(Cs).

omp_clause(private(Vs)) --> "private(", sep_list(Vs, cname, ", "), ")".
omp_clause(shared(Vs)) --> "shared(", sep_list(Vs, cname, ", "), ")".
omp_clause(reduction(Op, Vs)) -->
    { reduction_op(Op, COp) },
    fmt("reduction(~w:", [COp]), sep_list(Vs, cname, ", "), ")".

reduction_op(+, +).
reduction_op(*, *).
reduction_op(and, &&).
reduction_op(or, '||').
reduction_op(min, min).
reduction_op(max, max).

write_args([], _, _, _) --> [].
write_args([A|As], L, Ind, Types) -->
    indent(Ind), write_arg(A, Types), line_comment(L), "\n",
    write_args(As, L, Ind, Types).

write_arg(A, Types) --> { arg(3, A, integer) }, !,
    "printf(\"%ld\", ", expr(A, Types), ");".
write_arg(A, Types) --> { arg(3, A, real) }, !,
    "printf(\"%.15g\", ", expr(A, Types), ");".
write_arg(A, Types) --> { arg(3, A, boolean) }, !,
    "fputs(", expr(A, Types), " ? \"TRUE\" : \"FALSE\", stdout);".
write_arg(A, Types) -->
    "fputs(", expr(A, Types), ", stdout);".

call_arg(Types, addr(_, [V], _)) --> !,
    (   { V = vparam(_, [N], _) }
    ->  cname(N)
    ;   "&", expr(V, Types)
    ).
call_arg(Types, E) --> expr(E, Types).

                 /*******************************
                 *          EXPRESSIONS         *
                 *******************************/

expr(id(_, [N], _), _) --> cname(N).
expr(vparam(_, [N], _), _) --> "(*", cname(N), ")".
expr(fresult(_, _, _), _) --> "pppc_result".
expr(iconst(_, [N], _), _) --> fmt("~d", [N]).
expr(fconst(_, [R], _), _) --> fmt("~w", [R]).
expr(bconst(_, [B], _), _) --> atom(B).
expr(string(_, [Cs], _), _) --> "\"", c_string(Cs), "\"".
expr(itor(_, [E], _), Types) --> "((double)", expr(E, Types), ")".
expr(op1(_, [Op, E], _), Types) -->
    { op1_c(Op, C) }, "(", atom(C), expr(E, Types), ")".
expr(op2(_, [Op, A, B], T), Types) -->
    (   { minmax(Op, T, F) }
    ->  atom(F), "(", expr(A, Types), ", ", expr(B, Types), ")"
    ;   { op2_c(Op, C) },
        "(", expr(A, Types), " ", atom(C), " ", expr(B, Types), ")"
    ).
expr(index(_, [A, I], _), Types) -->
    { arg(3, A, array(Lo, _, _)) },
    expr(A, Types), ".e[",
    (   { Lo =:= 0 }
    ->  expr(I, Types)
    ;   expr(I, Types), fmt(" - ~d", [Lo])
    ),
    "]".
expr(field(_, [R, F], _), Types) --> expr(R, Types), ".", cname(F).
expr(fcall(_, [N, Args], _), Types) -->
    cname(N), "(", sep_list(Args, call_arg(Types), ", "), ")".
expr(builtin(_, [N, Args], T), Types) -->
    builtin(N, Args, T, Types).

builtin(random, [], _, _) --> !, "pppc_random()".
builtin(random, [A], _, Types) --> !, "pppc_random_int(", expr(A, Types), ")".
builtin(trunc, [A], _, Types) --> !, "((long)", expr(A, Types), ")".
builtin(N, [A], T, Types) -->
    { once(builtin_c(N, T, F)) },
    atom(F), "(", expr(A, Types), ")".

builtin_c(abs, integer, labs).
builtin_c(abs, real, fabs).
builtin_c(sqr, integer, pppc_sqr_i).
builtin_c(sqr, real, pppc_sqr_r).
builtin_c(sqrt, _, sqrt).
builtin_c(sin, _, sin).
builtin_c(cos, _, cos).
builtin_c(exp, _, exp).
builtin_c(ln, _, log).
builtin_c(round, _, lround).
builtin_c(odd, _, pppc_odd).

op1_c(-, -).
op1_c(not, !).

op2_c(+, +).   op2_c(-, -).   op2_c(*, *).   op2_c(/, /).
op2_c(div, /). op2_c(mod, '%').
op2_c(and, &&). op2_c(or, '||').
op2_c(=, ==).  op2_c('<>', '!=').
op2_c(<, <).   op2_c('<=', '<=').  op2_c(>, >).  op2_c('>=', '>=').

minmax(min, integer, pppc_min_i).
minmax(max, integer, pppc_max_i).
minmax(min, real, pppc_min_r).
minmax(max, real, pppc_max_r).

c_string([]) --> [].
c_string([C|Cs]) --> c_char(C), c_string(Cs).

c_char(0'") --> !, "\\\"".
c_char(0'\\) --> !, "\\\\".
c_char(C) --> { C >= 32, C < 127 }, !, [C].
c_char(C) --> { C > 255 }, !, "?".
c_char(C) -->
    { D1 is C >> 6, D2 is (C >> 3) /\ 7, D3 is C /\ 7 },
    fmt("\\~d~d~d", [D1, D2, D3]).
