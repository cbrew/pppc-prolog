:- module(pppc,
          [ pppc_compile/3,             % +File, +Options, -CText
            pppc_stage/3,               % +File, +Stage, -Result
            pppc_report/2,              % +File, -Lines
            pppc_report/3,              % +File, +Options, -Lines
            pppc_predict/3              % +File, +Options, -Prediction
          ]).
:- use_module(library(option)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(readutil)).
:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/transform)).
:- use_module(library(pppc/cost)).
:- use_module(library(pppc/predict)).
:- use_module(library(pppc/codegen)).
:- use_module(library(pppc/messages), []).

/** <module> PPPC: a portable parallelizing Pascal compiler

Reproduction of Gabber's PPPC (The Practice of Prolog, 1990, ch. 4)
targeting C + OpenMP. The passes are run in-process:

    lexer -> parser -> semantic -> [parallelizer] -> codegen

The parallelizer decides with the run time prediction for a number of
threads, using a target cost table. Options accepted by pppc_compile/3,
pppc_report/3 and pppc_predict/3:

  - threads(N)  the number of threads to predict for (default 4);
  - cost(File)  the cost table (default: the shipped table);
  - prediction(Bool)  if `false`, parallelize every eligible loop
    without run time prediction, as Phase 1 did (pppc_compile/3 and
    pppc_report/3; threads and cost are then not used).

Errors in the source are thrown as pppc(Error) where Error is
no_source, syntax(Line, Expected, Found), bad_number(Line, Text) or
semantic_errors(List); errors in the options as bad_threads(N),
cost_table_missing(File) or bad_cost_table(File, Culprit); a failing or
crashing pass throws pppc(internal(Pass, Reason)).
*/

%!  pppc_compile(+File, +Options, -CText:string) is det.
%
%   Compile the TAU-Pascal program in File to C. Options, besides
%   threads(N) and cost(File):
%
%     - serial(Bool)  if `true`, skip the parallelizer.
pppc_compile(File, Options, CText) :-
    front_end(File, Typed),
    (   option(serial(true), Options)
    ->  Program = Typed
    ;   option(prediction(false), Options)
    ->  pass(parallelizer, parallelize_program(Typed, Program, _))
    ;   prediction_setup(Options, Table, N),
        pass(parallelizer, parallelize_program(Typed, Table, N, Program, _))
    ),
    pass(codegen, generate_c(Program, CText)).

%!  pppc_stage(+File, +Stage, -Result) is det.
%
%   Run the compiler up to Stage and return its output. Stage is one
%   of tokens, parse, typed, labelled, reach, predict, parallel. For
%   labelled and reach, Result is a list Routine-Value. predict and
%   parallel use the default options.
pppc_stage(File, tokens, Ts) :- !,
    read_source(File, Codes),
    pass(lexer, tokenize(Codes, Ts)).
pppc_stage(File, parse, Tree) :- !,
    pppc_stage(File, tokens, Ts),
    pass(parser, parse_program(Ts, Tree)).
pppc_stage(File, typed, Typed) :- !,
    front_end(File, Typed).
pppc_stage(File, labelled, Pairs) :- !,
    analysis(File, Rs),
    findall(N-L, member(routine(N, L, _, _), Rs), Pairs).
pppc_stage(File, reach, Pairs) :- !,
    analysis(File, Rs),
    findall(N-R, member(routine(N, _, _, R), Rs), Pairs).
pppc_stage(File, predict, Prediction) :- !,
    pppc_predict(File, [], Prediction).
pppc_stage(File, parallel, Program) :- !,
    front_end(File, Typed),
    prediction_setup([], Table, N),
    pass(parallelizer, parallelize_program(Typed, Table, N, Program, _)).
pppc_stage(_, Stage, _) :-
    domain_error(pppc_stage, Stage).

%!  pppc_report(+File, -Lines:list(string)) is det.
%!  pppc_report(+File, +Options, -Lines:list(string)) is det.
%
%   One line per for loop:
%
%       Routine Line parallel Var:Class ...
%       Routine Line serial Reason ...
%       Routine Line nested OuterLine
%
%   Reason unprofitable(Serial, Parallel) gives the predicted times.
pppc_report(File, Lines) :-
    pppc_report(File, [], Lines).

pppc_report(File, Options, Lines) :-
    (   option(prediction(false), Options)
    ->  front_end(File, Typed),
        pass(parallelizer, analyse_program(Typed, Rs))
    ;   decided(File, Options, Rs, _)
    ),
    findall(Line, ( member(routine(N, _, Loops, _), Rs),
                    member(Loop, Loops),
                    report_line(N, Loop, Line) ),
            Lines).

report_line(R, loop(_, L, parallel, Classes), Line) :-
    msort(Classes, Sorted),
    maplist([V-C, S]>>format(string(S), "~w:~w", [V, C]), Sorted, Ss),
    atomic_list_concat(Ss, ' ', Text),
    format(string(Line), "~w ~w parallel ~w", [R, L, Text]).
report_line(R, loop(_, L, serial(Reasons), _), Line) :-
    maplist([X, S]>>format(string(S), "~w", [X]), Reasons, Ss),
    atomic_list_concat(Ss, ' ', Text),
    format(string(Line), "~w ~w serial ~w", [R, L, Text]).
report_line(R, loop(_, L, nested(O), _), Line) :-
    format(string(Line), "~w ~w nested ~w", [R, L, O]).

%!  pppc_predict(+File, +Options, -Prediction) is det.
%
%   Prediction is prediction(Loops, Serial, Speedups) as described in
%   pppc_predict:decide/5, for threads(N) (default 4).
pppc_predict(File, Options, Prediction) :-
    decided(File, Options, _, Prediction).

                 /*******************************
                 *          PIPELINE            *
                 *******************************/

front_end(File, Typed) :-
    pppc_stage(File, parse, Tree),
    pass(semantic, check_program(Tree, Typed, Errors)),
    (   Errors == []
    ->  true
    ;   throw(pppc(semantic_errors(Errors)))
    ).

analysis(File, Routines) :-
    front_end(File, Typed),
    pass(parallelizer, analyse_program(Typed, Routines)).

decided(File, Options, Routines, Prediction) :-
    front_end(File, Typed),
    prediction_setup(Options, Table, N),
    pass(parallelizer, analyse_program(Typed, Routines0)),
    pass(predict, decide(Routines0, Table, N, Routines, Prediction)).

%   prediction_setup(+Options, -Table, -N): the cost table and number of
%   threads to predict with.
prediction_setup(Options, Table, N) :-
    option(threads(N), Options, 4),
    (   integer(N), N > 0
    ->  true
    ;   throw(pppc(bad_threads(N)))
    ),
    (   option(cost(File), Options)
    ->  true
    ;   default_cost_file(File)
    ),
    pass(cost, load_cost_table(File, Table)).

read_source(File, Codes) :-
    catch(read_file_to_codes(File, Codes, []),
          error(existence_error(source_sink, _), _),
          throw(pppc(no_source))).

%   pass(+Name, :Goal): run one compiler pass deterministically.
%   Source errors (pppc(_) exceptions) pass through; anything else is
%   an internal error of that pass.
:- meta_predicate pass(+, 0).

pass(Name, Goal) :-
    catch(Goal, E, internal_error(Name, E)),
    !.
pass(Name, _) :-
    throw(pppc(internal(Name, failed))).

internal_error(_, pppc(E)) :- !, throw(pppc(E)).
internal_error(Name, E) :- throw(pppc(internal(Name, E))).
