# PPPC Reproduction — Phase 2 Design: Cost Model and Run Time Prediction

Date: 2026-10-13
Status: Draft for review
Builds on: `2026-10-13-pppc-phase1-design.md` (merged to `master` at `eb3dcc2`)

## 1. Purpose

Add the paper's target cost table, run time prediction and profitability
decision (Gabber 1990, sections 4.3.4 and 4.4.6 "Run Time Prediction"):

- a loop that obeys the parallelization rules is parallelized only if its
  predicted parallel time is shorter than its serial time;
- the compiler reports predicted loop times and whole-program speedups;
- the cost table is measured on the target machine by a calibration
  program, as in the paper.

The learning goal continues: this phase adds explicit data passing in
place of global facts, exact rational arithmetic, generating and running
C from Prolog (`library(process)`), a second pack app, and validating
data files read with `read_term/3`.

### Success criteria (Phase 2)

1. All Phase 1 criteria still hold (serial/parallel output identical,
   Jacobi classification, negative programs serial, suites pass).
2. `pppc --predict` prints loop times and a speedup row for each of the
   seven benchmarks.
3. Prediction follows section 4.3.4 exactly (section 4 below); this is
   checked by hand-computed expectations against a unit cost table.
4. A loop is parallelized only when its predicted parallel time is
   shorter: `negative/small.pas` stays serial at N = 4, and a test shows
   a loop whose verdict changes with N.
5. `pppc_calibrate` produces a table that loads; the committed default
   table is its output on the development machine.
6. `make test` and `make check` pass inside the devenv shell.

### Out of scope (Phase 3 or later)

- Replicated SPMD regions (one `omp parallel` around an outer serial loop).
- `make bench`: measured speedups and the predicted-vs-actual Table 4.1.
- Larger problem sizes for 2026 hardware.
- A Python front end; nested parallelism; inter-procedural analysis.

## 2. Architecture

New modules:

| File | Role |
|---|---|
| `prolog/pppc/cost.pl` | load and validate a cost table; lookups |
| `prolog/pppc/predict.pl` | serial and parallel times; decisions; program prediction |
| `prolog/pppc/calibrate.pl` | generate, build and run C probes; write a table |
| `prolog/pppc/cost/default.pl` | the shipped table (data, never consulted) |
| `app/pppc_calibrate.pl` | the `swipl pppc_calibrate` pack app |
| `test/costs/unit.pl` | fixed table for exact unit tests |

Pipeline (the parallelizer gains a phase between detection and
transformation):

```
lexer → parser → semantic → label/dataflow/parloop → predict → transform → codegen
```

The cost table is **passed explicitly** (approach A): `load_cost_table/2`
reads a file into an opaque `Table` term and every costing predicate
takes it as an argument. No global state is asserted, so concurrent
compilations with different tables cannot interfere.

## 3. Cost table

### 3.1 Format

A plain file of facts, read with `read_term/3` (never consulted). Costs
are non-negative integers in units of one integer addition.

```prolog
cost_op2(Op, LeftType, RightType, Cost).   % dyadic operators (paper's shape)
cost_op1(Op, Type, Cost).                  % monadic operators (paper's shape)
cost_func(Name, Cost).                     % standard functions (paper's shape)
cost(Key, Cost).                           % Key: index store loop if call param itor write_item
default_trips(Trips).                      % iterations assumed for unknown bounds; 25
overhead(Kind, P, Cost).                   % Kind: fork_join | reduction; one fact per measured P
```

`cost/2` and `overhead/3` are this project's counterpart of the paper's
VMMP cost-function parameters (`a + f(#processors)·(b + c·sizeof(data))`):
on shared-memory OpenMP there is no data distribution, so the overhead
is fork/join plus a per-reduction-variable combine, each measured per P.

### 3.2 Required keys and validation

`cost.pl` holds the list of required entries: one `cost_op2` for each
operator typing the semantic pass accepts (`op2_rule/4`: 29 entries),
one `cost_op1` for each `op1_rule/3` (3), one `cost_func` per standard
function (`abs sqr sqrt sin cos exp ln trunc round odd random`), every
`cost/2` key above, `default_trips/1`, and at least one `overhead/3` fact
of each kind, with P = 1 present. A unit test checks the required list
against the semantic pass's rules, so adding an operator there without
a cost fails the suite.

`load_cost_table(+File, -Table)`:

- missing or unreadable file → `pppc(cost_table_missing(File))`;
- a term that is not a fact of a known shape, a non-integer or negative
  cost, a duplicate entry → `pppc(bad_cost_table(File, Fact))`;
- a missing required entry → `pppc(bad_cost_table(File, missing(Key)))`.

