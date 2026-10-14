/*  Unit cost table for test_predict.plt: every operation costs 1,
    fork/join costs 100 P and a reduction 10 P, measured for P = 1..4. */

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
overhead(fork_join, 1, 100).
overhead(fork_join, 2, 200).
overhead(fork_join, 3, 300).
overhead(fork_join, 4, 400).
overhead(reduction, 1, 10).
overhead(reduction, 2, 20).
overhead(reduction, 3, 30).
overhead(reduction, 4, 40).
