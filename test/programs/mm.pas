program mm;
{ matrix multiply, 140 x 140 as in the paper }
const n = 140;
var a, b, c: array[1..n, 1..n] of real;
    i, j, k: integer;
    s, trace: real;
begin
  for i := 1 to n do
    for j := 1 to n do
    begin
      a[i, j] := (i + j) / n;
      b[i, j] := (i + 2 * j) / n
    end;
  for i := 1 to n do
    for j := 1 to n do
    begin
      s := 0;
      for k := 1 to n do
        s := s + a[i, k] * b[k, j];
      c[i, j] := s
    end;
  trace := 0;
  for i := 1 to n do
    trace := trace + c[i, i];
  writeln('trace = ', trace)
end.
