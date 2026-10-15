:- use_module(library(pppc/bench)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(apply)).
:- use_module(library(lists)).

/*  The bench with canned results, except bench_smoke and the app test,
    which run pi at a tiny size and check only the shape of the output. */

:- begin_tests(bench).

test(parse_timings) :-
    parse_timings("pppc_time program 29 1 4.21e-06\npppc_time fill 6 3 0.000000e+00\n", Ts),
    assertion(Ts == [program-29-1-4.21e-06, fill-6-3-0.0]).

test(bad_timing, throws(pppc(bench(bad_timing("hello"))))) :-
    parse_timings("pppc_time program 29 1 4.21e-06\nhello\n", _).

test(shipped_sizes) :-
    read_sizes('bench/sizes.pl', Sizes),
    pairs_keys(Sizes, Names),
    assertion(Names == [pi, montepi, mandel, linear, nbody, mm, cg]).

test(duplicate_size, throws(pppc(bench(bad_sizes(_, duplicate(pi)))))) :-
    sizes_file("size(pi, [n=1]).\nsize(pi, [n=2]).\n", F),
    read_sizes(F, _).

test(bad_size, throws(pppc(bench(bad_sizes(_, size(pi, [n=x])))))) :-
    sizes_file("size(pi, [n=x]).\n", F),
    read_sizes(F, _).

test(missing_sizes_file, throws(pppc(bench(bad_sizes('no/such.pl', cannot_open))))) :-
    read_sizes('no/such.pl', _).

sizes_file(Text, File) :-
    tmp_file_stream(text, File, S), write(S, Text), close(S).

%   One benchmark at 1, 2 and 4 threads. Loop program 9 is predicted
%   and measured faster in parallel; program 12 is predicted serial but
%   measured faster in parallel; f 3 never ran.
canned(bench{date:'2026-10-15 12:00:00', cpu:'Test CPU', gcc:'16.2.0', cost:'t.pl',
             repeat:3, threads:[1, 2, 4],
             programs:[prog{name:pi, sizes:[n=100, eps=0.5], unit:1.0e-9,
                            speedups:[1-1, 2-2, 3-3, 4-7r2],
                            loops:[4-[ loop_time(program, 9, 2000, 600),
                                       loop_time(program, 12, 300, 500),
                                       loop_time(f, 3, 50, 900) ]],
                            runs:[ run(serial, 1, 2.0, [f-3-0-0.0, program-9-1-2.0e-6, program-12-4-1.2e-6]),
                                   run(serial, 1, 2.2, [f-3-0-0.0, program-9-1-2.2e-6, program-12-4-1.2e-6]),
                                   run(serial, 1, 1.8, [f-3-0-0.0, program-9-1-1.8e-6, program-12-4-1.2e-6]),
                                   run(parallel, 1, 2.0, []), run(parallel, 2, 1.0, []),
                                   run(parallel, 4, 0.5, []),
                                   run(all, 4, 0.6, [f-3-0-0.0, program-9-1-1.0e-6,
                                                     program-12-2-0.2e-6]) ]}]}).

test(speedup_rows) :-
    canned(R),
    speedup_rows(R, Rows),
    assertion(Rows == [row(pi, 2.0, [1-1.0, 2-2.0, 4-3.5], [1-1.0, 2-2.0, 4-4.0])]).

test(loop_rows) :-
    canned(R),
    loop_rows(R, 4, [loop(pi, program, 9, PS, PP, S, P), _, Never]),
    assertion(abs(PS - 2.0e-6) < 1.0e-15),
    assertion(abs(PP - 0.6e-6) < 1.0e-15),
    assertion(S-P == 2.0e-6-1.0e-6),
    assertion(Never = loop(pi, f, 3, _, _, none, none)).

test(markdown) :-
    canned(R),
    with_output_to(string(Text), write_results(current_output, R, "My notes.\n")),
    expected_markdown(Expected),
    assertion(Text == Expected).

