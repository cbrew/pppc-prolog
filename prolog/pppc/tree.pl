:- module(pppc_tree,
          [ node_line/2,                % +Node, -Line
            expr_vars/2,                % +Expr, -Vars
            target_base/3,              % +Target, -Name, -Whole
            target_uses/2,              % +Target, -Vars
            has_user_call/1,            % +Node
            var_node/2                  % ?Node, ?Name
          ]).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).

/** <module> Typed tree utilities

Small queries over typed tree nodes (spec section 5.3) shared by the
parallelizer passes.
*/

%!  node_line(+Node, -Line) is det.
node_line(Node, L) :- arg(1, Node, L).

%!  var_node(?Node, ?Name) is semidet.
%
%   Node is a reference to the variable Name.
var_node(id(_, [N], _), N).
var_node(vparam(_, [N], _), N).
var_node(fresult(_, [N], _), N).

%!  expr_vars(+Expr, -Vars:ordset) is det.
%
%   Vars is the set of variable names occurring anywhere in Expr,
%   including subscripts and the bases of indexed or field references.
expr_vars(E, Vars) :-
    findall(N, (sub_term(T, E), compound(T), var_node(T, N)), Ns),
    sort(Ns, Vars).

%!  target_base(+Target, -Name, -Whole:boolean) is det.
%
%   Name is the variable assigned by Target. Whole is `true` if Target
%   is the entire variable (a killing definition) and `false` if it
%   is an element or field (a non-killing definition).
target_base(T, N, true) :- var_node(T, N), !.
target_base(index(_, [A, _], _), N, false) :- target_base(A, N, _).
target_base(field(_, [R, _], _), N, false) :- target_base(R, N, _).

%!  target_uses(+Target, -Vars:ordset) is det.
%
%   Variables read in order to locate Target, i.e. those in its
%   subscripts.
target_uses(T, []) :- var_node(T, _), !.
target_uses(index(_, [A, I], _), Vs) :-
    target_uses(A, V1), expr_vars(I, V2), ord_union(V1, V2, Vs).
target_uses(field(_, [R, _], _), Vs) :- target_uses(R, Vs).

%!  has_user_call(+Node) is semidet.
%
%   Node contains a call of a user procedure or function.
has_user_call(Node) :-
    sub_term(T, Node), compound(T),
    ( T = fcall(_, _, _) ; T = pcall(_, _, _) ), !.
