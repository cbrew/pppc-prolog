program subscript;
{ a is written through a non-index subscript: must stay serial }
const n = 500;
var a: array[1..1000] of integer;
    i, s: integer;
begin
  a := 0;
  for i := 1 to n do
    a[2 * i] := i;
  s := 0;
  for i := 1 to 1000 do
    s := s + a[i];
  writeln('s = ', s)
end.
