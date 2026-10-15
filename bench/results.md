# PPPC benchmark results

- Date: 2026-10-15 05:06:05
- CPU: AMD Ryzen 5 5600G with Radeon Graphics
- gcc: 16.2.0 (-O2 -fopenmp)
- Cost table: /home/cbrew/working/pascal_compiler/prolog/pppc/cost/default.pl
- Each time is the median of 3 runs

| Program | Sizes |
|---|---|
| pi | n=2000000000 |
| montepi | n=300000000 |
| mandel | nx=2400, ny=1800 |
| linear | n=5000 |
| nbody | n=1500 |
| mm | n=1400 |
| cg | n=5000 |

## Speedups (Table 4.1)

| Program | | Serial (s) | P=1 | P=2 | P=3 | P=4 | P=5 | P=6 | P=7 | P=8 | P=12 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| pi | Predicted | 2.20 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 7.00 | 8.00 | 12.00 |
| | Actual | | 1.02 | 2.02 | 2.97 | 3.95 | 4.87 | 5.80 | 3.45 | 3.90 | 5.71 |
| montepi | Predicted | 1.95 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 7.00 | 8.00 | 12.00 |
| | Actual | | 1.66 | 3.27 | 4.84 | 6.32 | 7.66 | 8.03 | 6.48 | 7.35 | 9.75 |
| mandel | Predicted | 1.13 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 6.98 | 8.00 | 12.00 |
| | Actual | | 1.00 | 1.97 | 1.42 | 2.12 | 2.05 | 2.77 | 2.78 | 3.42 | 4.53 |
| linear | Predicted | 0.25 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 5.99 | 6.99 | 8.00 | 11.99 |
| | Actual | | 0.99 | 1.77 | 2.17 | 2.40 | 2.62 | 2.70 | 2.75 | 2.61 | 2.62 |
| nbody | Predicted | 1.60 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 6.97 | 7.97 | 11.99 |
| | Actual | | 0.99 | 1.94 | 2.88 | 3.79 | 4.66 | 5.38 | 3.39 | 3.89 | 5.00 |
| mm | Predicted | 1.31 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 5.98 | 7.00 | 8.00 | 11.97 |
| | Actual | | 0.97 | 1.66 | 2.14 | 3.46 | 4.45 | 4.92 | 1.89 | 2.18 | 3.40 |
| cg | Predicted | 0.21 | 1.00 | 2.00 | 3.00 | 4.00 | 5.00 | 5.99 | 6.99 | 8.00 | 11.98 |
| | Actual | | 1.00 | 1.74 | 2.27 | 2.42 | 2.67 | 2.74 | 2.73 | 2.86 | 2.53 |

## Loops at P=4

Time of one execution of each candidate loop, in µs. Actual parallel times are from the build with every candidate loop parallel.