`Table` is a dict from kind to entries; `cost.pl` exports lookups
(`op2_cost/5`, `op1_cost/4`, `func_cost/3`, `unit_cost/3`, `trips/2`,
`overhead/4`). `overhead(Table, Kind, P, Cost)` returns the measured value
at P, or for P beyond the largest measured point extrapolates linearly
from the last two (the last one alone if only one is measured).

### 3.3 Default table

`prolog/pppc/cost/default.pl` is the output of `pppc_calibrate` on the
development machine, committed. It is located with
`absolute_file_name(library(pppc/cost/default), F, [file_type(prolog), access(read)])`.
Regenerating it is deliberate (`make calibrate`); tests never depend on
live timings.

## 4. Run time prediction (`predict.pl`)

Prediction runs over the labelled routine bodies produced by
`analyse_program/2` (statements wrapped as `lbl(Label, Stmt)`), so loop
times can be keyed by label. Times are computed with **exact rational arithmetic** (`rdiv`), so the
mean of two branches stays exact; they are rounded only for display.

### 4.1 Expressions (after the paper's `cost_expr/2`)

| Node | Cost |
|---|---|
| `id`, `vparam`, `iconst`, `fconst`, `bconst`, `string` | 0 |
| `op2(_, [Op, L, R], _)` | L + R + `cost_op2(Op, TL, TR)` (operand types) |
| `op1(_, [Op, E], _)` | E + `cost_op1(Op, T)` |
| `itor(_, [E], _)` | E + `cost(itor)` |
| `index(_, [A, I], _)` | A + I + `cost(index)` |
| `field(_, [R, _], _)` | R |
| `builtin(_, [F, Args], _)` | `cost_func(F)` + Σ (arg + `cost(param)`) |
| `fcall(_, [F, Args], _)` | routine time of F + `cost(call)` + Σ (arg + `cost(param)`) |
| `addr(_, [V], _)` | V |

### 4.2 Statements

Let `Trips(F, T, Dir)` be `max(0, T − F + 1)` (`up`) or
`max(0, F − T + 1)` (`down`) when both bounds are `iconst`, otherwise
`default_trips`.

| Statement | Serial time |
|---|---|
| `assign(_, [T, E], _)`, scalar target | T + E + `cost(store)` |
| `assign`, array/record target (whole copy) | T + E + n · `cost(store)`, n = number of scalar leaves of the type |
| `zero_assign(_, [V], _)` | V + n · `cost(store)` |
| `if(_, [C, Th, El], _)` | C + `cost(if)` + (Th + El) / 2 |
| `for(_, [V, F, T, D, B], _)` | F + T + Trips · (B + `cost(loop)`) |
| `while(_, [C, B], _)`, `repeat(_, [B, C], _)` | `default_trips` · (B + C + `cost(loop)`) |
| `compound(_, [Ss], _)` | Σ Ss |
| `pcall(_, [P, Args], _)` | routine time of P + `cost(call)` + Σ (arg + `cost(param)`) |
| `write(_, [_, Args], _)` | Σ (arg + `cost(write_item)`) |
| `empty` | 0 |

The routine time of a user routine is its body's time. Routines are
costed on demand with a stack of routines being costed; a call to a
routine already on the stack (recursion) contributes `cost(call)` and its
arguments only, so prediction terminates.

### 4.3 Parallel loops and the decision

For an outermost eligible loop (Phase 1 verdict `parallel`) with body
time B, bounds F, T, Trips iterations and R associative variables, its
parallel time at P threads is

```
F + T + ⌈Trips / P⌉ · (B + cost(loop)) + overhead(fork_join, P) + R · overhead(reduction, P)
```

It stays `parallel` iff its parallel time at P = N is less than its
serial time; otherwise its verdict becomes
`serial([unprofitable(S, Par)])` with both times rounded to integers.
Inner loops keep their `nested(Outer)` verdict, which now means "covered
by the decision at the outer loop": as in the paper (section 4.3.5) no
inner loop is tried, since it does the same total work with more forks
and so is never more profitable.

Loops inside routines are decided the same way with their own routine's
times.

### 4.4 Whole-program prediction

The program's time at P is the main body's time, computed as in 4.2
except that each loop whose final verdict is `parallel` (in any routine)
takes its parallel time at P. The serial time is the same with no loop
parallel. The predicted speedup at P is `Serial / Time(P)` for P in 1..N,
with the decisions fixed at N. At P = 1 the speedup may be slightly
below 1 because fork/join still has a cost.

`decide(+Routines0, +Table, +N, -Routines, -Prediction)` rewrites
verdicts and returns

