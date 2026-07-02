'use strict';

// Unit tests for the dependency license checker.
//
// TDD approach: each describe() block below was written RED-first — the test
// existed and failed before the corresponding function in license-checker.js
// was implemented. The mock license lookup is a plain object injected into
// checkLicenses(), so no network / registry access is ever needed in tests.

const { test, describe } = require('node:test');
const assert = require('node:assert');

const { parsePackageJson, parseRequirementsTxt, checkLicenses, formatReport, detectManifest, runChecker } = require('./license-checker');

// Mock license database used across tests — stands in for a real registry
// lookup (npm / PyPI). checkLicenses() receives it via dependency injection.
const MOCK_LICENSES = {
  express: 'MIT',
  lodash: 'MIT',
  'gpl-tool': 'GPL-3.0',
  requests: 'Apache-2.0',
};

const CONFIG = {
  allowedLicenses: ['MIT', 'Apache-2.0'],
  deniedLicenses: ['GPL-3.0'],
};

describe('parsePackageJson', () => {
  test('extracts names and versions from dependencies and devDependencies', () => {
    const manifest = JSON.stringify({
      name: 'fixture-app',
      dependencies: { express: '^4.18.2', lodash: '4.17.21' },
      devDependencies: { jest: '~29.7.0' },
    });
    const deps = parsePackageJson(manifest);
    assert.deepStrictEqual(deps, [
      { name: 'express', version: '4.18.2' },
      { name: 'lodash', version: '4.17.21' },
      { name: 'jest', version: '29.7.0' },
    ]);
  });

  test('returns empty list when manifest has no dependency sections', () => {
    assert.deepStrictEqual(parsePackageJson('{"name":"empty"}'), []);
  });

  test('throws a meaningful error on invalid JSON', () => {
    assert.throws(() => parsePackageJson('{not json'), /Invalid package\.json/);
  });
});

describe('parseRequirementsTxt', () => {
  test('extracts pinned and ranged requirements, skipping comments/blanks', () => {
    const content = [
      '# production deps',
      'requests==2.31.0',
      'flask >= 2.3.0',
      '',
      'left-pad==1.3.0  # inline comment',
    ].join('\n');
    assert.deepStrictEqual(parseRequirementsTxt(content), [
      { name: 'requests', version: '2.31.0' },
      { name: 'flask', version: '2.3.0' },
      { name: 'left-pad', version: '1.3.0' },
    ]);
  });

  test('uses "unspecified" when no version is given', () => {
    assert.deepStrictEqual(parseRequirementsTxt('numpy\n'), [
      { name: 'numpy', version: 'unspecified' },
    ]);
  });

  test('throws a meaningful error on an unparseable line', () => {
    assert.throws(
      () => parseRequirementsTxt('=== not a requirement'),
      /Invalid requirements\.txt line 1/
    );
  });
});

describe('checkLicenses', () => {
  test('classifies each dependency as approved, denied, or unknown', () => {
    const deps = [
      { name: 'express', version: '4.18.2' },
      { name: 'gpl-tool', version: '1.0.0' },
      { name: 'mystery-lib', version: '0.0.1' },
    ];
    const results = checkLicenses(deps, CONFIG, MOCK_LICENSES);
    assert.deepStrictEqual(results, [
      { name: 'express', version: '4.18.2', license: 'MIT', status: 'approved' },
      { name: 'gpl-tool', version: '1.0.0', license: 'GPL-3.0', status: 'denied' },
      { name: 'mystery-lib', version: '0.0.1', license: 'UNKNOWN', status: 'unknown' },
    ]);
  });

  test('a license on neither list is unknown even when the lookup resolves it', () => {
    const results = checkLicenses(
      [{ name: 'odd-lib', version: '1.0.0' }],
      CONFIG,
      { 'odd-lib': 'WTFPL' }
    );
    assert.strictEqual(results[0].license, 'WTFPL');
    assert.strictEqual(results[0].status, 'unknown');
  });

  test('deny-list wins if a license is on both lists', () => {
    const results = checkLicenses(
      [{ name: 'x', version: '1.0.0' }],
      { allowedLicenses: ['MIT'], deniedLicenses: ['MIT'] },
      { x: 'MIT' }
    );
    assert.strictEqual(results[0].status, 'denied');
  });

  test('license matching is case-insensitive', () => {
    const results = checkLicenses(
      [{ name: 'x', version: '1.0.0' }],
      { allowedLicenses: ['mit'], deniedLicenses: [] },
      { x: 'MIT' }
    );
    assert.strictEqual(results[0].status, 'approved');
  });
});

