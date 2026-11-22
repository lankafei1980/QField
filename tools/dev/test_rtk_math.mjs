#!/usr/bin/env node
/**
 * Unit tests for the RTK correction maths and status mapping.
 *
 * The QML JavaScript libraries are plain scripts (they start with
 * `.pragma library`), so they are evaluated in a VM context after stripping
 * that directive.
 *
 * Run with: node --test tools/dev/test_rtk_math.mjs
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const here = path.dirname(fileURLToPath(import.meta.url));
const qmlDir = path.resolve(here, '../../src/gui/qml');

function loadLibrary(name) {
  const source = fs
    .readFileSync(path.join(qmlDir, name), 'utf8')
    .replace(/^\.pragma.*$/gm, '');
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: name });
  return sandbox;
}

const math = loadLibrary('QfRtkMath.js');
const status = loadLibrary('QfRtkStatus.js');

const close = (actual, expected, tolerance, message) => {
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${message}: ${actual} != ${expected} (tolerance ${tolerance})`
  );
};

test('four parameter: exact recovery from three points', () => {
  const a = 1.0002;
  const b = 0.0003;
  const tx = 500000;
  const ty = 4000000;
  const measured = [
    [100, 200],
    [300, 150],
    [250, 400],
  ];
  const points = measured.map(([mx, my], index) => ({
    name: `K${index}`,
    mx,
    my,
    kx: tx + a * mx - b * my,
    ky: ty + b * mx + a * my,
  }));

  const solution = math.solveFourParameter(points);
  assert.equal(solution.ok, true);
  close(solution.a, a, 1e-9, 'a');
  close(solution.b, b, 1e-9, 'b');
  close(solution.tx, tx, 1e-6, 'tx');
  close(solution.ty, ty, 1e-6, 'ty');
  close(solution.rms, 0, 1e-9, 'rms');
  assert.equal(solution.count, 3);
});

test('four parameter: least squares result matches the numpy reference', () => {
  // Reference generated with numpy (see the commit message for the code).
  const points = [
    { mx: 100, my: 200, kx: 1100.004, ky: 2200.023 },
    { mx: 300, my: 150, kx: 1300.0195, ky: 2150.033 },
    { mx: 250, my: 400, kx: 1250.007, ky: 2400.0535 },
    { mx: 120, my: 380, kx: 1119.994, ky: 2380.04 },
  ];
  // Known values from the numpy run.
  const expected = {
    a: 1.000084872298625,
    b: 0.000055959397511,
    tx: 1000.005595612312,
    ty: 2000.002626391617,
    rms: 0.002950253338393,
  };

  const solution = math.solveFourParameter(points);
  assert.equal(solution.ok, true);
  close(solution.a, expected.a, 1e-9, 'a');
  close(solution.b, expected.b, 1e-9, 'b');
  close(solution.tx, expected.tx, 1e-6, 'tx');
  close(solution.ty, expected.ty, 1e-6, 'ty');
  close(solution.rms, expected.rms, 1e-9, 'rms');
  close(solution.scale, Math.hypot(expected.a, expected.b), 1e-9, 'scale');
});

test('four parameter: two points are enough', () => {
  const points = [
    { mx: 0, my: 0, kx: 10, ky: 20 },
    { mx: 100, my: 0, kx: 110, ky: 20 },
  ];
  const solution = math.solveFourParameter(points);
  assert.equal(solution.ok, true);
  close(solution.a, 1, 1e-12, 'a');
  close(solution.b, 0, 1e-12, 'b');
  close(solution.tx, 10, 1e-9, 'tx');
  close(solution.ty, 20, 1e-9, 'ty');
});

test('four parameter: coincident points are rejected', () => {
  const points = [
    { mx: 10, my: 20, kx: 11, ky: 21 },
    { mx: 10, my: 20, kx: 12, ky: 22 },
  ];
  const solution = math.solveFourParameter(points);
  assert.equal(solution.ok, false);
  assert.equal(solution.error, 'degenerate');
});

test('control points: incomplete input and not enough points', () => {
  assert.equal(math.solveFourParameter([{ mx: 1, my: 2 }]).error, 'incomplete');
  assert.equal(math.solveFourParameter([{ mx: 1, my: 2, kx: 3, ky: 4 }]).error, 'notenough');
  assert.equal(math.solveSinglePoint([]).error, 'notenough');
});

test('single point: translation and height offset', () => {
  const solution = math.solveSinglePoint([
    { mx: 500, my: 600, mh: 100.5, kx: 500.12, ky: 599.88, kh: 100.0 },
  ]);
  assert.equal(solution.ok, true);
  assert.equal(solution.mode, 1);
  close(solution.dx, 0.12, 1e-9, 'dx');
  close(solution.dy, -0.12, 1e-9, 'dy');
  close(solution.dz, -0.5, 1e-9, 'dz');
});

test('four parameter: height follows the mean control point difference', () => {
  const solution = math.solveFourParameter([
    { mx: 0, my: 0, mh: 10, kx: 0, ky: 0, kh: 10.2 },
    { mx: 10, my: 0, mh: 20, kx: 10, ky: 0, kh: 20.4 },
    { mx: 0, my: 10, mh: 30, kx: 0, ky: 10, kh: 30.6 },
  ]);
  assert.equal(solution.ok, true);
  close(solution.dz, 0.4, 1e-9, 'dz');
});

test('apply correction: disabled, single point, four parameter and independent height', () => {
  const disabled = math.applyCorrection(10, 20, 30, false, 1, { mode: 1, dx: 1, dy: -1, dz: 1 }, 0, 0);
  assert.deepEqual({ x: disabled.x, y: disabled.y, z: disabled.z }, { x: 10, y: 20, z: 30 });

  const single = math.applyCorrection(10, 20, 30, true, 1, { mode: 1, dx: 1, dy: -2, dz: 0.5 }, 0, 0);
  close(single.x, 11, 1e-12, 'x');
  close(single.y, 18, 1e-12, 'y');
  close(single.z, 30.5, 1e-12, 'z');

  const identity = math.applyCorrection(10, 20, 30, true, 2, { mode: 2, a: 1, b: 0, tx: 0, ty: 0, dz: 0 }, 0, 0);
  close(identity.x, 10, 1e-12, 'x');
  close(identity.y, 20, 1e-12, 'y');
  close(identity.z, 30, 1e-12, 'z');

  const independent = math.applyCorrection(10, 20, 30, true, 1, { mode: 1, dx: 1, dy: 1, dz: 5 }, 1, -1.25);
  close(independent.z, 28.75, 1e-12, 'z');
});

test('mean samples', () => {
  const mean = math.meanSamples([
    { latitude: 30, longitude: 120, elevation: 10 },
    { latitude: 32, longitude: 122, elevation: 12 },
  ]);
  close(mean.latitude, 31, 1e-12, 'latitude');
  close(mean.longitude, 121, 1e-12, 'longitude');
  close(mean.elevation, 11, 1e-12, 'elevation');
  assert.equal(math.meanSamples([]), null);
});

test('GNSS status mapping', () => {
  assert.equal(status.gnssState(false, undefined, false), 'nofix');
  assert.equal(status.gnssState(true, undefined, false), 'acquiring');
  assert.equal(status.gnssState(true, { latitudeValid: false, quality: 4 }, false), 'acquiring');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 4 }, false), 'fixed');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 5 }, false), 'float');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 2 }, false), 'dgps');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 1 }, false), 'single');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 0 }, false), 'nofix');
  assert.equal(status.gnssState(true, { latitudeValid: true, quality: 4 }, true), 'capturing');

  assert.equal(status.gnssColorKey('fixed'), 'good');
  assert.equal(status.gnssColorKey('float'), 'warning');
  assert.equal(status.gnssColorKey('dgps'), 'warning');
  assert.equal(status.gnssColorKey('single'), 'error');
  assert.equal(status.gnssColorKey('acquiring'), 'error');
  assert.equal(status.gnssColorKey('nofix'), 'gray');
  assert.equal(status.gnssColorKey('capturing'), 'main');
});

test('correction status mapping', () => {
  assert.equal(status.correctionState(false, 1, { mode: 1 }, 0), 'none');
  assert.equal(status.correctionState(true, 1, { mode: 1 }, 0), 'single');
  assert.equal(status.correctionState(true, 2, { mode: 2 }, 0), 'multi');
  assert.equal(status.correctionState(true, 2, { mode: 1 }, 0), 'none');
  assert.equal(status.correctionState(true, 0, {}, 0.3), 'elevation');
  assert.equal(status.correctionState(true, 0, {}, 0), 'none');
});

test('sample validation', () => {
  const fixed = { latitudeValid: true, longitudeValid: true, quality: 4, haccValid: true, hacc: 0.01, vaccValid: true, vacc: 0.02 };
  assert.equal(status.sampleIsValid(fixed, true, 0.02, 0.04), true);
  assert.equal(status.sampleIsValid({ ...fixed, quality: 5 }, true, 0.02, 0.04), false);
  assert.equal(status.sampleIsValid({ ...fixed, quality: 5 }, false, 0.02, 0.04), true);
  assert.equal(status.sampleIsValid({ ...fixed, hacc: 0.05 }, false, 0.02, 0.04), false);
  assert.equal(status.sampleIsValid({ ...fixed, hacc: 0.05 }, false, 0, 0.04), true);
  assert.equal(status.sampleIsValid({ ...fixed, vaccValid: false }, false, 0.02, 0.04), false);
  assert.equal(status.sampleIsValid(fixed, true, 0, 0), true);
});

test('capture blocker diagnosis', () => {
  const info = { latitudeValid: true, quality: 4 };
  assert.equal(status.blockerKey(false, info, true, true, true, 2, true, true), 'noposition');
  assert.equal(status.blockerKey(true, info, false, true, true, 2, true, true), 'nodifferential');
  assert.equal(status.blockerKey(true, info, true, false, true, 2, true, true), 'ntripdisabled');
  assert.equal(status.blockerKey(true, info, true, true, false, 2, true, true), 'ntripinvalid');
  assert.equal(status.blockerKey(true, info, true, true, true, 0, true, true), 'ntripdisconnected');
  assert.equal(status.blockerKey(true, info, true, true, true, 1, true, true), 'ntripconnecting');
  assert.equal(status.blockerKey(true, info, true, true, true, 2, false, true), 'ntripstale');
  assert.equal(status.blockerKey(true, { latitudeValid: true, quality: 5 }, true, true, true, 2, true, true), 'notfixed');
  assert.equal(status.blockerKey(true, info, true, true, true, 2, true, false), '');
  assert.equal(status.blockerKey(true, info, false, false, false, 0, false, false), '');
});