```
prediction(Loops, Serial, Speedups)
  Loops    = [loop_time(Routine, Line, SerialTime, ParallelTimeAtN), ...]
             (one per outermost eligible loop, source order)
  Serial   = program serial time (rational)
  Speedups = [1-S1, 2-S2, ..., N-SN] (rationals)
```

## 5. Calibration (`calibrate.pl`, `app/pppc_calibrate.pl`)

```
swipl pppc_calibrate [-o FILE] [--max-threads N] [--repeat K]
```

Defaults: standard output; `--max-threads` from
`current_prolog_flag(cpu_count, C)`; `--repeat 5`. `make calibrate`
regenerates `prolog/pppc/cost/default.pl`.

1. **Generate.** A table of probes `probe(Key, Decls, Step)` gives, for
   each required entry of 3.2, a C fragment; the generator writes one C
   file: a harness timing each probe with `omp_get_wtime()` over a
   dependent chain of the operation (each step consumes the previous
   result), operands initialised through `volatile`, the result stored to
   a `volatile` sink so gcc cannot fold or remove the work. An empty
   chain is the baseline. Probes for operations C compiles to nothing
   (e.g. unary `+`) are not emitted and cost 0.
2. **Build and run** with `process_create/3`: `gcc -O2 -fopenmp` in a
   temporary directory (`tmp_file/2`), then run; output is one
   `Key Seconds` line per probe and run.
3. **Normalise.** Subtract the baseline, divide by the integer-add time,
   take the median of K runs, round to an integer with minimum 1.
4. **OpenMP overheads.** For P in 1..max-threads: `fork_join` is the time
   of `#pragma omp parallel for num_threads(P)` over P empty iterations;
   `reduction` is the extra time of the same loop with a
   `reduction(+:s)` clause; both in integer-add units.
5. **Write** the table with `portray_clause/2`, after a header comment
   giving date, CPU model (from `/proc/cpuinfo` when present), gcc version
   and options.

Errors (no gcc, build failure, unparsable output) are
`pppc(calibrate(Why))`, exit 1; internal errors exit 2, as for `pppc`.

**Accepted limitation.** Costing operations in isolation ignores
instruction overlap, caches and vectorisation, so absolute predicted
times are approximate. The decision depends on the ratio of loop work to
fork/join cost, which is measured directly. Phase 3 measures how close
the predictions are.

## 6. API, CLI and output

### 6.1 API (`prolog/pppc.pl`)

New options, accepted by `pppc_compile/3`, `pppc_report/3`,
`pppc_predict/3` and `pppc_stage/3`'s `predict` stage:

- `threads(N)`: P used for the decision, default 4; N must be a positive
  integer, otherwise `pppc(bad_threads(N))`.
- `cost(File)`: cost table, default the shipped table.

Changes:

- `pppc_compile/3` uses both (`serial(true)` still skips the
  parallelizer, and with it prediction and table loading).
- `pppc_report/3` (`+File, +Options, -Lines`); `pppc_report/2` calls it
  with `[]`. A loop may now report `program 12 serial unprofitable(1500,8200)`.
- New `pppc_predict(+File, +Options, -Prediction)` returning the term of
  4.4.
- `pppc_stage/3` gains stage `predict` (default options), so `--dump predict`
  works.
- `pppc_transform:parallelize_program/3` becomes `/4` (`+Typed, +Options,
  -Parallel, -Routines`); `analyse_program/2` is unchanged. The table is
  loaded once per compile inside `pass(cost, …)`; its `pppc(_)` errors pass
  through as source errors (exit 1).

### 6.2 CLI (`swipl pppc`)

- `--threads N`, `--cost FILE`: the options above.
- `--report`: unchanged format, now with `unprofitable` verdicts.
- `--predict` (new): loop times and speedups, aligned with `format/2`
  column stops, times rounded to integers, speedups to two decimals:

```
program  10  serial    6250500  parallel@4   1570125
program  21  serial    3312500  parallel@4    836125
program serial 9563000
speedup 1:0.99 2:1.97 3:2.93 4:3.88
```

### 6.3 Messages (`messages.pl`)

`cost_table_missing(File)`, `bad_cost_table(File, Fact)`,
`bad_threads(N)`, and the `calibrate(Why)` family (`no_compiler`,
`build_failed(Output)`, `bad_output(Line)`).

## 7. Testing

### 7.1 Unit (`make test`)

- `test_cost.plt`: the default table loads; required list matches the
  semantic pass's operator and builtin rules; bad fact, negative cost,
  duplicate and missing entry give `bad_cost_table`; missing file gives
  `cost_table_missing`; overhead at a measured P and extrapolated beyond.
