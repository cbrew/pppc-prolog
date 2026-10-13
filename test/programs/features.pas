program features;
{ exercises language features the benchmarks do not }
const n = 10;
type vec = array[1..n] of real;
     point = record x, y: real end;
var v, w: vec;
    pts: array[1..n] of point;
    origin: point;
    i, k, int, printf: integer;
    exp: real;
    done, flag: boolean;

procedure scale(var a: vec; f: real);
var i: integer;
begin
  for i := 1 to n do
    a[i] := a[i] * f
end;

function total(a: vec): real;
var i: integer; s: real;
begin
  s := 0;
  for i := 1 to n do
    s := s + a[i];
  total := s
end;

procedure swap(var p, q: integer);
var t: integer;
begin
  t := p; p := q; q := t
end;

begin
  for i := 1 to n do
    v[i] := i;
  w := v;
  scale(w, 0.5);
  writeln('total v = ', total(v), ' total w = ', total(w));
  pts := 0;
  origin := pts[1];
  for i := 1 to n do
  begin
    pts[i].x := i;
    pts[i].y := -i
  end;
  writeln('pts[3] = ', pts[3].x, ' ', pts[3].y, ' origin = ', origin.x);
  int := 3; printf := 4;
  swap(int, printf);
  writeln('int = ', int, ' printf = ', printf);
  exp := 0;
  for i := n downto 1 do
    exp := exp + sqr(i);
  writeln('exp = ', exp);
  k := 0;
  for i := 5 to 1 do
    k := k + 1;
  writeln('empty loop ran ', k, ' times');
  k := 3;
  for i := 1 to k do
    k := k + 1;
  writeln('k = ', k);
  i := 0; done := false;
  while not done do
  begin
    i := i + 1;
    done := (i * i > 50) or odd(i * 0)
  end;
  flag := (i mod 4 = 0) and (i div 2 > 1);
  writeln('i = ', i, ' flag = ', flag, ' min = ', 7 min 3, ' max = ', 2.5 max 1,
          ' trunc = ', trunc(-2.7), ' round = ', round(2.5), ' abs = ', abs(-4))
end.
