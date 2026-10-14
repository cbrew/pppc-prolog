program results;
{ function results in parallel loops, a side effect in a loop bound,
  and integer arithmetic beyond 32 bits }
const n = 100000; m = 1000;
type vec = array[1..m] of integer;
var calls, i, big: integer;
    a, v: vec;

function first(k: integer): integer;
begin
  calls := calls + 1;
  first := k
end;

function squares: vec;
var i: integer;
begin
  for i := 1 to m do
    squares[i] := i * i
end;

begin
  calls := 0;
  for i := first(1) to m do
    a[i] := i;
  v := squares;
  big := n * n;
  writeln('calls = ', calls, ' a[m] = ', a[m], ' v[m] = ', v[m]);
  writeln('big = ', big, ' mod = ', -7 mod 3, ' lit = ', 3)
end.
