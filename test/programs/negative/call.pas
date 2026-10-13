program call;
{ the loop body calls a user function: must stay serial }
const n = 1000;
var i: integer;
    s: real;
function f(k: integer): real;
begin
  f := 1.0 / k
end;
begin
  s := 0;
  for i := 1 to n do
    s := s + f(i);
  writeln('s = ', s)
end.
