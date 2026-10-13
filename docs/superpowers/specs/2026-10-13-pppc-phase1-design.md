# PPPC Reproduction — Phase 1 Design

Date: 2026-10-13
Status: Approved 2026-10-13; revised after prototyping (see section 11)

## 1. Purpose

Reproduce the Portable Parallelizing Pascal Compiler (PPPC) described in
Gabber, "Developing a Portable Parallelizing Pascal Compiler in Prolog"
(*The Practice of Prolog*, MIT Press 1990, ch. 4; `pascal-compiler-prolog.pdf`),
using current SWI-Prolog and targeting C + OpenMP instead of VMMP.

The underlying goal is to (re)learn **modern SWI-Prolog practice**: standard
pack layout, modules, DCGs, tabling, plunit, pldoc, `print_message/2`, and
deterministic, explicitly-threaded state. Where the paper's 1990 idiom
(C-Prolog, global `assert`, `write/1` chains, text files between passes)
differs from modern practice, the modern idiom wins, but the paper's
algorithms and term shapes are kept recognisable.

### Success criteria (Phase 1)

1. `pppc` compiles each of the seven benchmark programs (Pi, MontePi, Mandel,
   Linear/Jacobi, Nbody, MM, CG) to C that builds with `gcc -O2 -fopenmp`.
2. For every benchmark, the parallel build run with `OMP_NUM_THREADS=1` and
   `=4` produces output equal to the `--serial` build (reals within a
   documented tolerance).
3. The loops reported as parallel, and their variable classifications, match
   the paper's rules (section 4.3.3); for the paper's Jacobi excerpt exactly:
   `i` index, `sum`/`j` local, `a`/`b` read-only, `new_x` distributed,
   `error` associative (`max`).
4. Negative programs (carried dependence, user procedure call in body,
   non-index subscript) are not parallelized.
5. `make test` (unit) and `make check` (end-to-end) pass inside the devenv
   shell.

### Out of scope (Phase 2 or later)

- Target cost table, run-time prediction, profitability decision.
- Replicated-SPMD regions (one `omp parallel` around an outer serial loop).
- Speedup measurements / Table 4.1 reproduction.
- A second (typed Python subset) front end.
- Nested parallelism, inter-procedural analysis.

## 2. Environment

