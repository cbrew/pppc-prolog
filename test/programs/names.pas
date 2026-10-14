program names;
{ Pascal names that clash with C keywords, library functions, predefined
  macros, each other after naive renaming, or the C entry point }
const n = 100;
var int, int_, y1, index, floor, linux, pppc_hi: integer;
    a: array[1..n] of integer;
    i: integer;

procedure main;
begin
  y1 := y1 + 1
end;

function pow(x: integer): integer;
begin
  pow := x * x
end;

begin
  int := 1;
  int_ := 2;
  y1 := 3;
  index := 4;
  floor := 5;
  linux := 6;
  pppc_hi := 7;
  main;
  for i := 1 to n do
    a[i] := i;
  writeln('int + int_ = ', int + int_);
  writeln('sum = ', y1 + index + floor + linux + pppc_hi, ' pow = ', pow(7), ' a[n] = ', a[n])
end.
