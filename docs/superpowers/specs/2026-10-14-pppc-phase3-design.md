# PPPC Reproduction — Phase 3 Design: Measuring Speedups

Date: 2026-10-14
Status: Draft for review
Builds on: `2026-10-13-pppc-phase2-design.md` (merged to `master`; cost
table recalibrated at `bb07c4f`)

## 1. Purpose

Measure how close Phase 2's run time prediction is to reality
(Gabber 1990, section 4.3.6 and Table 4.1 "Speedup Measurements"):

- run the seven benchmarks at problem sizes that take seconds on 2026
  hardware, serially and in parallel at several thread counts;
- set the actual whole-program speedups beside the predicted ones, in
  the layout of Table 4.1;
- time every candidate loop serially and in parallel, and check each
  of the compiler's serial/parallel verdicts against the measurement.

The deliverable is `make bench` and its committed output
`bench/results.md`. Phase 4 (replicated SPMD regions) uses this harness
to show the effect of its changes.

The learning goal continues: this phase adds compile-time parameters
threaded through an existing pass, a third pack app, generating
instrumented C, running and timing processes, and producing a report
document from Prolog.

### Success criteria (Phase 3)

1. All Phase 1 and Phase 2 criteria still hold; the existing tests pass
   unchanged except where this spec adds to the cost table format
   (section 3).
2. `make bench` writes `bench/results.md` for all seven benchmarks on
   the development machine in under 10 minutes; the committed file is
   that output.
3. Each benchmark's serial run at its bench size takes 0.5–5 s, except
   `linear` and `cg`, which take at least 0.1 s (section 5.1).
4. The results say whether the `mandel` line 29 loop (the summing loop
   that the recalibrated table made parallel by a 7% predicted margin)
   is faster in parallel at 4 threads.
5. `make test` and `make check` pass inside the devenv shell.

### Out of scope (Phase 4 or later)

- Replicated SPMD regions (one `omp parallel` around an outer serial
  loop).
- Modelling SMT, caches or memory bandwidth in the cost model.
- Checking program output at bench sizes (`make check` does this at the
  small sizes).
- Changing prediction because of what the bench finds: findings go in
  the notes of `bench/results.md`; acting on them is later work.

## 2. Architecture

New and changed files:

| File | Role |
|---|---|
| `prolog/pppc/semantic.pl` | `check_program/4` with constant overrides |
| `prolog/pppc/codegen.pl` | `generate_c/3` with `timed(Keys)` |
| `prolog/pppc/cost.pl` | required `unit_seconds/1` fact; `unit_seconds/2` lookup |
| `prolog/pppc/calibrate.pl` | writes `unit_seconds(S)` |
| `prolog/pppc.pl` | options `const(Name=Value)` and `timing(Bool)` |
| `app/pppc.pl` | `--const NAME=VALUE`, `--time` |
| `prolog/pppc/bench.pl` | build, run, parse, compare, write markdown |
| `app/pppc_bench.pl` | the `swipl pppc_bench` pack app |
| `bench/sizes.pl` | bench problem sizes (data, read with `read_term/3`) |
| `bench/results.md` | committed bench output |
| `Makefile` | `bench` target |

`make bench` is not part of `make test` or `make check`: it is slow and
its results depend on the machine.

## 3. Inputs

### 3.1 Constant overrides

Option `const(Name=Value)`, which may be given more than once, accepted
by `pppc_compile/3`, `pppc_report/3`, `pppc_predict/3` and
`pppc_stage/4`. On the CLI: `--const NAME=VALUE`, repeatable.

- It replaces the value of a **program-level** `const` declaration
  (constants declared in procedures and functions cannot be
  overridden).
- Value is a literal of the declared constant's type: an integer, a
  real, or `true`/`false`. The type of the declared constant is the
  type of its expression.
- The substitution happens in the semantic pass: `check_program/4`
  (+Tree, +Overrides, -Typed, -Errors), with `check_program/3` calling
  it with `[]`. In `consts//3`, an overridden constant takes its value
  from Overrides instead of its expression; the expression is still
  evaluated, to find the type and report its own errors.
- Later constants (`h = 1.0 / n`) and types (`array[1..n] of real`)
  follow, because they are evaluated after the override.

Errors:

- a name that is not a program-level constant: `pppc(unknown_const(Name))`,
  exit 1, message "no program constant `Name'";
- a value of the wrong type: a semantic error at the constant's line,
  "cannot override constant `n' (integer) with 2.5";
- a CLI value that is not `NAME=VALUE` with a literal value: exit 1,
  in the style of the `--threads` message.

### 3.2 Seconds per unit

