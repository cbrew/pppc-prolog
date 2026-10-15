/*  Problem sizes for `make bench` (pppc_bench): size(Program, Overrides),
    Overrides the --const values for test/programs/Program.pas. Chosen
    so the serial run takes 1-3 s on the development machine, except
    linear and cg, whose solvers converge in a few iterations at any
    size (about 0.2 s at n = 5000). */

size(pi,      [n=2000000000]).
size(montepi, [n=300000000]).
size(mandel,  [nx=2400, ny=1800]).
size(linear,  [n=5000]).
size(nbody,   [n=1500]).
size(mm,      [n=1400]).
size(cg,      [n=5000]).
