.pragma library

/**
 * RTK coordinate correction maths.
 *
 * Single point correction is a pure translation. Multi point correction is a
 * 2D similarity (four parameter) transformation solved by least squares:
 *
 *   X = tx + a * x - b * y
 *   Y = ty + b * x + a * y
 *
 * with a = k * cos(theta) and b = k * sin(theta).
 *
 * All coordinates are expressed in the project CRS. Heights are metres.
 */

function isNumber(value) {
  return value !== null && value !== undefined && value !== "" && isFinite(Number(value));
}

function toNumber(value, fallback) {
  return isNumber(value) ? Number(value) : fallback;
}

/**
 * Validates and normalises a control point list. Returns { ok, error, points }.
 * error is one of "incomplete" or "notenough".
 */
function prepareControlPoints(points) {
  if (!points || points.length === undefined) {
    return {
      ok: false,
      error: "notenough",
      points: []
    };
  }

  const prepared = [];
  for (let i = 0; i < points.length; i++) {
    const point = points[i];
    if (!point || !isNumber(point.mx) || !isNumber(point.my) || !isNumber(point.kx) || !isNumber(point.ky)) {
      return {
        ok: false,
        error: "incomplete",
        index: i,
        points: []
      };
    }
    prepared.push({
      name: point.name !== undefined && point.name !== null ? String(point.name) : "",
      mx: Number(point.mx),
      my: Number(point.my),
      mh: toNumber(point.mh, NaN),
      kx: Number(point.kx),
      ky: Number(point.ky),
      kh: toNumber(point.kh, NaN)
    });
  }
  return {
    ok: true,
    error: "",
    index: -1,
    points: prepared
  };
}

/**
 * Solves a single point translation from one control point.
 * Returns { ok, error, mode, dx, dy, dz, count } or { ok: false, error }.
 */
function solveSinglePoint(points) {
  const prepared = prepareControlPoints(points);
  if (!prepared.ok) {
    return prepared;
  }
  if (prepared.points.length < 1) {
    return {
      ok: false,
      error: "notenough"
    };
  }

  const point = prepared.points[0];
  const solution = {
    ok: true,
    error: "",
    mode: 1,
    count: 1,
    dx: point.kx - point.mx,
    dy: point.ky - point.my,
    dz: isNumber(point.kh) && isNumber(point.mh) ? point.kh - point.mh : 0,
    rms: 0
  };
  return solution;
}

/**
 * Solves a four parameter similarity transformation by least squares.
 *
 * The coordinates are centred on their mean before solving, which keeps the
 * normal equations well conditioned even for large project coordinates. The
 * resulting system is diagonal, so no matrix inversion is required.
 *
 * Returns { ok, error, mode, a, b, tx, ty, dz, rms, count, scale, rotation }.
 */
