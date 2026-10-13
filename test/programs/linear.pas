program linear;
{ Jacobi iteration for A x = b (paper section 4.3.5) }
const n = 250; eps = 1.0e-10;
var a: array[1..n, 1..n] of real;
    b: array[1..n] of real;
    x, new_x: array[1..n] of real;
    i, j, iter: integer;
    sum, error: real;
begin
  for i := 1 to n do
  begin
    for j := 1 to n do
      a[i, j] := 1.0 / (i + j);
    a[i, i] := n + 1.0;
    b[i] := i;
    x[i] := 0.0
  end;
  iter := 0;
  repeat
    error := 0;
    for i := 1 to n do
    begin
      sum := 0;
      for j := 1 to n do
        sum := sum + a[i, j] * x[j];
      new_x[i] := x[i] + (b[i] - sum) / a[i, i];
      error := error max abs(b[i] - sum)
    end;
    x := new_x;
    iter := iter + 1
  until error < eps;
  writeln('iterations = ', iter);
  sum := 0;
  for i := 1 to n do sum := sum + x[i];
  writeln('sum x = ', sum)
end.
