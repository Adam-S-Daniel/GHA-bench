import test from 'node:test';
import assert from 'node:assert';
import { generateMatrix } from '../src/index.js';

test('should generate a simple matrix from basic OS config', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18', '20']
  };

  const result = generateMatrix(config);

  assert.strictEqual(result.include.length, 4, 'Should generate 4 combinations');
  assert.deepStrictEqual(
    result.include.map(row => [row.os, row.node_version]),
    [
      ['ubuntu-latest', '18'],
      ['ubuntu-latest', '20'],
      ['macos-latest', '18'],
      ['macos-latest', '20']
    ],
    'Should have correct combinations'
  );
});

test('should handle single-value configs', () => {
  const config = {
    os: ['ubuntu-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config);

  assert.strictEqual(result.include.length, 1);
  assert.deepStrictEqual(result.include[0], {
    os: 'ubuntu-latest',
    node_version: '18'
  });
});

test('should handle empty config', () => {
  const config = {};

  const result = generateMatrix(config);

  assert.strictEqual(result.include.length, 0);
});

test('should reject matrix exceeding max size', () => {
  const config = {
    os: Array.from({ length: 10 }, (_, i) => `os-${i}`),
    node_version: Array.from({ length: 10 }, (_, i) => `v${i}`),
    arch: Array.from({ length: 10 }, (_, i) => `arch-${i}`)
  };

  assert.throws(
    () => generateMatrix(config, { maxSize: 100 }),
    /Matrix size 1000 exceeds maximum/,
    'Should throw when matrix exceeds max size'
  );
});

test('should support max-parallel limit', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18', '20']
  };

  const result = generateMatrix(config, { maxParallel: 2 });

  assert.deepStrictEqual(result.max_parallel, 2);
});

test('should support fail-fast configuration', () => {
  const config = {
    os: ['ubuntu-latest'],
    node_version: ['18']
  };

  const result = generateMatrix(config, { failFast: false });

  assert.deepStrictEqual(result.fail_fast, false);
});

test('should support include rules', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18']
  };

  const include = [
    { os: 'windows-latest', node_version: '20' }
  ];

  const result = generateMatrix(config, { include });

  assert.strictEqual(result.include.length, 3);
  assert(
    result.include.some(row => row.os === 'windows-latest' && row.node_version === '20'),
    'Should include the extra configuration'
  );
});

test('should support exclude rules', () => {
  const config = {
    os: ['ubuntu-latest', 'macos-latest'],
    node_version: ['18', '20']
  };

  const exclude = [
    { os: 'macos-latest', node_version: '18' }
  ];

  const result = generateMatrix(config, { exclude });

  assert.strictEqual(result.include.length, 3);
  assert(
    !result.include.some(row => row.os === 'macos-latest' && row.node_version === '18'),
    'Should exclude the specified configuration'
  );
});
