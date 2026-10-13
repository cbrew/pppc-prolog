program mandel;
{ Mandelbrot set: total escape iterations over a grid }
const nx = 800; ny = 600; maxit = 500;
var rows: array[0..ny - 1] of integer;
    ix, iy, k, total: integer;
    cr, ci, zr, zi, t: real;
begin
  for iy := 0 to ny - 1 do
  begin
    rows[iy] := 0;
    for ix := 0 to nx - 1 do
    begin
      cr := -2.0 + 3.0 * ix / nx;
      ci := -1.2 + 2.4 * iy / ny;
      zr := 0;
      zi := 0;
      k := 0;
      while (k < maxit) and (zr * zr + zi * zi < 4.0) do
      begin
        t := zr * zr - zi * zi + cr;
        zi := 2.0 * zr * zi + ci;
        zr := t;
        k := k + 1
      end;
      rows[iy] := rows[iy] + k
    end
  end;
  total := 0;
  for iy := 0 to ny - 1 do
    total := total + rows[iy];
  writeln('total iterations = ', total)
end.
