program alias;
{ x is a itself: reading x while writing a must stay serial }
const n = 100000;
type vec = array[1..n] of integer;
var a: vec;
    i: integer;

procedure rev(var x: vec);
var k: integer;
begin
  for k := 1 to n do
    a[k] := x[n + 1 - k]
end;

begin
  for i := 1 to n do
    a[i] := i;
  rev(a);
  writeln(a[1], ' ', a[n div 2 + 1], ' ', a[n])
end.
