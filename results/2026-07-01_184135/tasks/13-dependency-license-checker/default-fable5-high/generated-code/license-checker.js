'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Dependency license compliance checker.
//
// Pipeline: parse manifest -> look up each dependency's license (injectable
// lookup table, mocked in tests) -> classify against an allow/deny config ->
// render a human-readable compliance report.

/**
 * Strip common semver range prefixes (^, ~, >=, etc.) so the report shows a
 * concrete version string.
 */
function normalizeVersion(range) {
  return String(range).replace(/^[\^~><=\s]+/, '').trim();
}

/**
 * Parse a package.json string into [{ name, version }].
 * Reads both "dependencies" and "devDependencies".
 */
function parsePackageJson(content) {
  let manifest;
  try {
    manifest = JSON.parse(content);
  } catch (err) {
    throw new Error(`Invalid package.json: ${err.message}`);
  }
  const deps = [];
  for (const section of ['dependencies', 'devDependencies']) {
    for (const [name, range] of Object.entries(manifest[section] || {})) {
      deps.push({ name, version: normalizeVersion(range) });
    }
  }
  return deps;
}

/**
 * Parse a requirements.txt string into [{ name, version }].
 * Supports "name==1.2.3", "name >= 1.2.3", bare "name" (version becomes
 * "unspecified"), full-line and inline comments.
 */
function parseRequirementsTxt(content) {
  const deps = [];
  const lines = String(content).split(/\r?\n/);
  lines.forEach((rawLine, idx) => {
    const line = rawLine.replace(/#.*$/, '').trim(); // drop comments
    if (!line) return;
    // name, then optional PEP 440-style operator + version
    const match = line.match(/^([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:(?:==|>=|<=|~=|!=|>|<)\s*([^\s,;]+))?/);
    if (!match || !match[1]) {
      throw new Error(`Invalid requirements.txt line ${idx + 1}: "${rawLine.trim()}"`);
    }
    deps.push({ name: match[1], version: match[2] || 'unspecified' });
  });
  return deps;
}

/**
 * Classify each dependency's license against the config.
 *
 * @param {Array<{name, version}>} deps
 * @param {{allowedLicenses: string[], deniedLicenses: string[]}} config
 * @param {Object<string,string>} licenseLookup  name -> SPDX id. In production
 *   this would be backed by a registry query; tests inject a mock table.
 * @returns {Array<{name, version, license, status}>}
 *   status: denied (deny-list, wins over allow) | approved (allow-list) |
 *   unknown (unresolvable or on neither list).
 */
function checkLicenses(deps, config, licenseLookup) {
  const lower = (list) => (list || []).map((l) => String(l).toLowerCase());
  const allowed = lower(config.allowedLicenses);
  const denied = lower(config.deniedLicenses);

  return deps.map(({ name, version }) => {
    const license = licenseLookup[name];
    let status = 'unknown';
    if (license !== undefined) {
      const id = license.toLowerCase();
      if (denied.includes(id)) status = 'denied';
      else if (allowed.includes(id)) status = 'approved';
    }
    return { name, version, license: license ?? 'UNKNOWN', status };
  });
}

/**
 * Render classification results as a plain-text compliance report:
 * one "name@version | license | STATUS" line per dependency, then a summary
 * line with exact counts (asserted verbatim by the CI test harness).
 */
function formatReport(results) {
  const count = (s) => results.filter((r) => r.status === s).length;
  const lines = ['Dependency License Compliance Report', '===================================='];
  for (const r of results) {
    lines.push(`${r.name}@${r.version} | ${r.license} | ${r.status.toUpperCase()}`);
  }
  lines.push(
    `Summary: ${results.length} total, ${count('approved')} approved, ` +
      `${count('denied')} denied, ${count('unknown')} unknown`
  );
  return lines.join('\n');
}

// Supported manifest types, in detection priority order, each mapped to its
// parser so callers never need to switch on type themselves.
const MANIFEST_PARSERS = {
  'package.json': parsePackageJson,
  'requirements.txt': parseRequirementsTxt,
};

/**
 * Find a supported dependency manifest inside `dir`.
 * Returns { path, type }; throws with a clear message if the directory or a
 * manifest can't be found.
 */
function detectManifest(dir) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    throw new Error(`Manifest directory not found or not a directory: ${dir}`);
  }
  for (const type of Object.keys(MANIFEST_PARSERS)) {
    const candidate = path.join(dir, type);
    if (fs.existsSync(candidate)) return { path: candidate, type };
  }
  throw new Error(
    `No supported manifest (${Object.keys(MANIFEST_PARSERS).join(', ')}) found in ${dir}`
  );
}

/** Read and parse a JSON file, failing with errors that name the file's role. */
function readJsonFile(filePath, role) {
  let raw;
  try {
    raw = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    throw new Error(`Cannot read ${role} file "${filePath}": ${err.message}`);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`Invalid JSON in ${role} file "${filePath}": ${err.message}`);
  }
}

/**
 * End-to-end run: detect + parse the manifest in `manifestDir`, load the
 * allow/deny config and the (mock) license database, classify, and render.
 * Returns { report, results, manifestType }.
 */
function runChecker({ manifestDir, configPath, licensesPath }) {
  const manifest = detectManifest(manifestDir);
  const parse = MANIFEST_PARSERS[manifest.type];
  const deps = parse(fs.readFileSync(manifest.path, 'utf8'));
  const config = readJsonFile(configPath, 'config');
  const licenses = readJsonFile(licensesPath, 'licenses');
  const results = checkLicenses(deps, config, licenses);
  return { report: formatReport(results), results, manifestType: manifest.type };
}

/**
 * CLI: node license-checker.js --manifest-dir DIR --config FILE --licenses FILE [--strict]
 * Prints the report to stdout. Exit codes: 0 = ran fine (report-only mode),
 * 1 = denied licenses found while --strict, 2 = usage / input error.
 */
function main(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--manifest-dir') args.manifestDir = argv[++i];
    else if (argv[i] === '--config') args.configPath = argv[++i];
    else if (argv[i] === '--licenses') args.licensesPath = argv[++i];
    else if (argv[i] === '--strict') args.strict = true;
    else {
      console.error(`Unknown argument: ${argv[i]}`);
      return 2;
    }
  }
  if (!args.manifestDir || !args.configPath || !args.licensesPath) {
    console.error(
      'Usage: node license-checker.js --manifest-dir DIR --config FILE --licenses FILE [--strict]'
    );
    return 2;
  }
  let outcome;
  try {
    outcome = runChecker(args);
  } catch (err) {
    console.error(`license-checker error: ${err.message}`);
    return 2;
  }
  console.log(`Manifest type: ${outcome.manifestType}`);
  console.log(outcome.report);
  const denied = outcome.results.filter((r) => r.status === 'denied').length;
  if (args.strict && denied > 0) {
    console.error(`--strict: failing because ${denied} dependency(ies) have denied licenses`);
    return 1;
  }
  return 0;
}

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}

module.exports = {
  parsePackageJson,
  parseRequirementsTxt,
  checkLicenses,
  formatReport,
  detectManifest,
  runChecker,
  MANIFEST_PARSERS,
};