- **devenv** (`devenv.nix`, `devenv.yaml`) supplies:
  `swi-prolog` 10.0.2 (current stable; from devenv's nixpkgs `rolling`),
  `gcc` (OpenMP), `gnumake`.
- Packs are isolated to the project: the shell sets `SWIPL_PACK_PATH` to
  `.devenv/state/swipl-packs` (gitignored) so nothing touches
  `~/.local/share/swi-prolog`, and links this project into it
  (`swipl pack install -y .`), so `use_module(library(pppc))` and the
  pack app `swipl pppc ...` work from any directory in the shell.
- No `.envrc`: direnv is not installed; use `devenv shell`.
- The system `/usr/bin/swipl` (9.0.4) is not used.

## 3. Project layout

```
pascal_compiler/
├── devenv.nix  devenv.yaml  devenv.lock
├── pack.pl                    # name(pppc), version, author, home, requires
├── Makefile                   # test | check | doc | clean
├── prolog/
│   ├── pppc.pl                # public API
│   └── pppc/
│       ├── lexer.pl           # codes → tokens
│       ├── parser.pl          # tokens → parse tree
│       ├── semantic.pl        # parse tree → typed tree + symbol table
│       ├── label.pl           # statement labelling
│       ├── dataflow.pl        # reaching definitions (tabled)
│       ├── parloop.pl         # variable classification, parallel loop marking
│       ├── transform.pl       # parallelizer driver; marked loops → omp_for
│       ├── tree.pl            # small queries over typed tree nodes
│       ├── codegen.pl         # typed tree → C text (DCG)
│       └── messages.pl        # prolog:message//1 rules
├── app/pppc.pl                # CLI (library(main), argv_options/3); run as `swipl pppc`
├── tools/doc.pl               # pldoc HTML generation (make doc)
├── test/
│   ├── unit.pl                # loads and runs every test_*.plt (make test)
│   ├── test_<module>.plt      # one plunit file per module, plus test_cli.plt
│   ├── e2e.plt                # end-to-end tests (make check)
│   └── programs/              # *.pas + *.report, plus negative/
├── docs/superpowers/specs/
└── pascal-compiler-prolog.pdf
```

Conventions:

- Every file is a module with an explicit export list; modules are named
  `pppc_<pass>` and loaded as `library(pppc/<pass>)`.
- Exported predicates carry pldoc `%!` comments with modern mode
  indicators.
- No `assert` crosses a module boundary. State is passed as arguments;
  the only dynamic/tabled facts live inside `dataflow.pl` and are
  abolished at the start of each compilation.
- Output is produced by DCGs into strings/codes and written once at the
  end; no scattered `write/1`.
- Diagnostics use `print_message/2` with terms `pppc(...)`.

## 4. Source language: TAU-Pascal subset

**Program structure:** `program Name;` then `const`, `type`, `var`
sections; procedure and function declarations (value and `var`
parameters, top level only); `begin … end.`

**Types:** `integer`, `real`, `boolean`; subrange (array index types only);
`array[lo..hi {, lo..hi}] of T`; `record f1, f2: T; … end`; named type
aliases.

**Statements:** assignment; `if-then[-else]`; `for v := e to|downto e do`;
`while`; `repeat … until`; `begin … end`; procedure call;
`write`/`writeln` with expression and string-literal arguments.

**Expressions:** `+ - * /`, `div`, `mod`, unary `-` `+`, `and or not`,
`= <> < <= > >=`, `min`, `max`; standard functions `abs sqr sqrt sin cos
exp ln trunc round odd random`.

**TAU-Pascal extensions (from the paper):**

- `min`, `max` are dyadic operators with relational-operator precedence.
- Zero assignment `v := 0` is allowed for any array or record whose leaf
  elements are all numeric.

**`random`** is `random(n)` (integer in `0..n-1`) / `random` (real in
`[0,1)`), implemented in the C runtime header with per-thread state so it
is safe inside parallel loops. (Results of MontePi therefore differ
between serial and parallel builds; its end-to-end check compares to π
within a tolerance rather than to the serial output.)

**Excluded:** pointers, files, sets, variant records, `goto`/labels,
`with`, `case`, strings beyond write literals, nested procedure
declarations, procedure parameters.

Pascal is case-insensitive: the lexer downcases identifiers and keywords.

## 5. Intermediate representation

The IR is documented here as **source-language independent**: nothing
after the parser may depend on the input having been Pascal.

### 5.1 Tokens

`tok(Line, Kind)` where `Kind` is one of `kw(K)`, `id(Name)`,
`int(N)`, `real(R)`, `str(Codes)`, `punct(P)`.

### 5.2 Parse tree (paper format `name(Line, Args)`)

```
program(L, [Name, Block])
block(L, [Consts, Types, Vars, Procs, Body])
const_decl(L, [Name, Expr])
type_decl(L, [Name, TypeExpr])
var_decl(L, [Names, TypeExpr])
proc(L, [Name, Params, ResultTypeOrNone, Block])   % function if result type
param(L, [Mode, Names, TypeExpr])                   % Mode: value | var

% type expressions
tname(L, [Name])          subrange(L, [Lo, Hi])
array(L, [Ranges, Elem])  record(L, [Fields])   field_decl(L, [Names, T])

% statements
assign(L, [Target, Expr])
if(L, [Cond, Then, Else])                 % Else = empty(L, []) if absent
for(L, [Var, From, To, Dir, Body])        % Dir: up | down
while(L, [Cond, Body])
repeat(L, [Stmts, Cond])
compound(L, [Stmts])
pcall(L, [Name, Args])
write(L, [Newline, Args])                 % Newline: true | false
empty(L, [])

% expressions
op2(L, [Op, Left, Right])  op1(L, [Op, Arg])
id(L, [Name])  iconst(L, [N])  fconst(L, [R])  bconst(L, [B])  string(L, [Codes])
index(L, [Array, Indices])  field(L, [Record, FieldName])
fcall(L, [Name, Args])
```

### 5.3 Typed tree

Same functors with a third argument `Type`, e.g.
`op2(L, [Op, Left, Right], real)`. Statements carry type `void`.
Types are normalised terms: `integer`, `real`, `boolean`,
`array(Lo, Hi, Elem)` (one dimension; `array[1..n, 1..m] of real` is
`array(1, n, array(1, m, real))`), `record([Name-Type, …])`, plus `string`
(literals), `void` (statements) and `error` (after a reported error).

Differences from the parse tree, so later passes need no symbol table:

- constants are replaced by their values (`iconst`/`fconst`/`bconst`);
- `index` nodes have one subscript: `a[i, j]` becomes
  `index(L, [index(L, [a, i], _), j], _)`;
- references to `var` parameters are `vparam(L, [Name], T)`; assignment
  to the function's own name is `fresult(L, [Name], T)`;
- integer-to-real widening is `itor(L, [E], real)`;
- calls of standard functions are `builtin(L, [Name, Args], T)`, of user
  functions `fcall/3`; `var` arguments are wrapped as `addr(L, [V], T)`;
- `v := 0` on an all-numeric array or record is `zero_assign(L, [V], void)`;
- `block(L, [VarDecls, Procs, Body], void)` (consts and types are gone),
  `var_decl(L, [Names, Type], void)`, `param(L, [Mode, Names, Type], void)`,
  `proc(L, [Name, Params, ResultTypeOrNone, Block], void)`.

### 5.4 Symbol table

Internal to `semantic.pl`: an environment `env(Scopes, Routine)` where
Scopes is a list of `library(assoc)` maps (innermost first) from name to
`var(T)`, `vparam(T)`, `const(T, V)`, `type(T)` or `proc(Params, R)`.
Everything later passes need is carried by the typed tree (5.3), so no
symbol table is passed on.

## 6. Passes

All passes are deterministic. Each exported entry point is wrapped so
unexpected failure raises `pppc(internal(Pass))`.

### 6.1 Lexer (`lexer.pl`)

`tokens(-Tokens)//` over a code list read with `read_file_to_codes/3`.
Tracks line numbers; handles `{ … }` and `(* … *)` comments.

### 6.2 Parser (`parser.pl`)

DCG over the token list, with the standard Pascal precedence levels
(relational incl. `min`/`max` < additive < multiplicative < unary).
Left-associative operators are written iteratively (no left
recursion). On the first syntax error it throws
`pppc(syntax(Line, Expected, Found))`; no error recovery.

### 6.3 Semantic check (`semantic.pl`)

Processes declarations to build the symbol table, then types the body
bottom-up (`check_expr/4` in the shape of the paper's `check_expr/3`,
plus the symbol table). Operator typing is table-driven (`op2_type/4`
facts, as in the paper). Integer→real widening is explicit in the
typed tree. Errors (type clash, undeclared identifier, bad field,
wrong argument count, non-numeric zero assignment, …) are **collected**;
if any exist, all are printed and compilation fails.

### 6.4 Parallelizer (optional; skipped by `--serial`)

1. **Labelling** (`label.pl`): every statement gets a hierarchical label
   (list of integers); a compound statement's label is a prefix of its
   inner labels. Labelled statements are wrapped as
   `lbl(Label, Stmt)`. `begin … end` bodies of loops are transparent,
   `if` branches are `[P,1]` and `[P,2]`, empty statements in sequences
   are dropped — this reproduces the paper's labels and `reach/3` facts
   for its section 4.4.6 fragment exactly.
2. **Reaching definitions** (`dataflow.pl`): builds the statement-level
   control-flow graph from the labelled tree as facts
   (`def/2`, `use/2`, `succ/2`), then computes
   `reach(Var, DefLabel, UseLabel)` as a tabled fixpoint. Array element
   writes are non-killing definitions of the whole array; `var`
   parameters and procedure calls are treated conservatively (a call
   defines and uses every variable it could reach). Extra nodes: `[-1]`
   (entry, defines every variable) and `[0]` (exit, uses globals, `var`
   parameters and the function result). The facts live inside
   `with_dataflow/4`, which loads them, runs a goal and clears them and
   the tables.
3. **Parallel loop detection** (`parloop.pl`): bottom-up access summary
   per statement — referenced, changed, associative
   (`v := v op e`, `op ∈ {+,*,and,or,min,max}`, `v` not otherwise
   touched in the block), arrays — merged upwards as in the paper. A
   `for` loop is parallel iff every variable it touches is classified
   `index`, `read_only`, `distributed`, `associative(Op)` or `local`,
   using `is_local/2` etc. written after the paper (named helpers in
   place of nested `not/1`). The paper's fourth test ("never use a
   value defined in a previous iteration", via `before/2` on labels) is
   done exactly instead: `carried/3` asks whether a definition inside the
   loop reaches the loop header and then, along a path with no killing
   definition, a use inside the loop. (The paper does not define `before/2`;
   a plain ordering on labels cannot handle `sum` in the Jacobi loop,
   whose definition and use are the same statement of the inner loop,
   nor then/else branches, which are ordered as labels but never run in
   the same iteration.) Additional rules:
   - a body containing a user procedure/function call is never parallel;
   - a distributed array must be subscripted by the loop index in its
     first dimension, in every access in the body;
   - record variables are treated as single variables;
   - a `local` variable must only be assigned as a whole inside the loop
     (a private copy of a partly assigned array would lose elements);
   - a body that writes output (`write`) is never parallel (output order);
   - a body that assigns through a `var` parameter is never parallel
     (possible aliasing);
   - only the outermost eligible loop is marked (no nested parallelism).
4. **Transformation** (`transform.pl`): each marked loop becomes
   `omp_for(L, [Var, From, To, Dir, Body, Clauses])` with
   `Clauses = [private(Vs), shared(Vs), reduction(Op, Vs)]`.
   No cost check in Phase 1: every eligible outermost loop is
   parallelized.
5. **Cleanup**: strips labels, so the output has the same shape as the
   semantic pass output plus `omp_for` nodes.

### 6.5 Code generation (`codegen.pl`)

DCG producing C99 text: `#include`s and a small inline runtime
(`pppc_rt.h` contents emitted into the file: thread-safe `random`,
write helpers), typedefs for Pascal types, globals as `static` in
`main`'s translation unit, functions, `main`. Each statement is
followed by a `/* line N */` comment (as in the paper). Arrays are
0-based C arrays with index offset `lo` subtracted; `var` parameters
become pointers. `omp_for` emits

```c
#pragma omp parallel for private(...) shared(...) reduction(max:error)
for (i = lo; i <= hi; i++) { ... }
```

Pascal `for` bounds are evaluated once before the loop. Reductions map
`+ * and or min max` to `+ * && || min max`.

## 7. CLI and API

```
swipl pppc [--serial] [--dump=tokens|parse|typed|labelled|reach|parallel]
           [--report] [-o out.c] input.pas
```

- `--dump=Stage` prints the IR at that stage with `print_term/2` and stops.
- `--report` prints one line per `for` loop (used by the end-to-end tests):
  `Routine Line parallel Var:Class …` (classes sorted by variable),
  `Routine Line serial Reason …`, or `Routine Line nested OuterLine`.
- Exit status: 0 success, 1 source error, 2 internal error.

Library API: `pppc_compile(+SourceFile, +Options, -CText)`,
`pppc_stage(+SourceFile, +Stage, -Result)`, `pppc_report(+SourceFile, -Lines)`.

## 8. Error handling

| Kind | Mechanism | Behaviour |
|---|---|---|
| Missing source | `throw(pppc(no_source))` | exit 1 |
| Syntax | `throw(pppc(syntax(L, Exp, Found)))` | stop at first, exit 1 |
| Semantic | collected list of `pppc(semantic(L, Msg))`, thrown as `pppc(semantic_errors(List))` | report all, exit 1 |
| Internal | unexpected failure/exception in a pass | `pppc(internal(Pass, Reason))`, exit 2 |

All rendered via `prolog:message//1` in `messages.pl` as
`pppc(File, Error)`, printed by `print_message(error, …)` as
`ERROR: File:Line: …`.

## 9. Testing

- **Unit (plunit, `make test`)**, one `.plt` per module:
  lexer/parser snippets → expected terms; semantic well/ill-typed
  snippets; labelling of the paper's section 4.4.6 fragment; `reach/3`
  facts for that fragment (compared to the paper's listed facts);
  classification of the Jacobi excerpt (criterion 3); codegen snippets →
  expected C text.
- **CLI (`test_cli.plt`)**: runs `swipl pppc` and checks output and exit
  status for success, serial mode, semantic errors, syntax errors, a
  missing file, `--report` and `--dump`.
- **End-to-end (`make check`, `test/e2e.plt`)**, for each benchmark:
  compile `--serial` and parallel; build both with
  `gcc -O2 -Wall -Werror -fopenmp -lm`; run parallel at `OMP_NUM_THREADS=1` and `4`;
  compare to serial output (reals: relative tolerance 1e-9 unless the
  program's expected file states otherwise; MontePi: within 0.01 of π);
  compare `--report` output to an expected report file.
- **Negative programs** (`test/programs/negative/`): carried dependence
  (`a[i] := a[i-1] + 1`), user procedure call in loop body, non-index
  subscript (`a[2*i]`), scalar read before written in the body, output
  in the body; their expected reports show the loop as serial.
- **Features program** (`test/programs/features.pas`): procedures, `var`
  parameters, functions, records, zero assignment, `downto`, empty
  ranges, bounds changed in the body, `while`, booleans, `min`/`max`,
  standard functions, and identifiers that are C reserved names.
- Development is test-first (TDD) per module.

## 10. Benchmarks

Written fresh in TAU-Pascal from the paper's descriptions (section 4.3.6),
at sizes giving runs of a few seconds serially:

| Program | Content |
|---|---|
| pi | π by integrating `4/(1+x²)`, `sum` associative |
| montepi | π by Monte-Carlo, `random`, count associative |
| mandel | Mandelbrot set over a grid, distributed rows |
| linear | Jacobi iteration, `repeat` outside, paper's loop inside |
| nbody | 100 bodies in 3D, gravitational forces |
| mm | 140×140 matrix multiply (paper size; larger for timing later); b[i,j] = (i+2j)/n so the checked trace is not near zero |
| cg | conjugate gradient, 250 unknowns |

(Note: the paper's text mentions the integrand `√(1−x²)`; either works.)

## 11. Revisions after prototyping (2026-10-13)

The whole of Phase 1 was prototyped against SWI-Prolog 10.0.2 before the
implementation plan was written. Changes from the approved draft, all
reflected above:

- Array types are nested one-dimensional `array(Lo, Hi, Elem)`; the typed
  tree carries everything later passes need, so the symbol table stays
  inside `semantic.pl` (5.3, 5.4).
- `carried/3` replaces the paper's `before/2` test; locals must be wholly
  assigned; output and `var`-parameter assignment keep a loop serial (6.4).
- Missing source file error; internal errors carry a reason (8).
- `swipl pppc` pack app instead of a separate binary; `test/unit.pl`,
  `test/e2e.plt`, `tools/doc.pl`; no `.envrc` (2, 3, 7, 9).
- Added `features.pas` and `negative/io.pas`; changed mm's `b` matrix (9, 10).
