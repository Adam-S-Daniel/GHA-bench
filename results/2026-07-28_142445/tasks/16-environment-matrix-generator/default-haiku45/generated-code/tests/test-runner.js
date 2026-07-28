import { MatrixGenerator } from '../src/generator.js';
import assert from 'assert';

// Simple test harness - each test is a function that throws on failure
const tests = [];
let passed = 0;
let failed = 0;

function test(name, fn) {
  tests.push({ name, fn });
}

async function runTests() {
  console.log('🧪 Running tests...\n');

  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`✅ ${name}`);
      passed++;
    } catch (error) {
      console.error(`❌ ${name}`);
      console.error(`   ${error.message}\n`);
      failed++;
    }
  }

  console.log(`\n📊 Results: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

// Test 1: Basic matrix generation with OS and Node versions
test('should generate basic matrix from config', () => {
  const config = {
    include: [
      { os: 'ubuntu-latest', node: '18' },
      { os: 'ubuntu-latest', node: '20' },
      { os: 'windows-latest', node: '18' }
    ]
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert(matrix.include, 'Matrix should have include property');
  assert.strictEqual(matrix.include.length, 3, 'Matrix should have 3 combinations');
  assert.deepStrictEqual(matrix.include[0], { os: 'ubuntu-latest', node: '18' });
  assert.deepStrictEqual(matrix.include[1], { os: 'ubuntu-latest', node: '20' });
  assert.deepStrictEqual(matrix.include[2], { os: 'windows-latest', node: '18' });
});

// Test 2: Generate matrix from product of OS and versions
test('should generate matrix from product of OS and versions', () => {
  const config = {
    os: ['ubuntu-latest', 'windows-latest'],
    node: ['18', '20']
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 4, 'Product should have 4 combinations');
  assert(matrix.include.some(m => m.os === 'ubuntu-latest' && m.node === '18'));
  assert(matrix.include.some(m => m.os === 'ubuntu-latest' && m.node === '20'));
  assert(matrix.include.some(m => m.os === 'windows-latest' && m.node === '18'));
  assert(matrix.include.some(m => m.os === 'windows-latest' && m.node === '20'));
});

// Test 3: Exclude combinations
test('should exclude specified combinations', () => {
  const config = {
    os: ['ubuntu-latest', 'windows-latest'],
    node: ['18', '20'],
    exclude: [
      { os: 'windows-latest', node: '18' }
    ]
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 3, 'Should have 3 combinations after exclude');
  assert(!matrix.include.some(m => m.os === 'windows-latest' && m.node === '18'));
});

// Test 4: Fail-fast configuration
test('should include fail-fast configuration', () => {
  const config = {
    os: ['ubuntu-latest'],
    node: ['18'],
    failFast: true
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.failFast, true, 'Matrix should have failFast property');
});

// Test 5: Max-parallel configuration
test('should include max-parallel configuration', () => {
  const config = {
    os: ['ubuntu-latest'],
    node: ['18'],
    maxParallel: 5
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.maxParallel, 5, 'Matrix should have maxParallel property');
});

// Test 6: Validate matrix size doesn't exceed maximum
test('should validate matrix size against maximum', () => {
  const config = {
    os: ['ubuntu-latest', 'windows-latest', 'macos-latest'],
    node: ['16', '18', '20', '21'],
    maxSize: 10
  };

  const generator = new MatrixGenerator();
  try {
    generator.generate(config);
    throw new Error('Should have thrown for exceeding max size');
  } catch (error) {
    assert(error.message.includes('exceeds maximum matrix size'),
      'Should throw error about exceeding max size');
  }
});

// Test 7: Feature flags in matrix
test('should support feature flags in matrix', () => {
  const config = {
    os: ['ubuntu-latest'],
    node: ['18'],
    features: ['feature-a', 'feature-b']
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 2, 'Should have 2 combinations with features');
  assert(matrix.include.some(m => m.features === 'feature-a'));
  assert(matrix.include.some(m => m.features === 'feature-b'));
});

// Test 8: Include and exclude together
test('should handle include and exclude together', () => {
  const config = {
    include: [
      { os: 'ubuntu-latest', node: '18' },
      { os: 'ubuntu-latest', node: '20' },
      { os: 'windows-latest', node: '18' },
      { os: 'windows-latest', node: '20' }
    ],
    exclude: [
      { os: 'windows-latest', node: '18' }
    ]
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 3, 'Should exclude one combination');
});

// Test 9: Empty config should handle gracefully
test('should handle empty include list', () => {
  const config = {
    include: []
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 0, 'Should have empty include list');
});

// Test 10: Complex multi-dimensional product
test('should generate product with three dimensions', () => {
  const config = {
    os: ['ubuntu-latest', 'windows-latest'],
    node: ['18', '20'],
    features: ['minimal', 'full']
  };

  const generator = new MatrixGenerator();
  const matrix = generator.generate(config);

  assert.strictEqual(matrix.include.length, 8, 'Should have 2*2*2=8 combinations');
});

// Run all tests
runTests().catch(error => {
  console.error('Test runner error:', error);
  process.exit(1);
});