| Program | Loop | Predicted serial | Predicted parallel | Actual serial | Actual parallel | Predicted | Actual | Agree |
|---|---|---:|---:|---:|---:|---|---|---|
| pi | program 9 | 16267681.3 | 4066921.2 | 2197693.0 | 554950.2 | parallel | parallel | yes |
| montepi | program 8 | 2440152.2 | 610039.0 | 1949690.0 | 307655.9 | parallel | parallel | yes |
| mandel | program 8 | 1213868.8 | 303468.1 | 1131519.0 | 550811.1 | parallel | parallel | yes |
| mandel | program 29 | 4.0 | 1.9 | 2.4 | 11.8 | parallel | serial | no |
| linear | program 10 | 172573.0 | 43144.2 | 117544.7 | 34190.2 | parallel | parallel | yes |
| linear | program 21 | 147963.2 | 36991.7 | 19233.4 | 7779.1 | parallel | parallel | yes |
| linear | program 34 | 13.6 | 4.3 | 4.9 | 5.7 | parallel | serial | no |
| nbody | program 9 | 51.8 | 13.9 | 68.0 | 198.6 | parallel | serial | no |
| nbody | program 21 | 34670.9 | 8668.6 | 7986.5 | 2084.5 | parallel | parallel | yes |
| nbody | program 42 | 49.5 | 13.3 | 3.0 | 4.4 | parallel | serial | no |
| nbody | program 53 | 22.9 | 6.6 | 2.4 | 2.9 | parallel | serial | no |
| mm | program 8 | 28503.6 | 7126.8 | 17683.9 | 5325.7 | parallel | parallel | yes |
| mm | program 14 | 19621141.3 | 4905286.2 | 1288383.0 | 349021.6 | parallel | parallel | yes |
| mm | program 23 | 5.5 | 2.3 | 11.8 | 10.5 | parallel | parallel | yes |
| cg | program 10 | 191098.4 | 47775.5 | 113971.1 | 31840.2 | parallel | parallel | yes |
| cg | program 21 | 23.4 | 6.8 | 5.3 | 7.1 | parallel | serial | no |
| cg | program 26 | 147900.3 | 36976.0 | 19082.1 | 6806.0 | parallel | parallel | yes |
| cg | program 34 | 23.4 | 6.8 | 5.2 | 5.8 | parallel | serial | no |
| cg | program 38 | 77.6 | 20.3 | 5.5 | 5.6 | parallel | serial | no |
| cg | program 46 | 29.6 | 8.3 | 2.2 | 3.5 | parallel | serial | no |
| cg | program 51 | 13.6 | 4.3 | 4.8 | 3.4 | parallel | parallel | yes |

Verdict right for 12 of 21 candidate loops at P=4.

## Loops at P=12

Time of one execution of each candidate loop, in µs. Actual parallel times are from the build with every candidate loop parallel.

| Program | Loop | Predicted serial | Predicted parallel | Actual serial | Actual parallel | Predicted | Actual | Agree |
|---|---|---:|---:|---:|---:|---|---|---|
| pi | program 9 | 16267681.3 | 1355642.1 | 2197693.0 | 382869.7 | parallel | parallel | yes |
| montepi | program 8 | 2440152.2 | 203348.0 | 1949690.0 | 191154.8 | parallel | parallel | yes |
| mandel | program 8 | 1213868.8 | 101157.4 | 1131519.0 | 263060.6 | parallel | parallel | yes |
| mandel | program 29 | 4.0 | 2.3 | 2.4 | 814.3 | parallel | serial | no |
| linear | program 10 | 172573.0 | 14394.2 | 117544.7 | 25332.1 | parallel | parallel | yes |
| linear | program 21 | 147963.2 | 12342.1 | 19233.4 | 8993.3 | parallel | parallel | yes |
| linear | program 34 | 13.6 | 3.1 | 4.9 | 5.2 | parallel | serial | no |
| nbody | program 9 | 51.8 | 5.9 | 68.0 | 602.0 | parallel | serial | no |
| nbody | program 21 | 34670.9 | 2890.9 | 7986.5 | 1442.2 | parallel | parallel | yes |
| nbody | program 42 | 49.5 | 5.8 | 3.0 | 12.7 | parallel | serial | no |
| nbody | program 53 | 22.9 | 3.8 | 2.4 | 3.8 | parallel | serial | no |
| mm | program 8 | 28503.6 | 2383.7 | 17683.9 | 3453.3 | parallel | parallel | yes |
| mm | program 14 | 19621141.3 | 1639768.4 | 1288383.0 | 379907.3 | parallel | parallel | yes |
| mm | program 23 | 5.5 | 2.4 | 11.8 | 29.1 | parallel | serial | no |
| cg | program 10 | 191098.4 | 15939.2 | 113971.1 | 20785.1 | parallel | parallel | yes |
| cg | program 21 | 23.4 | 3.9 | 5.3 | 7.8 | parallel | serial | no |
| cg | program 26 | 147900.3 | 12336.5 | 19082.1 | 6902.1 | parallel | parallel | yes |
| cg | program 34 | 23.4 | 3.9 | 5.2 | 8.5 | parallel | serial | no |
| cg | program 38 | 77.6 | 8.4 | 5.5 | 4.8 | parallel | parallel | yes |
| cg | program 46 | 29.6 | 4.1 | 2.2 | 3.7 | parallel | serial | no |
| cg | program 51 | 13.6 | 3.1 | 4.8 | 3.8 | parallel | parallel | yes |

