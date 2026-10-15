:- use_module(library(pppc/messages)).

:- begin_tests(messages).

render(Term, Text) :-
    phrase(prolog:message(Term), Lines),
    with_output_to(string(Text), print_message_lines(current_output, '', Lines)).

test(syntax) :-
    render(pppc('a.pas', syntax(3, then, id(x))), T),
    assertion(T == "a.pas:3: syntax error: expected then, found identifier `x'\n").

test(semantic) :-
    render(pppc('a.pas', semantic(7, assign_mismatch(real, boolean))), T),
    assertion(T == "a.pas:7: cannot assign boolean to real\n").

test(no_source) :-
    render(pppc('nope.pas', no_source), T),
    assertion(T == "nope.pas: cannot open source file\n").

test(every_semantic_error_has_a_message, [forall(error_term(E))]) :-
    assertion(phrase(prolog:message(pppc(f, semantic(1, E))), [_|_])).

error_term(E) :-
    member(E, [ redeclared(x), undeclared(x), not_constant(x), not_a_type(x), bad_bounds,
                nested_routine(p), bad_for_variable, not_a_procedure(p), not_a_function(f),
                not_a_variable(x), function_result_read(f), bad_zero_assignment,
                assign_mismatch(real, boolean), not_boolean, not_integer, not_writable,
                not_an_array, not_a_record, no_such_field(f), type_clash(-, boolean),
                type_clash(+, real, boolean), bad_arguments(sqrt), arg_count(p, 1, 2),
                arg_mismatch(integer, real), constant_error(z, zero_divisor),
                constant_error(z, float_overflow), bad_override(n, integer, 2.5) ]).

test(bad_number) :-
    render(pppc('a.pas', bad_number(4, '1e400')), T),
    assertion(T == "a.pas:4: number out of range: 1e400\n").

test(constant_error) :-
    render(pppc('a.pas', semantic(2, constant_error(z, zero_divisor))), T),
    assertion(T == "a.pas:2: cannot compute constant `z': division by zero\n").

test(cost_table_missing) :-
    render(pppc('a.pas', cost_table_missing('t.pl')), T),
    assertion(T == "t.pl: cannot open cost table\n").

test(bad_cost_table) :-
    render(pppc('a.pas', bad_cost_table('t.pl', missing(func(sqrt)))), T),
    assertion(T == "t.pl: cost table has no entry for func(sqrt)\n").

test(cost_table_syntax_error) :-
    render(pppc('a.pas', bad_cost_table('t.pl', syntax_error(2, cannot_start_term))), T),
    assertion(T == "t.pl:2: syntax error in cost table: cannot_start_term\n").

test(bad_threads) :-
    render(pppc('a.pas', bad_threads(0)), T),
    assertion(T == "a.pas: the number of threads must be a positive integer, not 0\n").

test(calibrate) :-
    render(pppc(pppc_calibrate, calibrate(no_compiler)), T),
    assertion(T == "pppc_calibrate: cannot run gcc\n").

test(bad_override) :-
    render(pppc('a.pas', semantic(2, bad_override(n, integer, 2.5))), T),
    assertion(T == "a.pas:2: cannot override constant `n' (integer) with 2.5\n").

test(unknown_const) :-
    render(pppc('a.pas', unknown_const(m)), T),
    assertion(T == "a.pas: no program constant `m'\n").

test(bad_const) :-
    render(pppc('a.pas', bad_const(n=x)), T),
    assertion(T == "a.pas: --const needs NAME=VALUE with a number, true or false, not n=x\n").

test(duplicate_const) :-
    render(pppc('a.pas', duplicate_const(n)), T),
    assertion(T == "a.pas: constant `n' is overridden more than once\n").

:- end_tests(messages).
