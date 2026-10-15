/*  Zero-overhead cost table for the end-to-end tests: every operation
    costs 1 and parallel regions cost nothing, so every eligible loop of
    two or more iterations is parallelized. This keeps the parallel code
    of every test program built and run, whatever the real table decides. */

cost_op2(+, integer, integer, 1).
cost_op2(-, integer, integer, 1).
cost_op2(*, integer, integer, 1).
cost_op2(div, integer, integer, 1).
cost_op2(mod, integer, integer, 1).
cost_op2(min, integer, integer, 1).
cost_op2(max, integer, integer, 1).
cost_op2(=, integer, integer, 1).
cost_op2(<>, integer, integer, 1).
cost_op2(<, integer, integer, 1).
cost_op2(<=, integer, integer, 1).
cost_op2(>, integer, integer, 1).
cost_op2(>=, integer, integer, 1).
cost_op2(+, real, real, 1).
cost_op2(-, real, real, 1).
cost_op2(*, real, real, 1).
cost_op2(/, real, real, 1).
cost_op2(min, real, real, 1).
cost_op2(max, real, real, 1).
cost_op2(=, real, real, 1).
cost_op2(<>, real, real, 1).
cost_op2(<, real, real, 1).
cost_op2(<=, real, real, 1).
cost_op2(>, real, real, 1).
cost_op2(>=, real, real, 1).
cost_op2(and, boolean, boolean, 1).
cost_op2(or, boolean, boolean, 1).
cost_op2(=, boolean, boolean, 1).
cost_op2(<>, boolean, boolean, 1).
cost_op1(-, integer, 1).
cost_op1(-, real, 1).
cost_op1(not, boolean, 1).
cost_func(abs, 1).
cost_func(sqr, 1).
cost_func(sqrt, 1).
cost_func(sin, 1).
cost_func(cos, 1).
cost_func(exp, 1).
cost_func(ln, 1).
cost_func(trunc, 1).
cost_func(round, 1).
cost_func(odd, 1).
cost_func(random, 1).
cost(index, 1).
cost(store, 1).
cost(loop, 1).
cost(if, 1).
cost(call, 1).
cost(param, 1).
cost(itor, 1).
cost(write_item, 1).
default_trips(25).
unit_seconds(1.0e-9).
overhead(fork_join, 1, 0).
overhead(reduction, 1, 0).