Verdict right for 12 of 21 candidate loops at P=12.

<!-- notes -->

## Notes (2026-10-15)

Run conditions: the desktop was not fully idle. Another job,
`claude-transcript-archive`, kept one core busy throughout (load
average 2–3.5), so the P=12 column, which needs every hardware thread,
is pessimistic. The P ≤ 6 columns agree with an earlier idle run of the
same harness to within a few percent.

1. **mandel line 29 (criterion 4): not faster in parallel.** The
   summing loop over 1800 rows takes 2.4 µs serially and 11.8 µs on 4
   threads (814 µs at P=12, with a thread competing with the other
   job). The prediction (4.0 µs serial, 1.9 µs parallel) assumed the
   table's fork/join cost, `overhead(fork_join, 4, 3720)` × 2.46e-10 s
   = 0.92 µs. That is the cost of back-to-back regions with the
   threads still spinning, which is what the calibration times. Here
   the region follows a serial stretch, the threads have gone to sleep,
   and waking them costs about ten times as much.

2. **Verdicts: 12 of 21 right at P=4 and at P=12.** Every candidate
   loop was predicted parallel. All the large loops (actual serial time
   above 1 ms) are faster in parallel, as predicted. All nine wrong
   verdicts at P=4 are small loops (2–70 µs serial) whose isolated
   parallel region costs more than the loop: mandel 29, linear 34,
   nbody 9, 42 and 53, cg 21, 34, 38 and 46 (at P=12, mm 23 joins them
   and cg 38 leaves, both within a microsecond). nbody line 9 is the program's first
   loop, so its parallel time (199 µs at P=4) also includes creating
   the OpenMP thread pool.

3. **SMT.** The 5600G has 6 cores with 2 hardware threads each, and the
   bench binds one thread per core while there are cores left. Compute-
   bound programs scale almost linearly to 6 threads (pi 5.80, nbody
   5.38, mm 4.92 at P=6), then drop at 7 and 8 (pi 3.45 and 3.90, mm
   1.89 and 2.18): one core runs two threads, and with a static
   schedule the whole loop waits for it. P=12 recovers partly (pi
   5.71). The cost model treats all 12 hardware threads as cores, so it
   predicts 7–12 throughout.

4. **Memory bandwidth.** linear and cg at n = 5000 (a 200 MB matrix)
   flatten early: 2.4 at P=4 and about 2.7 beyond. Their large loops
   (linear 10 and 21, cg 10 and 26) still gain 2.5–3.6x at P=4. mandel
   is limited by a different effect, load imbalance under the static
   schedule: its expensive rows are in the middle of the image, so P=3
   (1.42) is slower than P=2 (1.97).

5. **Absolute times.** The model's serial times are high by a large
   factor for loops of cheap operations: pi line 9 is predicted at
   16.3 s and takes 2.2 s (7.4x); mm line 14 19.6 s against 1.29 s
   (15x); linear 21 148 ms against 19 ms. It costs each operation's
   latency in isolation, while the CPU overlaps independent operations
   and gcc keeps values in registers. Where the work is dominated by
   long dependency chains it is close: mandel line 8, 1.21 s predicted
   against 1.13 s. The ratios that decide verdicts are much closer than
   the absolute times: the large loops are predicted at 4.0x on 4
   threads and measured at 3.69x (mm 14), 3.96x (pi 9) and 2.05x
   (mandel 8, load imbalance).

6. **montepi is faster parallel even on one thread** (1.66 at P=1, and
   6.34x for its loop at P=4). In the serial build x, y and hits are
   file-scope statics stored to memory every iteration; in the parallel
   build they are private copies or a reduction variable inside the
   outlined loop function, which gcc keeps in registers.

7. **For Phase 4 and later.** Small loops dominate the wrong verdicts.
   The cost model needs a fork/join cost measured for isolated regions
   (or a threshold of serial work below which a loop stays serial).
   Replicated SPMD regions, which keep the threads inside one region
   across the outer serial loop, should remove most of that overhead
   for linear and cg.
