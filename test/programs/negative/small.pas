program small;
{ an eligible loop too short to pay for a parallel region }
var i: integer;
    s: real;
    a: array[1..10] of real;
begin
  for i := 1 to 10 do
    a[i] := i * 0.5;
  s := 0;
  for i := 1 to 10 do
    s := s + a[i];
  writeln('s = ', s)
end.