The calibrator already measures the time of one integer addition in
seconds. It now writes that time to the table as `unit_seconds(S)`, a
positive float. `cost.pl` requires the fact (it is a required entry,
checked like the others) and exports `unit_seconds(+Table, -S)`.
`test/costs/unit.pl` and `test/costs/free.pl` each gain a
`unit_seconds/1` fact, and the shipped table is regenerated.

Prediction and decisions do not use `unit_seconds`; only the bench
does, to convert predicted times to seconds.

## 4. Timing each loop

Option `timing(true)` of `pppc_compile/3`; CLI `--time`. It combines
with every build mode: `serial(true)`, the default (predicted), and
`prediction(false)`.

**Which loops.** The *candidate* loops: the outermost loops that obey
the parallelization rules, that is, those with the `parallel` verdict
from `analyse_program/2` before run time prediction. These are the
loops `--predict` lists. They are timed whether or not the build makes
them parallel, so the serial and parallel builds time the same loops.
`pppc_compile/3` takes the list of `Routine-Line` keys from the
analysis and passes it as `generate_c(Program, [timed(Keys)], C)`;
`generate_c/2` calls `generate_c/3` with `[]`.

**Generated C.** With K > 0 timed loops, the runtime part gains

```c
static double PPPC_t[K];
static long PPPC_n[K];
static const char *const PPPC_where[K] = { "program 29", ... };
static void PPPC_report_times(void) { /* print each entry */ }
```

and `main` begins with `atexit(PPPC_report_times);`. Timed loop k is
emitted as

```c
{   double PPPC_t0 = omp_get_wtime();
    <the loop, with its #pragma if it is parallel>
    PPPC_t[k] += omp_get_wtime() - PPPC_t0;
    PPPC_n[k]++;
}
```

At exit, one line per timed loop goes to **stderr**, in key order:

```
pppc_time program 29 1 4.21e-06
```

giving routine, line, number of executions and total seconds (`%.6e`).
A loop that never ran is printed with 0 executions. stdout is
unchanged, so a timed build prints the same as an untimed one. With no
timed loops, or without `timing(true)`, the C text is exactly what
Phase 2 generates.

**No locking is needed.** A loop that contains a call of a user routine
is never a candidate, so no candidate loop can run inside another
candidate's body. The counters are only touched by the master thread.

**Timer cost.** `omp_get_wtime` costs about 20 ns; the smallest
interesting loop (`mandel` line 29) takes about 1 µs.

## 5. The bench (`bench.pl`, `app/pppc_bench.pl`)

### 5.1 Sizes

`bench/sizes.pl` holds one fact per benchmark:

```prolog
size(mm, [n=1400]).
```

The key is the program's base name in `test/programs`; the list gives
the constant overrides. Sizes are chosen so the serial run takes
0.5–5 s on the development machine (1–3 s aimed for), except `linear`
and `cg` (see criterion 3). The sizes, with serial times measured
while planning:

| Program | Overrides | Serial |
|---|---|---|
| pi | n = 2000000000 | 2.1 s |
| montepi | n = 300000000 | 1.9 s |
| mandel | nx = 2400, ny = 1800 | 1.1 s |
| linear | n = 5000 | 0.24 s |
| nbody | n = 1500 | 1.6 s |
| mm | n = 1400 | 1.3 s |
| cg | n = 5000 | 0.20 s |

The file is read
with `read_term/3`; a term that is not `size(Atom, List)` with
`Name=Value` elements, or a duplicate key, gives
`pppc(bench(bad_sizes(File, Culprit)))`.

### 5.2 Options

```
swipl pppc_bench [-o FILE] [--threads LIST] [--repeat K]
                 [--program NAME]... [--cost FILE]
```

- `--threads 1,2,4,8,12`: the thread counts; default the speedup points
  (Phase 2, `speedup_points/2`) up to the number of CPUs; Pmax is the
  largest.
- `--repeat K`: runs of each binary at each thread count; the median is
  reported. Default 3.
- `--program NAME`: limit to these benchmarks (repeatable); default all
  seven: pi, montepi, mandel, linear, nbody, mm, cg.
- `--cost FILE`: the cost table, as for `pppc`.
- `-o FILE`: write the report there (see 5.5); default standard output.

The Prolog entry point is `bench(+Options, -Results)` plus
`write_results(+Stream, +Results, +Options)`, following
`calibrate/2` and `write_table/3`.

### 5.3 For each benchmark

1. **Predict.** `pppc_predict` with the program's overrides and
   `threads(Pmax)` gives the predicted whole-program speedup at every P
   (the loops are chosen once, at Pmax). For the per-loop table, the
   same call at each P gives `loop_time(R, L, S, Par)`.
2. **Build** three binaries with `gcc -O2 -fopenmp`, all with
   `timing(true)` and the overrides:
   - `serial`: `serial(true)`;
   - `parallel`: the default, with `threads(Pmax)`; one binary is run
     at every P, as in the paper;
   - `all`: `prediction(false)`, every candidate loop parallel.
