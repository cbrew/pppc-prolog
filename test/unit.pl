/*  Load every test/test_*.plt file and run the plunit tests.
    Usage (from the project root): swipl test/unit.pl          */

:- use_module(library(plunit)).
:- use_module(library(apply)).

:- initialization(main, main).

main :-
    expand_file_name('test/test_*.plt', Files),
    maplist([F]>>load_files(F, []), Files),
    (   run_tests
    ->  true
    ;   halt(1)
    ).
