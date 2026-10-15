:- use_module(library(pppc)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(apply)).
:- use_module(library(lists)).

/*  Timed builds (option timing(true)): compiled with gcc and run. */

:- begin_tests(timing).

%   fill's loop (line 6) is a candidate run 3 times, from a loop that
%   calls fill and so is not a candidate; the i loop (line 12) is a
%   candidate run once, with the j loop nested in it.
program_text("program t;
var i, j, k: integer; s: real; a: array[1..10] of real;
procedure fill;
var m: integer;
begin
  for m := 1 to 10 do a[m] := m
end;
begin
  for k := 1 to 3 do
    fill;
  s := 0;
  for i := 1 to 10 do
    for j := 1 to 10 do
      s := s + a[j];
  writeln(s)
end.
").

source(File) :-
    program_text(Text),
    tmp_file_stream(text, File0, S0), close(S0),
    file_name_extension(File0, pas, File),
    setup_call_cleanup(open(File, write, S), write(S, Text), close(S)).

%   build(+Pas, +Options, -Exe, -C): compile with pppc and gcc.
build(Pas, Options, Exe, C) :-
    pppc_compile(Pas, Options, C),
    tmp_file_stream(text, Base, S0), close(S0),
    file_name_extension(Base, c, Src),
    setup_call_cleanup(open(Src, write, S), write(S, C), close(S)),
    atom_concat(Base, '_exe', Exe),
    process_create(path(gcc), ['-O2', '-Wall', '-Werror', '-fopenmp', Src, '-o', Exe, '-lm'],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Diag), close(E),
    process_wait(Pid, Status),
    assertion(Status-Diag == exit(0)-"").

run(Exe, Out, Err) :-
    process_create(Exe, [], [ stdout(pipe(O)), stderr(pipe(E)), process(Pid),
                              environment(['OMP_NUM_THREADS'=2]) ]),
    read_string(O, _, Out), read_string(E, _, Err),
    close(O), close(E),
    process_wait(Pid, Status),
    assertion(Status == exit(0)).

%   timing_keys(+Err, -Keys): Routine-Line-Count of each pppc_time line.
timing_keys(Err, Keys) :-
    split_string(Err, "\n", "", Lines0),
    exclude(==(""), Lines0, Lines),
    maplist(timing_key, Lines, Keys).

timing_key(Line, R-L-N) :-
    split_string(Line, " ", "", ["pppc_time", RS, LS, NS, SecsS]),
    atom_string(R, RS), number_string(L, LS), number_string(N, NS),
    number_string(Secs, SecsS), assertion(Secs >= 0).

test(timed_candidates, [forall(member(Mode, [[serial(true)], [], [prediction(false)]]))]) :-
    source(Pas),
    build(Pas, [timing(true)|Mode], Exe, C),
    aggregate_all(count, sub_string(C, _, _, _, "pppc_wtime() - pppc_t0"), Timers),
    assertion(Timers == 2),
    run(Exe, Out, Err),
    timing_keys(Err, Keys),
    assertion(Keys == [fill-6-3, program-12-1]),
    build(Pas, Mode, Plain, _),
    run(Plain, PlainOut, PlainErr),
    assertion(Out-PlainErr == PlainOut-"").

%   A candidate loop in a function, whose C has a result variable and a
%   return after the loop.
test(timed_function_loop) :-
    tmp_file_stream(text, File0, S0), close(S0),
    file_name_extension(File0, pas, Pas),
    setup_call_cleanup(open(Pas, write, S),
                       write(S, "program t;\nvar a: array[1..10] of real; x: real;\n\c
                                 function total(m: integer): real;\nvar i: integer; s: real;\n\c
                                 begin\n  s := 0;\n  for i := 1 to m do s := s + a[i];\n\c
                                 total := s\nend;\n\c
                                 begin x := total(10) + total(5); writeln(x) end.\n"),
                       close(S)),
    build(Pas, [timing(true), prediction(false)], Exe, _),
    run(Exe, Out, Err),
    assertion(Out == "0\n"),
    timing_keys(Err, Keys),
    assertion(Keys == [total-7-2]).

test(no_candidates_no_timing) :-
    tmp_file_stream(text, File0, S0), close(S0),
    file_name_extension(File0, pas, Pas),
    setup_call_cleanup(open(Pas, write, S),
                       write(S, "program t;\nbegin writeln(1) end.\n"), close(S)),
    pppc_compile(Pas, [timing(true)], C),
    pppc_compile(Pas, [], C0),
    assertion(C == C0).

:- end_tests(timing).
