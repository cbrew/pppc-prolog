:- use_module(library(pppc/lexer)).

:- begin_tests(lexer).

kinds(Text, Kinds) :-
    string_codes(Text, Codes),
    tokenize(Codes, Tokens),
    findall(K, member(tok(_, K), Tokens), Kinds).

test(keywords_and_ids_downcased) :-
    kinds("Program Foo; BEGIN End", Ks),
    assertion(Ks == [kw(program), id(foo), punct(;), kw(begin), kw(end), eof]).

test(numbers) :-
    kinds("42 3.5 1e3 2.5E-2", Ks),
    assertion(Ks == [int(42), real(3.5), real(1000.0), real(0.025), eof]).

test(range_is_not_real) :-
    kinds("1..N", Ks),
    assertion(Ks == [int(1), punct('..'), id(n), eof]).

test(two_char_punct) :-
    kinds("a:=b<=c<>d>=e", Ks),
    assertion(Ks == [id(a), punct(':='), id(b), punct('<='), id(c),
                     punct('<>'), id(d), punct('>='), id(e), eof]).

test(string_with_quote) :-
    kinds("'it''s'", Ks),
    assertion(Ks == [str(`it's`), eof]).

test(comments_and_lines) :-
    string_codes("a { x\n y }\n(* z *) b\nc", Codes),
    tokenize(Codes, Ts),
    assertion(Ts == [tok(1, id(a)), tok(3, id(b)), tok(4, id(c)), tok(4, eof)]).

test(bad_char, throws(pppc(syntax(2, token, char('?'))))) :-
    kinds("a\n?", _).

test(unterminated_comment, throws(pppc(syntax(1, end_of_comment, eof)))) :-
    kinds("{ abc", _).

%   A literal outside the range of a C double is a source error.
test(real_out_of_range, throws(pppc(bad_number(1, '1e400')))) :-
    kinds("x := 1e400", _).

:- end_tests(lexer).