function solveFourParameter(points) {
  const prepared = prepareControlPoints(points);
  if (!prepared.ok) {
    return prepared;
  }

  const list = prepared.points;
  if (list.length < 2) {
    return {
      ok: false,
      error: "notenough"
    };
  }

  let meanMx = 0;
  let meanMy = 0;
  let meanKx = 0;
  let meanKy = 0;
  for (let i = 0; i < list.length; i++) {
    meanMx += list[i].mx;
    meanMy += list[i].my;
    meanKx += list[i].kx;
    meanKy += list[i].ky;
  }
  meanMx /= list.length;
  meanMy /= list.length;
  meanKx /= list.length;
  meanKy /= list.length;

  // Centred sums for the two unknowns.
  let s = 0;
  let sa = 0;
  let sb = 0;
  let dzSum = 0;
  let dzCount = 0;
  for (let i = 0; i < list.length; i++) {
    const x = list[i].mx - meanMx;
    const y = list[i].my - meanMy;
    const xc = list[i].kx - meanKx;
    const yc = list[i].ky - meanKy;
    s += x * x + y * y;
    sa += x * xc + y * yc;
    sb += x * yc - y * xc;
    if (isNumber(list[i].kh) && isNumber(list[i].mh)) {
      dzSum += list[i].kh - list[i].mh;
      dzCount++;
    }
  }

  if (!(s > 0)) {
    // Every measured point is at the same location.
    return {
      ok: false,
      error: "degenerate"
    };
  }

  const a = sa / s;
  const b = sb / s;
  const tx = meanKx - (a * meanMx - b * meanMy);
  const ty = meanKy - (b * meanMx + a * meanMy);

  // Residual RMS over all control points.
  let sumSquared = 0;
  for (let i = 0; i < list.length; i++) {
    const px = tx + a * list[i].mx - b * list[i].my;
    const py = ty + b * list[i].mx + a * list[i].my;
    const dx = px - list[i].kx;
    const dy = py - list[i].ky;
    sumSquared += dx * dx + dy * dy;
  }
  const rms = Math.sqrt(sumSquared / list.length);

  // A similarity transformation is only meaningful when the measured control
  // points actually span a plane. Two coincident points give s > 0 only when
  // they really differ, but three collinear points still yield a valid (albeit
  // poorly determined) rotation, so report the spread as an indicator.
  const range = Math.sqrt(s / list.length);

  return {
    ok: true,
    error: "",
    mode: 2,
    count: list.length,
    a: a,
    b: b,
    tx: tx,
    ty: ty,
    dz: dzCount > 0 ? dzSum / dzCount : 0,
    rms: rms,
    scale: Math.sqrt(a * a + b * b),
    rotation: Math.atan2(b, a) * 180 / Math.PI,
    spread: range
  };
}

/**
 * Applies the configured correction to a point in the project CRS.
 *
 * @param x                 easting
 * @param y                 northing
 * @param z                 height (may be NaN)
 * @param correctionEnabled master switch
 * @param mode              selected mode (0 none, 1 single, 2 four parameter)
 * @param solution          solved parameters (may be an empty object)
 * @param elevationMode     0 follow planar, 1 independent
 * @param elevationOffset   independent height offset in metres
 */
function applyCorrection(x, y, z, correctionEnabled, mode, solution, elevationMode, elevationOffset) {
  const result = {
    x: x,
    y: y,
    z: z
  };
  if (!correctionEnabled) {
    return result;
  }

  let dz = 0;
  if (mode === 2 && solution && solution.mode === 2) {
    result.x = solution.tx + solution.a * x - solution.b * y;
    result.y = solution.ty + solution.b * x + solution.a * y;
    dz = isNumber(solution.dz) ? Number(solution.dz) : 0;
  } else if (mode === 1 && solution && solution.mode === 1) {
    result.x = x + Number(solution.dx);
    result.y = y + Number(solution.dy);
    dz = isNumber(solution.dz) ? Number(solution.dz) : 0;
  } else {
    // No valid planar solution: only an independent height offset can apply.
    dz = 0;
  }

  if (elevationMode === 1) {
    dz = isNumber(elevationOffset) ? Number(elevationOffset) : 0;
  }

  if (isNumber(z)) {
    result.z = Number(z) + dz;
  }
  return result;
}

/**
 * Arithmetic mean of the accepted samples. Each sample is expected to carry
 * latitude, longitude and elevation in WGS84.
 */
function meanSamples(samples) {
  if (!samples || samples.length === 0) {
    return null;
  }
  let latitude = 0;
  let longitude = 0;
  let elevation = 0;
  let elevationCount = 0;
  for (let i = 0; i < samples.length; i++) {
    latitude += Number(samples[i].latitude);
    longitude += Number(samples[i].longitude);
    if (isNumber(samples[i].elevation)) {
      elevation += Number(samples[i].elevation);
      elevationCount++;
    }
  }
  return {
    latitude: latitude / samples.length,
    longitude: longitude / samples.length,
    elevation: elevationCount > 0 ? elevation / elevationCount : NaN
  };
}
