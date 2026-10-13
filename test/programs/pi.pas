program pi;
{ pi by integrating 4/(1+x*x) over [0,1], midpoint rule }
const n = 20000000;
var i: integer;
    h, x, sum: real;
begin
  h := 1.0 / n;
  sum := 0;
  for i := 1 to n do
  begin
    x := h * (i - 0.5);
    sum := sum + 4.0 / (1.0 + x * x)
  end;
  writeln('pi = ', sum * h)
end.
