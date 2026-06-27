#!/usr/bin/env node
// Thin command-line wrapper around src/bumper.js.
//
// Usage:
//   node src/cli.js [--version-file VERSION] [--commits commits.log] \
//                   [--changelog CHANGELOG.md] [--date YYYY-MM-DD]
//
// Output (stdout), designed to be both human- and machine-readable:
//   OLD_VERSION=1.1.0
//   BUMP_TYPE=minor
//   NEW_VERSION=1.2.0
//
// When run under GitHub Actions, the same key/value pairs are also written to
// $GITHUB_OUTPUT so later steps can consume them.

import fs from "node:fs";
import { bump } from "./bumper.js";

// Minimal flag parser: --key value  (also tolerates --key=value).
function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    let arg = argv[i];
    if (!arg.startsWith("--")) continue;
    arg = arg.slice(2);
    let value;
    if (arg.includes("=")) {
      [arg, value] = arg.split(/=(.*)/s);
    } else {
      value = argv[++i];
    }
    opts[arg] = value;
  }
  return opts;
}

// Today's date as YYYY-MM-DD (overridable via --date for reproducible output).
function today() {
  return new Date().toISOString().slice(0, 10);
}

// Decide which file holds the version when the user didn't pass --version-file:
// prefer a plain VERSION file, then package.json. This lets the same workflow
// drive either format based purely on which file the repo contains.
function resolveVersionFile(explicit) {
  if (explicit) return explicit;
  for (const candidate of ["VERSION", "package.json"]) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return "VERSION"; // fall through -> readVersion will report a clear error
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  const config = {
    versionFile: resolveVersionFile(opts["version-file"]),
    commitsFile: opts["commits"] || "commits.log",
    changelogFile: opts["changelog"] || "CHANGELOG.md",
    date: opts["date"] || today(),
  };

  const { oldVersion, newVersion, bumpType } = bump(config);

  // Human/machine readable stdout.
  const out = [
    `OLD_VERSION=${oldVersion}`,
    `BUMP_TYPE=${bumpType}`,
    `NEW_VERSION=${newVersion}`,
  ];
  console.log(out.join("\n"));

  // Expose as step outputs when running inside GitHub Actions.
  if (process.env.GITHUB_OUTPUT) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, out.join("\n") + "\n");
  }
}

try {
  main();
} catch (err) {
  // Graceful failure: meaningful message, non-zero exit code.
  console.error(`error: ${err.message}`);
  process.exit(1);
}
