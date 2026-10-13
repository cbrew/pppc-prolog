program carried;
{ a[i] depends on a[i-1]: must stay serial }
const n = 1000;
var a: array[1..n] of integer;
    i: integer;
begin
  a[1] := 1;
  for i := 2 to n do
    a[i] := (a[i - 1] * 3 + 1) mod 1000;
  writeln('a[n] = ', a[n])
end.
