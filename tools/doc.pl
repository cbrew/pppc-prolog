/*  Generate HTML documentation from the pldoc comments in prolog/.
    Usage (from the project root): swipl --no-packs -p library=prolog tools/doc.pl
    Output: doc/<file>.html, one page per source file.               */

:- use_module(library(pldoc)).
:- doc_collect(true).
:- use_module(library(pppc)).
:- use_module(library(doc_files)).
:- use_module(library(apply)).

:- initialization(main, main).

main :-
    expand_file_name('prolog/pppc/*.pl', Passes),
    maplist(ensure_loaded, Passes),     % e.g. calibrate.pl, not loaded by pppc
    maplist([F]>>doc_save(F, [doc_root(doc)]), ['prolog/pppc.pl'|Passes]).
