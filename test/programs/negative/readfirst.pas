program readfirst;
{ t is read before it is written in each iteration: must stay serial }
const n = 100;
var a: array[1..n] of integer;
    i, t: integer;
begin
  t := 7;
  for i := 1 to n do
  begin
    a[i] := t;
    t := i
  end;
  writeln('a[n] = ', a[n], ' t = ', t)
end.
