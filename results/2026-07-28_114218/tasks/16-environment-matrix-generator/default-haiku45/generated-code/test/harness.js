#!/usr/bin/env node
// Test harness for running tests through GitHub Actions workflow
// This script is called by the workflow to validate matrix generation

import fs from 'fs';
import path from 'path';
import { generateMatrix } from '../src/index.js';

const testCases = [
  {
    name: 'simple-2x2-matrix',
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20']
    },
    options: {},
    expectedSize: 4
  },
  {
    name: 'with-excludes',
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20']
    },
    options: {
      exclude: [{ os: 'macos-latest', node_version: '18' }]
    },
    expectedSize: 3
  },
  {
    name: 'with-includes',
    config: {
      os: ['ubuntu-latest'],
      node_version: ['18']
    },
    options: {
      include: [{ os: 'windows-latest', node_version: '20' }]
    },
    expectedSize: 2
  },
  {
    name: 'with-max-parallel',
    config: {
      os: ['ubuntu-latest'],
      node_version: ['18', '20']
    },
    options: { maxParallel: 2 },
    expectedSize: 2,
    expectedMaxParallel: 2
  },
  {
    name: 'with-fail-fast-false',
    config: {
      os: ['ubuntu-latest'],
      node_version: ['18']
    },
    options: { failFast: false },
    expectedSize: 1,
    expectedFailFast: false
  },
  {
    name: 'three-dimensions',
    config: {
      os: ['ubuntu-latest', 'macos-latest'],
      node_version: ['18', '20'],
      arch: ['x64', 'arm64']
    },
    options: {},
    expectedSize: 8
  }
];

function runTests() {
  let passCount = 0;
  let failCount = 0;
  const results = [];

  console.log('Running matrix generation test harness...\n');

  for (const testCase of testCases) {
    try {
      const matrix = generateMatrix(testCase.config, testCase.options);

      // Check size
      if (matrix.include.length !== testCase.expectedSize) {
        throw new Error(
          `Expected ${testCase.expectedSize} combinations, got ${matrix.include.length}`
        );
      }

      // Check maxParallel if specified
      if (testCase.expectedMaxParallel !== undefined) {
        if (matrix.max_parallel !== testCase.expectedMaxParallel) {
          throw new Error(
            `Expected max_parallel=${testCase.expectedMaxParallel}, got ${matrix.max_parallel}`
          );
        }
      }

      // Check failFast if specified
      if (testCase.expectedFailFast !== undefined) {
        if (matrix.fail_fast !== testCase.expectedFailFast) {
          throw new Error(
            `Expected fail_fast=${testCase.expectedFailFast}, got ${matrix.fail_fast}`
          );
        }
      }

      console.log(`✓ ${testCase.name}`);
      results.push({
        name: testCase.name,
        status: 'PASS',
        output: JSON.stringify(matrix, null, 2)
      });
      passCount++;
    } catch (error) {
      console.log(`✗ ${testCase.name}: ${error.message}`);
      results.push({
        name: testCase.name,
        status: 'FAIL',
        error: error.message
      });
      failCount++;
    }
  }

  console.log(`\n${passCount} passed, ${failCount} failed\n`);

  return { passCount, failCount, results };
}

// Run tests and output results
const { passCount, failCount, results } = runTests();

// Output JSON results for workflow consumption
console.log('::group::Test Results JSON');
console.log(JSON.stringify(results, null, 2));
console.log('::endgroup::');

// Exit with proper code
process.exit(failCount > 0 ? 1 : 0);