- `test_predict.plt`, against `test/costs/unit.pl` (every operation and
  `cost/2` key costs 1, `default_trips(25)`, `fork_join` = 100·P,
  `reduction` = 10·P, measured for P = 1..4): expected times computed by
  hand, with the arithmetic in a comment, for straight-line code, `if`
  (exact half), constant `for`, `downto`, empty range, default trips,
  `while`/`repeat`, whole-array assignment, `zero_assign`, user call,
  recursion, parallel time with ⌈Trips/P⌉ and reductions, a loop
  profitable at N = 4 but not at N = 1, inner loops of an unprofitable
  loop staying `nested`, the speedup list, and extrapolation at N = 8.
- `test_calibrate.plt`, no live timings: the generated C compiles with
  gcc; parsing canned output; normalising canned numbers to the expected
  table; the written table reads back through `load_cost_table/2`. One
  smoke test runs a real calibration with `--max-threads 2 --repeat 1`
  and checks only that the result loads.
- `test_cli.plt`: `--threads`, `--cost`, `--predict`; exit 1 for a bad
  table and a bad thread count.

### 7.2 End-to-end (`make check`)

Unchanged procedure, now with the default table at N = 4: each program's
`--report` equals its `.report` file and its parallel outputs equal the
serial build at `OMP_NUM_THREADS` 1 and 4. New
`negative/small.pas`: an eligible 10-iteration loop that must report
`serial unprofitable(…)`. Any `.report` file whose verdicts change is
updated in the commit that changes it, with the reason stated.
Because `unprofitable(S, Par)` carries times, regenerating the default
table (`make calibrate`) may change `.report` files; they are re-checked
and updated in the same commit as the new table.

## 8. Revisions after prototyping (2026-10-13)

The plan was written from a prototype that passed every test; these
are the points where it departs from sections 1–7.

1. **Calibration method (5).** Subtracting an empty-loop baseline from
   independent operations gave unstable tables (an out-of-order CPU
   overlaps one addition with the loop's own work, so the unit of
   measurement was a small, noisy difference). Probes now repeat their
   operation U = 4 and U = 12 times per iteration, and an operation's
   time is the difference divided by 8, which cancels the loop
   overhead. Operators are timed as dependent chains (`p_a = p_a + p_b`),
   so one integer addition is one cycle; library functions are timed
   unchained (a chain of `exp` or `ln` reaches infinity or NaN).
   Default iterations are 10^6; the output probe runs 1/64 of them.
   Two runs on the development machine agree on every entry but
   `write_item` (147 vs 149).
2. **Probes reuse codegen.** `pppc_codegen` exports `runtime_text/1`,
   and expression probes are typed tree nodes printed by `c_expr/2`, so
   calibration times the C the compiler emits.
3. **`parallelize_program/5`** (`+Typed, +Table, +N, -Parallel,
   -Routines`) replaces the planned `/4` with options: options are read
   and the table loaded once, in `pppc.pl`. `parallelize_program/3`
   remains and transforms every eligible loop without prediction (the
   Phase 1 behaviour, used by the transformation tests).
4. **End-to-end coverage (7.2).** With the shipped table, short loops in
   the Phase 1 regression programs (`names.pas`, `results.pas`,
   `features.pas`) are now serial, so their parallel code would no
   longer be compiled or run. `make check` therefore builds every
   program three ways: serial, parallel with the shipped table, and
   parallel with `test/costs/free.pl`, a table whose parallel regions
   cost nothing, so every eligible loop of two or more iterations is
   parallel as in Phase 1.
5. **Required-entry check (3.2).** The semantic pass's typing rules
   test membership (`memberchk/2`) and cannot enumerate, so the test
   runs every operator of the language over every pair of scalar types
   in both directions.
6. **The default table is recorded, not regenerated, by the plan.**
   `prolog/pppc/cost/default.pl` is the prototype's `make calibrate`
   output on the development machine (AMD Ryzen 5 5600G, gcc 16.2), so
   the `.report` files that carry `unprofitable(S, P)` times are exact.
7. **Verdict changes with the shipped table at N = 4.** Eligible loops
   that become `serial unprofitable(…)`: the one-pass vector loops of
   `cg` (lines 21, 34, 51), the final sum of `linear` (34), `mandel`
   (29) and `mm` (23), and the short loops of `features`, `names` and
   `results`. The heavy loops (Jacobi's iteration, matrix product,
   Mandelbrot rows, n-body forces, pi, montepi) stay parallel.
8. `--dump` accepts `predict`; `tools/doc.pl` loads every module before
   documenting it (it previously relied on `library(pppc)` loading them
   all, which `calibrate.pl` is not).