3. **Run** `serial` K times, and `parallel` and `all` K times at each P,
   with `OMP_NUM_THREADS=P` and `OMP_PROC_BIND=close`. Whole-program
   wall time is taken around `process_create/3` and `process_wait/2`;
   per-loop times come from the `pppc_time` lines on stderr; stdout is
   discarded.
4. **Compare.**
   - Actual speedup at P: median serial wall time / median `parallel`
     wall time at P.
   - For each candidate loop and P: predicted serial and parallel time
     (units × `unit_seconds`, shown in µs); actual serial time per
     execution (total seconds / executions, from `serial`); actual
     parallel time per execution (from `all` at P); predicted verdict
     (parallel if Par < S) and actual verdict (parallel if the actual
     parallel time is smaller); whether they agree.

### 5.4 Errors

Errors are `pppc(bench(Why))`, exit 1 (internal errors exit 2):
`no_gcc`, `build_failed(Program, Mode, Stderr)`,
`run_failed(Program, Mode, P, Status)`, `bad_timing(Line)` for a
`pppc_time` line that does not parse, `missing_size(Program)`, and
`bad_sizes(File, Culprit)`. Compiler errors in a benchmark propagate
as the usual `pppc(_)` errors.

### 5.5 `bench/results.md`

1. A header: date, CPU model, gcc version, cost table file, K, thread
   counts, and the sizes used.
2. **Table 4.1**, in the paper's layout: per benchmark, a `Predicted`
   row and an `Actual` row, one column per P, and the serial wall time
   in seconds.
3. **Loops**: one table each for P = 4 and P = Pmax (only those of the
   two that were measured): routine, line, predicted serial/parallel
   µs, actual serial/parallel µs, predicted and actual verdict, agree.
4. **Verdicts**: one summary line per table, for example "verdict right
   for 14 of 15 candidate loops at P=4".
5. A `<!-- notes -->` marker. When `-o FILE` names an existing file,
   everything after the marker is kept, so hand-written notes survive
   re-runs. The notes record findings, such as speedups flattening
   above 6 threads: the 5600G has 6 cores with 2 hardware threads
   each, which the cost model does not know about.

## 6. API, CLI and messages

### 6.1 API (`prolog/pppc.pl`)

- `const(Name=Value)` (repeatable): section 3.1; accepted by
  `pppc_compile/3`, `pppc_report/3`, `pppc_predict/3`, `pppc_stage/4`.
- `timing(Bool)`: section 4; accepted by `pppc_compile/3`.

### 6.2 CLI (`swipl pppc`)

- `--const NAME=VALUE`, repeatable;
- `--time`.

### 6.3 Messages (`messages.pl`)

New messages for `unknown_const(Name)`, the override type error, the
bad `--const` value, and each `bench(Why)`.

## 7. Testing

### 7.1 Unit (`make test`)

- **Constant overrides**: `n=50` changes `pi`'s loop trip count, seen
  in `--predict`; a dependent constant follows the override; an
  overridden array bound changes the array type; a real value for an
  integer constant is a semantic error at the constant's line; an
  unknown name exits 1 with its message; a bad `--const` value exits 1.
- **`unit_seconds`**: a table without it is rejected; normalising the
  canned calibration samples gives the expected value; the shipped
  table loads and has it.
- **Timing**: the C for a small program has exactly one timer per
  candidate loop and none for nested or non-candidate loops; a
  compiled, timed program prints the expected `pppc_time` keys and
  counts on stderr and the same stdout as an untimed build, including a
  candidate loop in a procedure called from a serial loop (count = the
  number of calls); without `timing(true)` the C text is unchanged.
- **Bench, with canned data**: parsing `pppc_time` lines and rejecting
  bad ones; medians and speedups; verdict agreement; the markdown
  layout (a golden string); keeping the text after the notes marker;
  validating `bench/sizes.pl`, which must have a fact for each of the
  seven benchmarks.
- **Bench smoke test**: `pi` at `n=100000`, threads 1 and 2, repeat 1,
  to a temporary file that must contain both tables.

### 7.2 End-to-end (`make check`)

Unchanged.

### 7.3 Bench (`make bench`)

Run on the idle development machine, and the output committed. It is
not an automated test.

## 8. Revisions after review (2026-10-15)

1. **linear and cg run shorter.** Both matrices are diagonally
   dominant, so Jacobi and CG converge in 4–6 iterations at any n, and
   time grows only with n². At n = 5000 (a 200 MB matrix) they take
   about 0.2 s. Rather than change the programs, criterion 3 allows
   them at least 0.1 s; medians of K runs still resolve their speedups.
   At this size they are bound by memory bandwidth, which the notes
   can record.
2. **Sizes recorded** in section 5.1, measured with the Phase 2
   compiler on scratch copies.
