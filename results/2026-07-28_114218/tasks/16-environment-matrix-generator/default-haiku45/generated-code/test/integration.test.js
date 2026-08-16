import test from 'node:test';
import assert from 'node:assert';
import { generateMatrix } from '../src/index.js';
import { fixtures, expectedMatrices } from './fixtures.js';

test('Integration: simple 2x2 matrix', () => {
  const result = generateMatrix(fixtures.simple.config, fixtures.simple.options);
  assert.strictEqual(result.include.length, fixtures.simple.expectedSize);
  assert.deepStrictEqual(result.include, expectedMatrices.simple.include);
});

test('Integration: single-dimension matrix', () => {
  const result = generateMatrix(
    fixtures.singleDimension.config,
    fixtures.singleDimension.options
  );
  assert.strictEqual(result.include.length, fixtures.singleDimension.expectedSize);
  assert.deepStrictEqual(result.include, expectedMatrices.singleDimension.include);
});

test('Integration: three-dimensional matrix', () => {
  const result = generateMatrix(
    fixtures.threeDimensions.config,
    fixtures.threeDimensions.options
  );
  assert.strictEqual(result.include.length, fixtures.threeDimensions.expectedSize);
  assert.deepStrictEqual(result.include, expectedMatrices.threeDimensions.include);
});

test('Integration: matrix with excludes', () => {
  const result = generateMatrix(
    fixtures.withExcludes.config,
    fixtures.withExcludes.options
  );
  assert.strictEqual(result.include.length, fixtures.withExcludes.expectedSize);
  assert(!result.include.some(row =>
    row.os === 'macos-latest' && row.node_version === '18'
  ));
});

test('Integration: matrix with includes', () => {
  const result = generateMatrix(
    fixtures.withIncludes.config,
    fixtures.withIncludes.options
  );
  assert.strictEqual(result.include.length, fixtures.withIncludes.expectedSize);
  assert(result.include.some(row =>
    row.os === 'windows-latest' && row.node_version === '20'
  ));
  assert(result.include.some(row =>
    row.os === 'ubuntu-latest' && row.node_version === '22'
  ));
});

test('Integration: complex case with includes and excludes', () => {
  const result = generateMatrix(
    fixtures.complex.config,
    fixtures.complex.options
  );
  assert.strictEqual(result.include.length, fixtures.complex.expectedSize);
  assert(!result.include.some(row =>
    row.os === 'macos-latest' && row.node_version === '18'
  ));
  assert(result.include.some(row =>
    row.os === 'windows-latest' && row.node_version === '20'
  ));
});

test('Integration: max-parallel and fail-fast settings', () => {
  const config = {
    os: ['ubuntu-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config, {
    maxParallel: 3,
    failFast: false
  });

  assert.strictEqual(result.max_parallel, 3);
  assert.strictEqual(result.fail_fast, false);
});

test('Integration: large matrix at size limit', () => {
  const config = {
    os: Array.from({ length: 8 }, (_, i) => `os-${i}`),
    node_version: Array.from({ length: 8 }, (_, i) => `v${i}`),
    arch: Array.from({ length: 4 }, (_, i) => `arch-${i}`)
  };

  // 8 * 8 * 4 = 256 (at limit)
  const result = generateMatrix(config, { maxSize: 256 });
  assert.strictEqual(result.include.length, 256);
});

test('Integration: error on oversized matrix', () => {
  const config = {
    os: Array.from({ length: 8 }, (_, i) => `os-${i}`),
    node_version: Array.from({ length: 8 }, (_, i) => `v${i}`),
    arch: Array.from({ length: 4 }, (_, i) => `arch-${i}`)
  };

  // 8 * 8 * 4 = 256, exceeds 255 limit
  assert.throws(
    () => generateMatrix(config, { maxSize: 255 }),
    /Matrix size 256 exceeds maximum/
  );
});

test('Integration: multiple excludes', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest', 'windows-latest'],
    node_version: ['18', '20']
  };

  const result = generateMatrix(config, {
    exclude: [
      { os: 'macos-latest', node_version: '18' },
      { os: 'windows-latest', node_version: '20' }
    ]
  });

  assert.strictEqual(result.include.length, 4);
  assert(!result.include.some(row =>
    row.os === 'macos-latest' && row.node_version === '18'
  ));
  assert(!result.include.some(row =>
    row.os === 'windows-latest' && row.node_version === '20'
  ));
});

test('Integration: exclude non-existent combination', () => {
  const config = {
    os: ['ubuntu-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config, {
    exclude: [
      { os: 'macos-latest', node_version: '20' }
    ]
  });

  // Should not affect existing combinations
  assert.strictEqual(result.include.length, 1);
});

test('Integration: include duplicate (already exists in matrix)', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config, {
    include: [
      { os: 'ubuntu-latest', node_version: '18' }
    ]
  });

  // Should not add duplicate
  assert.strictEqual(result.include.length, 2);
});

test('Integration: custom fields in include', () => {
  const config = {
    os: ['ubuntu-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config, {
    include: [
      { os: 'special', node_version: '19', experimentalFlag: true }
    ]
  });

  assert.strictEqual(result.include.length, 2);
  const special = result.include.find(row => row.os === 'special');
  assert.deepStrictEqual(special, {
    os: 'special',
    node_version: '19',
    experimentalFlag: true
  });
});

test('Integration: JSON serialization round-trip', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18', '20']
  };

  const result1 = generateMatrix(config, { failFast: false });
  const json = JSON.stringify(result1);
  const result2 = JSON.parse(json);

  assert.deepStrictEqual(result1, result2);
});
