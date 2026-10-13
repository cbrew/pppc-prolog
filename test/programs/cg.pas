program cg;
{ conjugate gradient for a symmetric positive definite 250 x 250 system }
const n = 250; maxit = 1000; tol = 1.0e-20;
type vec = array[1..n] of real;
var a: array[1..n, 1..n] of real;
    b, x, r, p, q: vec;
    i, j, it: integer;
    rr, rr_new, pq, alpha, beta, s: real;
begin
  for i := 1 to n do
  begin
    for j := 1 to n do
      a[i, j] := 1.0 / (1 + abs(i - j));
    a[i, i] := a[i, i] + n;
    b[i] := 1.0;
    x[i] := 0;
    r[i] := b[i];
    p[i] := b[i]
  end;
  rr := 0;
  for i := 1 to n do
    rr := rr + r[i] * r[i];
  it := 0;
  while (it < maxit) and (rr > tol) do
  begin
    for i := 1 to n do
    begin
      s := 0;
      for j := 1 to n do
        s := s + a[i, j] * p[j];
      q[i] := s
    end;
    pq := 0;
    for i := 1 to n do
      pq := pq + p[i] * q[i];
    alpha := rr / pq;
    rr_new := 0;
    for i := 1 to n do
    begin
      x[i] := x[i] + alpha * p[i];
      r[i] := r[i] - alpha * q[i];
      rr_new := rr_new + r[i] * r[i]
    end;
    beta := rr_new / rr;
    rr := rr_new;
    for i := 1 to n do
      p[i] := r[i] + beta * p[i];
    it := it + 1
  end;
  s := 0;
  for i := 1 to n do
    s := s + x[i];
  writeln('iterations = ', it);
  writeln('sum x = ', s)
end.
