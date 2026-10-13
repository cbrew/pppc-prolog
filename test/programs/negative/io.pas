program io;
{ output inside the loop: must stay serial to keep the order }
const n = 5;
var i: integer;
begin
  for i := 1 to n do
    writeln('i = ', i)
end.
