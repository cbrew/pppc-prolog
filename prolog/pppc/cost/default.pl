/*  PPPC cost table, measured by pppc_calibrate

    Date:    2026-10-15 04:33:40
    CPU:     AMD Ryzen 5 5600G with Radeon Graphics
    gcc:     16.2.0 (-O2 -fopenmp)
    Options: [blocks(51),iterations(1000000),max_threads(12),repeat(5),reps(200)]

    Costs are in units of one integer addition.
*/

cost_op2(+, integer, integer, 1).
cost_op2(-, integer, integer, 1).
cost_op2(*, integer, integer, 3).
cost_op2(div, integer, integer, 9).
cost_op2(mod, integer, integer, 10).
cost_op2(min, integer, integer, 2).
cost_op2(max, integer, integer, 2).
cost_op2(=, integer, integer, 3).
cost_op2(<>, integer, integer, 3).
cost_op2(<, integer, integer, 3).
cost_op2(<=, integer, integer, 3).
cost_op2(>, integer, integer, 3).
cost_op2(>=, integer, integer, 3).
cost_op2(+, real, real, 3).
cost_op2(-, real, real, 3).
cost_op2(*, real, real, 3).
cost_op2(/, real, real, 13).
cost_op2(min, real, real, 1).
cost_op2(max, real, real, 1).
cost_op2(=, real, real, 1).
cost_op2(<>, real, real, 1).
cost_op2(<, real, real, 2).
cost_op2(<=, real, real, 2).
cost_op2(>, real, real, 2).
cost_op2(>=, real, real, 2).
cost_op2(and, boolean, boolean, 1).
cost_op2(or, boolean, boolean, 1).
cost_op2(=, boolean, boolean, 2).
cost_op2(<>, boolean, boolean, 1).
cost_op1(-, integer, 1).
cost_op1(-, real, 1).
cost_op1(not, boolean, 1).
cost_func(abs, 1).
cost_func(sqr, 1).
cost_func(sqrt, 8).
cost_func(sin, 30).
cost_func(cos, 27).
cost_func(exp, 17).
cost_func(ln, 14).
cost_func(trunc, 1).
cost_func(round, 11).
cost_func(odd, 1).
cost_func(random, 8).
cost(loop, 2).
cost(index, 5).
cost(itor, 1).
cost(store, 1).
cost(if, 1).
cost(call, 4).
cost(param, 1).
cost(write_item, 148).
default_trips(25).
unit_seconds(2.4648001997500007e-10).
overhead(fork_join, 1, 1906).
overhead(fork_join, 2, 3502).
overhead(fork_join, 3, 3637).
overhead(fork_join, 4, 3720).
overhead(fork_join, 5, 3871).
overhead(fork_join, 6, 4195).
overhead(fork_join, 7, 4777).
overhead(fork_join, 8, 4891).
overhead(fork_join, 9, 5096).
overhead(fork_join, 10, 5350).
overhead(fork_join, 11, 5846).
overhead(fork_join, 12, 6626).
overhead(reduction, 1, 1).
overhead(reduction, 2, 1).
overhead(reduction, 3, 1).
overhead(reduction, 4, 1).
overhead(reduction, 5, 1).
overhead(reduction, 6, 1).
overhead(reduction, 7, 1).
overhead(reduction, 8, 1).
overhead(reduction, 9, 20).
overhead(reduction, 10, 261).
overhead(reduction, 11, 826).
overhead(reduction, 12, 1238).
