# pppc-prolog

A reproduction in SWI-Prolog of PPPC, the Portable Parallelizing Pascal
Compiler described by Eran Gabber in "PPPC: a Portable Parallelizing
Pascal Compiler", chapter 4 of Leon Sterling (ed.), *The Practice of
Prolog*, MIT Press, 1990. The paper is not included in this repository.

PPPC compiles a subset of Pascal (TAU-Pascal) and parallelizes the `for`
loops that are safe to run in parallel. A loop is made parallel only
when a run time prediction, using a cost table measured on the target
machine, says it will be faster. The original targeted a 1990
shared-memory multiprocessor; this reproduction generates C with OpenMP.

The project is also a way of relearning modern SWI-Prolog practice:
packs and apps, plunit, DCGs over token lists, tabling for dataflow
analysis, dicts, `library(process)`, and PlDoc.

## Using it

The development environment is pinned with [devenv](https://devenv.sh)
(SWI-Prolog 10.0.2, gcc 16 with OpenMP). Inside `devenv shell`, the
project is linked as the pack `pppc`:

```sh
swipl pppc test/programs/pi.pas -o pi.c     # compile to C + OpenMP
gcc -O2 -fopenmp pi.c -o pi -lm && ./pi
swipl pppc --report test/programs/linear.pas  # why each loop is (not) parallel
swipl pppc --predict test/programs/mm.pas     # predicted loop times and speedups
swipl pppc --const n=2000 --time test/programs/mm.pas -o mm.c  # resize, time loops
```

| Command | What it does |
|---|---|
| `make test` | unit tests (plunit) |
| `make check` | end-to-end: every test program built serial and parallel, outputs compared |
| `make calibrate` | measure the cost table on this machine (`prolog/pppc/cost/default.pl`) |
| `make bench` | measure speedups and loop verdicts (`bench/results.md`); several minutes, run on an idle machine |
| `make doc` | HTML documentation from the PlDoc comments |

## Layout

- `prolog/pppc.pl` and `prolog/pppc/`: the compiler passes (lexer,
  parser, semantic analysis, labelling, reaching definitions, parallel
  loop detection, run time prediction, transformation, C generation),
  plus calibration and the bench.
- `app/`: the `pppc`, `pppc_calibrate` and `pppc_bench` command lines.
- `test/`: unit tests, end-to-end tests and the test programs (the
  paper's benchmarks: pi, montepi, mandel, linear, nbody, mm, cg).
- `docs/superpowers/`: the design spec and implementation plan of each
  phase.
- `bench/results.md`: the latest measured speedups (the paper's
  Table 4.1) and notes on how well the prediction did.

## Status

- Phase 1: the compiler and the parallelization rules.
- Phase 2: the cost model and run time prediction.
- Phase 3: measuring speedups against the predictions.
- Phase 4 (planned): replicated SPMD regions.

## License

Copyright 2026 Chris Brew. Licensed under the Apache License, Version
2.0; see [LICENSE](LICENSE). The license covers this code only, not
Gabber's paper.
