program montepi;
{ pi by Monte-Carlo integration }
const n = 20000000;
var i, hits: integer;
    x, y: real;
begin
  hits := 0;
  for i := 1 to n do
  begin
    x := random;
    y := random;
    if x * x + y * y <= 1.0 then
      hits := hits + 1
  end;
  writeln('pi = ', 4.0 * hits / n)
end.