expected_markdown(
"# PPPC benchmark results

- Date: 2026-10-15 12:00:00
- CPU: Test CPU
- gcc: 16.2.0 (-O2 -fopenmp)
- Cost table: t.pl
- Each time is the median of 3 runs

| Program | Sizes |
|---|---|
| pi | n=100, eps=0.5 |

## Speedups (Table 4.1)

| Program | | Serial (s) | P=1 | P=2 | P=4 |
|---|---|---:|---:|---:|---:|
| pi | Predicted | 2.00 | 1.00 | 2.00 | 3.50 |
| | Actual | | 1.00 | 2.00 | 4.00 |

## Loops at P=4

Time of one execution of each candidate loop, in µs. Actual parallel times are from the build with every candidate loop parallel.

| Program | Loop | Predicted serial | Predicted parallel | Actual serial | Actual parallel | Predicted | Actual | Agree |
|---|---|---:|---:|---:|---:|---|---|---|
| pi | program 9 | 2.0 | 0.6 | 2.0 | 1.0 | parallel | parallel | yes |
| pi | program 12 | 0.3 | 0.5 | 0.3 | 0.1 | serial | parallel | no |
| pi | f 3 | 0.1 | 0.9 | - | - | serial | - | - |

Verdict right for 1 of 2 candidate loops at P=4 (1 not run).

<!-- notes -->
My notes.
").

test(notes_kept) :-
    sizes_file("# Old results\n\n<!-- notes -->\nSMT flattens above 6.\n", F),
    notes(F, Notes),
    assertion(Notes == "SMT flattens above 6.\n").

%   The rest of the marker's line is not part of the notes, whatever it
%   holds (a CR from CRLF line endings, trailing spaces).
test(notes_kept_crlf) :-
    sizes_file("# Old\r\n\r\n<!-- notes -->\r\nKeep me.\r\n", F),
    notes(F, Notes),
    assertion(Notes == "Keep me.\r\n").

test(notes_marker_trailing_space) :-
    sizes_file("# Old\n<!-- notes -->  \nKeep me.\n", F),
    notes(F, Notes),
    assertion(Notes == "Keep me.\n").

test(no_notes) :-
    notes('no/such/results.md', N1),
    assertion(N1 == "\n"),
    sizes_file("# Old results\n", F),
    notes(F, N2),
    assertion(N2 == "\n").

tiny_sizes(File) :-
    sizes_file("size(pi, [n=100000]).\n", File).

test(bench_smoke) :-
    tiny_sizes(Sizes),
    bench([programs([pi]), threads([1, 2]), repeat(1), sizes(Sizes)], R),
    R.programs = [Prog],
    assertion(memberchk(run(serial, 1, _, [program-9-1-_]), Prog.runs)),
    assertion(memberchk(run(all, 2, _, [program-9-1-_]), Prog.runs)),
    with_output_to(string(Text), write_results(current_output, R, "\n")),
    assertion(sub_string(Text, _, _, _, "| pi | Predicted |")),
    assertion(sub_string(Text, _, _, _, "## Loops at P=2")).

test(app_keeps_notes) :-
    tiny_sizes(Sizes),
    sizes_file("old\n<!-- notes -->\nKeep me.\n", Out),
    process_create(path(swipl), [pppc_bench, '--program', pi, '--threads', '1,2',
                                 '--repeat', '1', '--sizes', Sizes, '-o', Out],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status-Err == exit(0)-""),
    read_file_to_string(Out, Text, []),
    assertion(sub_string(Text, _, _, _, "## Speedups (Table 4.1)")),
    assertion(sub_string(Text, _, _, 0, "<!-- notes -->\nKeep me.\n")).

%   Replacing a file that has text but no marker loses that text: say so.
test(app_warns_without_marker) :-
    tiny_sizes(Sizes),
    sizes_file("Hand-written results\n", Out),
    process_create(path(swipl), [pppc_bench, '--program', pi, '--threads', '1',
                                 '--repeat', '1', '--sizes', Sizes, '-o', Out],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status == exit(0)),
    assertion(sub_string(Err, _, _, _, "has no notes marker")).

test(app_bad_threads) :-
    process_create(path(swipl), [pppc_bench, '--threads', '1,x'],
                   [stderr(pipe(E)), process(Pid)]),
    read_string(E, _, Err), close(E),
    process_wait(Pid, Status),
    assertion(Status == exit(1)),
    assertion(sub_string(Err, _, _, _, "--threads needs positive integers")).

%   Thread counts are sorted and deduplicated; an empty list or a count
%   below 1 is an error from the API too, not only from the app.
test(threads_sorted_and_deduplicated) :-
    bench_options([threads([4, 2, 2])], Options),
    assertion(memberchk(threads([2, 4]), Options)).

test(threads_empty, throws(pppc(bench(bad_threads([]))))) :-
    bench_options([threads([])], _).

test(threads_not_positive, throws(pppc(bench(bad_threads([1, 0]))))) :-
    bench_options([threads([1, 0])], _).

:- end_tests(bench).
