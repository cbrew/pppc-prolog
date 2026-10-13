program nbody;
{ 100 bodies in 3 dimensions under gravitation, explicit Euler steps }
const n = 100; steps = 200; dt = 0.001; soft = 0.01;
type vec = array[1..n] of real;
var px, py, pz, vx, vy, vz, ax, ay, az, m: vec;
    i, j, s: integer;
    dx, dy, dz, d2, inv, fx, fy, fz, e: real;
begin
  for i := 1 to n do
  begin
    px[i] := cos(i);
    py[i] := sin(i);
    pz[i] := 0.1 * i / n;
    vx[i] := 0;
    vy[i] := 0;
    vz[i] := 0;
    m[i] := 1.0 / n
  end;
  for s := 1 to steps do
  begin
    for i := 1 to n do
    begin
      fx := 0;
      fy := 0;
      fz := 0;
      for j := 1 to n do
        if j <> i then
        begin
          dx := px[j] - px[i];
          dy := py[j] - py[i];
          dz := pz[j] - pz[i];
          d2 := dx * dx + dy * dy + dz * dz + soft;
          inv := m[j] / (d2 * sqrt(d2));
          fx := fx + dx * inv;
          fy := fy + dy * inv;
          fz := fz + dz * inv
        end;
      ax[i] := fx;
      ay[i] := fy;
      az[i] := fz
    end;
    for i := 1 to n do
    begin
      vx[i] := vx[i] + dt * ax[i];
      vy[i] := vy[i] + dt * ay[i];
      vz[i] := vz[i] + dt * az[i];
      px[i] := px[i] + dt * vx[i];
      py[i] := py[i] + dt * vy[i];
      pz[i] := pz[i] + dt * vz[i]
    end
  end;
  e := 0;
  for i := 1 to n do
    e := e + 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i]);
  writeln('kinetic energy = ', e)
end.
