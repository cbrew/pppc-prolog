:- module(pppc,
          [ pppc_compile/3,             % +File, +Options, -CText
            pppc_stage/3,               % +File, +Stage, -Result
            pppc_report/2               % +File, -Lines
          ]).
:- use_module(library(option)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(readutil)).
:- use_module(library(pppc/lexer)).
:- use_module(library(pppc/parser)).
:- use_module(library(pppc/semantic)).
:- use_module(library(pppc/transform)).
:- use_module(library(pppc/codegen)).
:- use_module(library(pppc/messages), []).

/** <module> PPPC: a portable parallelizing Pascal compiler

Reproduction of Gabber's PPPC (The Practice of Prolog, 1990, ch. 4)
targeting C + OpenMP. The passes are run in-process:

    lexer -> parser -> semantic -> [parallelizer] -> codegen

Errors in the source are thrown as pppc(Error) where Error is
no_source, syntax(Line, Expected, Found), bad_number(Line, Text) or
semantic_errors(List); a failing or
crashing pass throws pppc(internal(Pass, Reason)).
*/

%!  pppc_compile(+File, +Options, -CText:string) is det.
%
%   Compile the TAU-Pascal program in File to C. Options:
%
%     - serial(Bool)  if `true`, skip the parallelizer.
pppc_compile(File, Options, CText) :-
    front_end(File, Typed),
    (   option(serial(true), Options)
    ->  Program = Typed
    ;   pass(parallelizer, parallelize_program(Typed, Program, _))
    ),
    pass(codegen, generate_c(Program, CText)).

%!  pppc_stage(+File, +Stage, -Result) is det.
%
%   Run the compiler up to Stage and return its output. Stage is one
%   of tokens, parse, typed, labelled, reach, parallel. For labelled
%   and reach, Result is a list Routine-Value.
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
pppc_stage(File, parallel, Program) :- !,
    front_end(File, Typed),
    pass(parallelizer, parallelize_program(Typed, Program, _)).
pppc_stage(_, Stage, _) :-
    domain_error(pppc_stage, Stage).

%!  pppc_report(+File, -Lines:list(string)) is det.
%
%   One line per for loop:
%
%       Routine Line parallel Var:Class ...
%       Routine Line serial Reason ...
%       Routine Line nested OuterLine
pppc_report(File, Lines) :-
    analysis(File, Rs),
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
