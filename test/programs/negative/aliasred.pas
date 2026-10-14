program aliasred;
{ x is s itself: a reduction into s that reads x must stay serial }
var s: integer;

procedure p(var x: integer);
var k: integer;
begin
  for k := 1 to 20 do
    s := s + x
end;

begin
  s := 1;
  p(s);
  writeln('s = ', s)
end.
