:- module(pppc_lexer,
          [ tokenize/2                  % +Codes, -Tokens
          ]).
:- use_module(library(dcg/basics)).

/** <module> TAU-Pascal lexical analyser

Turns a list of character codes into a list of tokens of the form
tok(Line, Kind), where Kind is one of

  - kw(Keyword)    reserved word, lower case
  - id(Name)       identifier, lower case (Pascal is case-insensitive)
  - int(N)         unsigned integer literal
  - real(R)        unsigned real literal
  - str(Codes)     quoted string literal
  - punct(P)       punctuation or operator symbol, e.g. ':=', '..'
  - eof            sentinel, always the last token

The line number is threaded through the grammar as an accumulator pair.
*/

%!  tokenize(+Codes:list(code), -Tokens:list) is det.
%
%   Tokenize Codes. Throws pppc(syntax(Line, Expected, Found)) on a
%   character that cannot start a token or an unterminated comment or
%   string.

tokenize(Codes, Tokens) :-
    phrase(tokens(1, Tokens), Codes).

tokens(L0, Ts) -->
    layout(L0, L1), !,
    tokens(L1, Ts).
tokens(L, [tok(L, T)|Ts]) -->
    token(L, T), !,
    tokens(L, Ts).
tokens(L, [tok(L, eof)]) -->
    eos, !.
tokens(L, _) -->
    [C],
    { char_code(Ch, C),
      throw(pppc(syntax(L, token, char(Ch))))
    }.

%   layout(+L0, -L)// skips one unit of white space or one comment.

layout(L0, L) --> "\n", !, { L is L0 + 1 }.
layout(L, L) --> [C], { code_type(C, space) }, !.
layout(L0, L) --> "{", !, comment(`}`, L0, L0, L).
layout(L0, L) --> "(*", !, comment(`*)`, L0, L0, L).

comment(End, _, L, L) --> End, !.
comment(End, S, L0, L) --> "\n", !, { L1 is L0 + 1 }, comment(End, S, L1, L).
comment(End, S, L0, L) --> [_], !, comment(End, S, L0, L).
comment(_, S, _, _) --> eos, { throw(pppc(syntax(S, end_of_comment, eof))) }.

token(_, T) -->
    [C], { code_type(C, alpha), C \== 0'_ }, !,
    word_codes(Cs),
    { atom_codes(A0, [C|Cs]),
      downcase_atom(A0, A),
      (   keyword(A)
      ->  T = kw(A)
      ;   T = id(A)
      )
    }.
token(_, T) -->
    digit(D0), digits(Ds),
    (   fraction(Fs)
    ->  optional_exponent(Es),
        { append([[D0|Ds], `.`, Fs, Es], Cs) },
        { number_codes(R, Cs), T = real(R) }
    ;   exponent(Es)
    ->  { append([[D0|Ds], `.0`, Es], Cs), number_codes(R, Cs), T = real(R) }
    ;   { number_codes(N, [D0|Ds]), T = int(N) }
    ).
token(L, str(Cs)) -->
    "'", !, string_body(L, Cs).
token(_, punct(P)) -->
    punct(P).

word_codes([C|Cs]) --> [C], { code_type(C, csym) }, !, word_codes(Cs).
word_codes([]) --> [].

fraction([D|Ds]) --> ".", digit(D), digits(Ds).

optional_exponent(Es) --> exponent(Es), !.
optional_exponent([]) --> [].

exponent([0'e|Es]) -->
    [E], { E == 0'e ; E == 0'E }, !,
    (   [S], { S == 0'+ ; S == 0'- }
    ->  { Es = [S|Ds] }
    ;   { Es = Ds }
    ),
    digit(D), digits(Ds0),
    { Ds = [D|Ds0] }.

string_body(_, [0''|Cs]) --> "''", !, string_body(_, Cs).
string_body(_, []) --> "'", !.
string_body(L, _) --> ( "\n" ; eos ), !, { throw(pppc(syntax(L, end_of_string, eol))) }.
string_body(L, [C|Cs]) --> [C], string_body(L, Cs).

punct(P) --> [C1, C2], { atom_codes(P, [C1, C2]), punct2(P) }, !.
punct(P) --> [C], { char_code(P, C), punct1(P) }.

punct2(':=').  punct2('<=').  punct2('>=').  punct2('<>').  punct2('..').

punct1(+). punct1(-). punct1(*). punct1(/). punct1(=). punct1(<). punct1(>).
punct1('('). punct1(')'). punct1('['). punct1(']'). punct1('.'). punct1(',').
punct1(;). punct1(:).

keyword(and).      keyword(array).    keyword(begin).   keyword(const).
keyword(div).      keyword(do).       keyword(downto).  keyword(else).
keyword(end).      keyword(false).    keyword(for).     keyword(function).
keyword(if).       keyword(max).      keyword(min).     keyword(mod).
keyword(not).      keyword(of).       keyword(or).      keyword(procedure).
keyword(program).  keyword(record).   keyword(repeat).  keyword(then).
keyword(to).       keyword(true).     keyword(type).    keyword(until).
keyword(var).      keyword(while).