describe('formatReport', () => {
  test('renders one line per dependency plus a summary with exact counts', () => {
    const results = [
      { name: 'express', version: '4.18.2', license: 'MIT', status: 'approved' },
      { name: 'gpl-tool', version: '1.0.0', license: 'GPL-3.0', status: 'denied' },
      { name: 'mystery-lib', version: '0.0.1', license: 'UNKNOWN', status: 'unknown' },
    ];
    const report = formatReport(results);
    assert.match(report, /express@4\.18\.2 \| MIT \| APPROVED/);
    assert.match(report, /gpl-tool@1\.0\.0 \| GPL-3\.0 \| DENIED/);
    assert.match(report, /mystery-lib@0\.0\.1 \| UNKNOWN \| UNKNOWN/);
    assert.match(report, /Summary: 3 total, 1 approved, 1 denied, 1 unknown/);
  });

  test('reports zero counts for an empty dependency list', () => {
    assert.match(formatReport([]), /Summary: 0 total, 0 approved, 0 denied, 0 unknown/);
  });
});

describe('detectManifest', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');

  function tmpDirWith(files) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lc-test-'));
    for (const [name, content] of Object.entries(files)) {
      fs.writeFileSync(path.join(dir, name), content);
    }
    return dir;
  }

  test('finds package.json and reports its type', () => {
    const dir = tmpDirWith({ 'package.json': '{"dependencies":{"a":"1.0.0"}}' });
    const found = detectManifest(dir);
    assert.strictEqual(found.type, 'package.json');
    assert.strictEqual(path.basename(found.path), 'package.json');
  });

  test('finds requirements.txt when no package.json exists', () => {
    const dir = tmpDirWith({ 'requirements.txt': 'a==1.0.0\n' });
    assert.strictEqual(detectManifest(dir).type, 'requirements.txt');
  });

  test('throws a meaningful error when no manifest exists', () => {
    const dir = tmpDirWith({});
    assert.throws(() => detectManifest(dir), /No supported manifest/);
  });

  test('throws a meaningful error when the directory is missing', () => {
    assert.throws(() => detectManifest('/nonexistent/dir'), /not found or not a directory/);
  });
});

describe('runChecker (end-to-end with on-disk fixtures)', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');

  function tmpDirWith(files) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lc-e2e-'));
    for (const [name, content] of Object.entries(files)) {
      fs.writeFileSync(path.join(dir, name), content);
    }
    return dir;
  }

  const configJson = JSON.stringify({
    allowedLicenses: ['MIT', 'Apache-2.0'],
    deniedLicenses: ['GPL-3.0'],
  });
  const licensesJson = JSON.stringify(MOCK_LICENSES);

  test('produces a full report for a package.json project', () => {
    const dir = tmpDirWith({
      'package.json': JSON.stringify({ dependencies: { express: '^4.18.2', 'gpl-tool': '1.0.0' } }),
      'config.json': configJson,
      'licenses.json': licensesJson,
    });
    const { report, results } = runChecker({
      manifestDir: dir,
      configPath: path.join(dir, 'config.json'),
      licensesPath: path.join(dir, 'licenses.json'),
    });
    assert.match(report, /express@4\.18\.2 \| MIT \| APPROVED/);
    assert.match(report, /gpl-tool@1\.0\.0 \| GPL-3\.0 \| DENIED/);
    assert.strictEqual(results.length, 2);
  });

  test('fails with a meaningful error when the config file is missing', () => {
    const dir = tmpDirWith({ 'package.json': '{}', 'licenses.json': '{}' });
    assert.throws(
      () => runChecker({
        manifestDir: dir,
        configPath: path.join(dir, 'nope.json'),
        licensesPath: path.join(dir, 'licenses.json'),
      }),
      /Cannot read config file/
    );
  });

  test('fails with a meaningful error when the config is invalid JSON', () => {
    const dir = tmpDirWith({ 'package.json': '{}', 'config.json': '{oops', 'licenses.json': '{}' });
    assert.throws(
      () => runChecker({
        manifestDir: dir,
        configPath: path.join(dir, 'config.json'),
        licensesPath: path.join(dir, 'licenses.json'),
      }),
      /Invalid JSON in config file/
    );
  });
});
