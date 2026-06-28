// Semantic Version Bumper
// ------------------------
// Parses a semantic version (from a plain version file or a package.json),
// inspects conventional-commit messages to decide the next version
// (feat -> minor, fix -> patch, breaking -> major), updates the version file,
// generates a changelog entry, and prints the new version.
//
// Built with strict red/green TDD — see version-bumper.test.ts for the spec.

import { appendFileSync } from "node:fs";

/** A parsed semantic version. Pre-release / build metadata are intentionally
 *  out of scope for this tool; we operate on the MAJOR.MINOR.PATCH core. */
export interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

/**
 * Parse a `MAJOR.MINOR.PATCH` string into its numeric components.
 *
 * A leading `v` (e.g. `v1.2.3`) and surrounding whitespace are tolerated so the
 * function is forgiving of common version-file conventions.
 *
 * @throws if the string is not a valid `MAJOR.MINOR.PATCH` triple.
 */
export function parseVersion(input: string): SemVer {
  const cleaned = input.trim().replace(/^v/i, "");
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(cleaned);
  if (!match) {
    throw new Error(
      `Invalid semantic version: "${input}". Expected MAJOR.MINOR.PATCH (e.g. 1.2.3).`,
    );
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

/** Render a SemVer back into its canonical `MAJOR.MINOR.PATCH` string. */
export function formatVersion(version: SemVer): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

/** The kind of release implied by a set of commits, in increasing precedence. */
export type BumpType = "none" | "patch" | "minor" | "major";

/** A single conventional commit after parsing. `type` is null when the message
 *  does not follow the conventional-commits grammar. */
export interface ParsedCommit {
  type: string | null;
  scope: string | null;
  breaking: boolean;
  description: string;
  /** The full, original commit message (subject + body). */
  raw: string;
}

// Conventional-commits subject grammar: `type(scope)!: description`.
// The scope and the breaking-`!` marker are both optional.
const SUBJECT_RE = /^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?:\s*(?<desc>.*)$/;

// A footer line that signals a breaking change, per the spec. Both the spaced
// ("BREAKING CHANGE:") and hyphenated ("BREAKING-CHANGE:") forms are valid.
const BREAKING_FOOTER_RE = /^BREAKING[ -]CHANGE:/m;

/**
 * Parse a single commit message (subject line plus optional body) into a
 * structured {@link ParsedCommit}.
 *
 * A message is "breaking" if either the subject carries the `!` marker (e.g.
 * `feat!:`) or the body contains a `BREAKING CHANGE:` / `BREAKING-CHANGE:`
 * footer. Messages that don't match the conventional grammar get `type: null`
 * and are treated as release-neutral by {@link determineBump}.
 */
export function parseCommit(message: string): ParsedCommit {
  const raw = message;
  // Split off the subject (first line) from the body for breaking-footer checks.
  const newlineIdx = message.indexOf("\n");
  const subject = (newlineIdx === -1 ? message : message.slice(0, newlineIdx)).trim();
  const body = newlineIdx === -1 ? "" : message.slice(newlineIdx + 1);

  const match = SUBJECT_RE.exec(subject);
  const breakingFromFooter = BREAKING_FOOTER_RE.test(body);

  if (!match || !match.groups) {
    // Non-conventional message: still report a breaking footer if one exists,
    // but there is no type to drive a feat/fix bump.
    return {
      type: null,
      scope: null,
      breaking: breakingFromFooter,
      description: subject,
      raw,
    };
  }

  const { type, scope, bang, desc } = match.groups;
  return {
    type: type.toLowerCase(),
    scope: scope ?? null,
    breaking: bang === "!" || breakingFromFooter,
    description: desc.trim(),
    raw,
  };
}

/**
 * Reduce a list of commits to the single strongest release signal.
 *
 * Precedence (highest wins): any breaking change -> major; any `feat` -> minor;
 * any `fix` -> patch; otherwise -> none. Unknown types (docs, chore, refactor,
 * …) never trigger a release on their own.
 */
export function determineBump(commits: ParsedCommit[]): BumpType {
  let bump: BumpType = "none";
  for (const commit of commits) {
    if (commit.breaking) {
      return "major"; // major is the ceiling — short-circuit.
    }
    if (commit.type === "feat") {
      bump = "minor";
    } else if (commit.type === "fix" && bump !== "minor") {
      bump = "patch";
    }
  }
  return bump;
}

/**
 * Apply a {@link BumpType} to a version, following semantic-versioning rules:
 * a major bump zeroes minor and patch, a minor bump zeroes patch, a patch bump
 * increments patch, and `none` returns the version unchanged.
 */
export function bumpVersion(version: SemVer, bump: BumpType): SemVer {
  switch (bump) {
    case "major":
      return { major: version.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: version.major, minor: version.minor + 1, patch: 0 };
    case "patch":
      return { major: version.major, minor: version.minor, patch: version.patch + 1 };
    case "none":
      return { ...version };
  }
}

// Commits in a log file are separated either by an explicit, human-readable
// delimiter line (handy for hand-written fixtures) or by the ASCII record
// separator (0x1e) that `git log --format=%B%x1e` emits. Supporting both means
// the same parser works for fixtures and for real git output.
const COMMIT_DELIMITER_RE = /\x1e|^[ \t]*--- COMMIT ---[ \t]*$/m;

/**
 * Split a raw commit log into individual commit messages.
 *
 * Whitespace-only segments are dropped and each message is trimmed. A log with
 * no delimiter is treated as a single commit, so multi-commit logs must place a
 * `--- COMMIT ---` line (or a 0x1e byte) between entries.
 */
export function splitCommits(raw: string): string[] {
  return raw
    .split(COMMIT_DELIMITER_RE)
    .map((chunk) => chunk.trim())
    .filter((chunk) => chunk.length > 0);
}

/** Split a raw commit log and parse each entry into a {@link ParsedCommit}. */
export function parseCommitLog(raw: string): ParsedCommit[] {
  return splitCommits(raw).map(parseCommit);
}

/** Prefix a changelog bullet with a bold scope, e.g. `**api:** `, if present. */
function changelogLine(commit: ParsedCommit): string {
  const scope = commit.scope ? `**${commit.scope}:** ` : "";
  return `- ${scope}${commit.description}`;
}

/**
 * Render a single, conventional-changelog-style entry for `version`.
 *
 * Commits are grouped into BREAKING CHANGES (any breaking commit), Features
 * (`feat`), and Bug Fixes (`fix`). Empty sections are omitted. When nothing is
 * user-facing (e.g. only chores), a placeholder line keeps the entry valid.
 * The `date` is injected (rather than read from the clock) so the output is
 * deterministic and unit-testable.
 */
export function generateChangelog(
  version: string,
  commits: ParsedCommit[],
  date: string,
): string {
  const breaking = commits.filter((c) => c.breaking);
  const features = commits.filter((c) => c.type === "feat");
  const fixes = commits.filter((c) => c.type === "fix");

  const lines: string[] = [`## [${version}] - ${date}`, ""];

  const section = (title: string, entries: ParsedCommit[]): void => {
    if (entries.length === 0) return;
    lines.push(`### ${title}`, "");
    for (const commit of entries) lines.push(changelogLine(commit));
    lines.push("");
  };

  section("BREAKING CHANGES", breaking);
  section("Features", features);
  section("Bug Fixes", fixes);

  if (breaking.length === 0 && features.length === 0 && fixes.length === 0) {
    lines.push("_No user-facing changes._", "");
  }

  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// File-IO layer
//
// The functions below are split into PURE helpers (content in -> content out,
// trivially unit-testable) and thin async wrappers that perform the actual
// disk reads/writes. Keeping the parsing/serialising logic pure is what let it
// be driven by TDD without mocking the filesystem.
// ---------------------------------------------------------------------------

/** Detect the indentation (spaces count or a tab) used by a pretty-printed
 *  JSON document, so we can re-serialise it without reformatting the whole file. */
function detectJsonIndent(content: string): number | string {
  const match = content.match(/\n([ \t]+)\S/);
  if (!match) return 2; // minified or single-line — fall back to 2 spaces.
  const whitespace = match[1]!;
  return whitespace.includes("\t") ? "\t" : whitespace.length;
}

/** Pull the current version out of a file's contents. */
export function extractVersion(content: string, isJson: boolean): string {
  if (!isJson) {
    // A plain version file: the version is simply its (first, trimmed) line.
    return content.trim().split(/\r?\n/)[0]!.trim();
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (err) {
    throw new Error(
      `Failed to parse JSON version file: ${(err as Error).message}`,
    );
  }
  const version = (parsed as Record<string, unknown>)?.version;
  if (typeof version !== "string") {
    throw new Error('JSON version file has no "version" field (or it is not a string).');
  }
  return version;
}

/**
 * Produce the new file contents with `newVersion` substituted in.
 *
 * For package.json we parse, set the TOP-LEVEL `version`, then re-serialise
 * using the file's detected indentation. This correctly targets the top-level
 * key (a naive "replace the first \"version\": string" would clobber a nested
 * key that happened to appear earlier) while keeping the file's indentation and
 * trailing-newline convention intact.
 */
export function applyVersionToContent(
  content: string,
  isJson: boolean,
  newVersion: string,
): string {
  if (!isJson) {
    return `${newVersion}\n`;
  }
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(content) as Record<string, unknown>;
  } catch (err) {
    throw new Error(
      `Failed to parse JSON version file: ${(err as Error).message}`,
    );
  }
  if (typeof parsed.version !== "string") {
    throw new Error('JSON version file has no "version" field to update.');
  }
  parsed.version = newVersion;
  const serialized = JSON.stringify(parsed, null, detectJsonIndent(content));
  // Preserve whether the original file ended with a trailing newline.
  return content.endsWith("\n") ? `${serialized}\n` : serialized;
}

const CHANGELOG_HEADER = "# Changelog\n\nAll notable changes to this project are documented in this file.\n";

/**
 * Insert a freshly generated changelog `entry` at the top of an existing
 * changelog document (newest-first), keeping a single `# Changelog` header.
 */
export function prependChangelog(existing: string, entry: string): string {
  const block = `${entry.trimEnd()}\n`;
  if (!existing.trim()) {
    return `${CHANGELOG_HEADER}\n${block}`;
  }
  // Insert above the first existing release entry, if any.
  const firstEntry = existing.indexOf("## ");
  if (firstEntry === -1) {
    return `${existing.trimEnd()}\n\n${block}`;
  }
  const head = existing.slice(0, firstEntry).trimEnd();
  const rest = existing.slice(firstEntry).trimEnd();
  return `${head}\n\n${block}\n${rest}\n`;
}

/** A version file that has been read and understood. */
export interface VersionFile {
  path: string;
  isJson: boolean;
  /** The raw, original file contents. */
  raw: string;
  /** The current version string extracted from {@link raw}. */
  version: string;
}

/** Decide whether a path/content pair should be treated as JSON (package.json). */
function looksLikeJson(path: string, content: string): boolean {
  if (path.toLowerCase().endsWith(".json")) return true;
  // Heuristic for oddly-named files: starts with `{` and parses with a version.
  const trimmed = content.trimStart();
  if (!trimmed.startsWith("{")) return false;
  try {
    return typeof (JSON.parse(content) as Record<string, unknown>)?.version === "string";
  } catch {
    return false;
  }
}

/** Read and parse a version file (plain or package.json). */
export async function readVersionFile(path: string): Promise<VersionFile> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Version file not found: ${path}`);
  }
  const raw = await file.text();
  const isJson = looksLikeJson(path, raw);
  const version = extractVersion(raw, isJson);
  return { path, isJson, raw, version };
}

/** Write `newVersion` back into a previously-read version file. */
export async function writeVersionFile(
  file: VersionFile,
  newVersion: string,
): Promise<void> {
  const updated = applyVersionToContent(file.raw, file.isJson, newVersion);
  await Bun.write(file.path, updated);
}

/** Prepend `entry` to a changelog file, creating it (with header) if needed. */
export async function updateChangelogFile(path: string, entry: string): Promise<void> {
  const file = Bun.file(path);
  const existing = (await file.exists()) ? await file.text() : "";
  await Bun.write(path, prependChangelog(existing, entry));
}

// ---------------------------------------------------------------------------
// Commit sourcing: a fixture file, or real git history.
// ---------------------------------------------------------------------------

/** Read a fixture commit-log file, raising a clear error if it is absent. */
export async function readCommitsFile(path: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Commit log file not found: ${path}`);
  }
  return file.text();
}

/**
 * Read commit messages from real git history using
 * `git log <range> --format=%B%x1e` (full message bodies, 0x1e-separated so the
 * {@link splitCommits} parser can recover individual commits). `cwd` defaults to
 * the process working directory; `range` (e.g. `v1.0.0..HEAD`) is optional.
 */
export async function readCommitsFromGit(
  range: string | null,
  cwd: string = process.cwd(),
): Promise<string> {
  const args = ["log", "--format=%B%x1e"];
  if (range) args.push(range);
  const proc = Bun.spawnSync(["git", ...args], { cwd });
  if (proc.exitCode !== 0) {
    const stderr = new TextDecoder().decode(proc.stderr).trim();
    throw new Error(`git log failed (exit ${proc.exitCode}): ${stderr}`);
  }
  return new TextDecoder().decode(proc.stdout);
}

// ---------------------------------------------------------------------------
// CLI orchestration
// ---------------------------------------------------------------------------

/** Fully-resolved options controlling a bump run. */
export interface CliOptions {
  versionFile: string;
  /** Fixture commit-log path. When null, commits come from git. */
  commitsFile: string | null;
  /** Changelog path. When null, changelog writing is skipped. */
  changelogFile: string | null;
  /** Optional git range (only used when reading from git). */
  gitRange: string | null;
  /** Optional date override (YYYY-MM-DD) for deterministic changelog entries. */
  date: string | null;
  /** When true, compute the bump but do not write any files. */
  dryRun: boolean;
}

/** The outcome of a bump run, suitable for printing and for CI step outputs. */
export interface BumpResult {
  previousVersion: string;
  newVersion: string;
  bump: BumpType;
  commitCount: number;
  changelogEntry: string;
  /** True when the version actually changed (i.e. bump !== "none"). */
  changed: boolean;
}

const USAGE = `Semantic Version Bumper

Usage: bun run version-bumper.ts [options]

Options:
  --version-file <path>   Version file to read/update (default: version.txt).
                          A path ending in .json is treated as package.json.
  --commits <path>        Read commit messages from this fixture file instead
                          of git. Commits separated by a "--- COMMIT ---" line.
  --git-range <range>     git range to read commits from (e.g. v1.0.0..HEAD).
                          Ignored when --commits is given.
  --changelog <path>      Changelog file to prepend to (default: CHANGELOG.md).
  --no-changelog          Do not write a changelog.
  --date <YYYY-MM-DD>     Date to stamp the changelog entry with (default: today).
  --dry-run               Compute the next version without writing any files.
  -h, --help              Show this help.`;

/** Parse argv (without the `bun`/script prefix) into {@link CliOptions}. */
export function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = {
    versionFile: "version.txt",
    commitsFile: null,
    changelogFile: "CHANGELOG.md",
    gitRange: null,
    date: null,
    dryRun: false,
  };

  // Pull the value that must follow a value-taking flag, or fail clearly.
  const valueFor = (flag: string, i: number): string => {
    const value = argv[i + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Flag ${flag} expects a value.`);
    }
    return value;
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    switch (arg) {
      case "--version-file":
        opts.versionFile = valueFor(arg, i++);
        break;
      case "--commits":
        opts.commitsFile = valueFor(arg, i++);
        break;
      case "--git-range":
        opts.gitRange = valueFor(arg, i++);
        break;
      case "--changelog":
        opts.changelogFile = valueFor(arg, i++);
        break;
      case "--no-changelog":
        opts.changelogFile = null;
        break;
      case "--date":
        opts.date = valueFor(arg, i++);
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "-h":
      case "--help":
        // Surfaced as a sentinel the caller can detect; keeps parseArgs pure.
        throw new Error("__HELP__");
      default:
        throw new Error(`Unknown argument: ${arg}\n\n${USAGE}`);
    }
  }
  return opts;
}

/**
 * Run a full bump: read the current version, gather commits, decide and apply
 * the bump, and (unless dry-run / no change) write the version + changelog
 * files. `today` is injected so the changelog date is deterministic in tests.
 */
export async function runBump(opts: CliOptions, today: string): Promise<BumpResult> {
  const versionFile = await readVersionFile(opts.versionFile);
  const current = parseVersion(versionFile.version);

  const rawLog = opts.commitsFile
    ? await readCommitsFile(opts.commitsFile)
    : await readCommitsFromGit(opts.gitRange);
  const commits = parseCommitLog(rawLog);

  const bump = determineBump(commits);
  const next = bumpVersion(current, bump);
  const newVersion = formatVersion(next);
  const date = opts.date ?? today;
  const changelogEntry = generateChangelog(newVersion, commits, date);
  const changed = bump !== "none";

  if (!opts.dryRun && changed) {
    await writeVersionFile(versionFile, newVersion);
    if (opts.changelogFile) {
      await updateChangelogFile(opts.changelogFile, changelogEntry);
    }
  }

  return {
    previousVersion: versionFile.version,
    newVersion,
    bump,
    commitCount: commits.length,
    changelogEntry,
    changed,
  };
}

/** Today's date as YYYY-MM-DD (UTC), used as the default changelog stamp. */
function todayISO(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * CLI entry point. Prints a human summary plus machine-readable `NEW_VERSION=…`
 * and `BUMP_TYPE=…` lines, and — when running inside GitHub Actions — also
 * publishes step outputs via `$GITHUB_OUTPUT`. Returns a process exit code.
 */
export async function main(argv: string[]): Promise<number> {
  let opts: CliOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    const message = (err as Error).message;
    if (message === "__HELP__") {
      console.log(USAGE);
      return 0;
    }
    console.error(`Error: ${message}`);
    return 2;
  }

  try {
    const result = await runBump(opts, todayISO());

    // Human-readable summary.
    console.log(`Previous version: ${result.previousVersion}`);
    console.log(`Bump type:        ${result.bump}`);
    console.log(`Commits analyzed: ${result.commitCount}`);
    console.log(`New version:      ${result.newVersion}`);
    if (!result.changed) {
      console.log("No release-worthy commits found; version left unchanged.");
    } else if (opts.dryRun) {
      console.log("Dry run: no files were modified.");
    }

    // Machine-readable lines (stable contract for the CI assertions).
    console.log(`NEW_VERSION=${result.newVersion}`);
    console.log(`BUMP_TYPE=${result.bump}`);
    console.log(`VERSION_CHANGED=${result.changed}`);

    // GitHub Actions step outputs, when available. $GITHUB_OUTPUT is an
    // append-only file shared across the whole step, so we APPEND rather than
    // overwrite (clobbering it would drop other steps' outputs).
    const githubOutput = process.env.GITHUB_OUTPUT;
    if (githubOutput) {
      const outLines =
        `new-version=${result.newVersion}\n` +
        `previous-version=${result.previousVersion}\n` +
        `bump-type=${result.bump}\n` +
        `changed=${result.changed}\n`;
      appendFileSync(githubOutput, outLines);
    }

    return 0;
  } catch (err) {
    console.error(`Error: ${(err as Error).message}`);
    return 1;
  }
}

// Only run the CLI when executed directly (`bun run version-bumper.ts`), not
// when imported by the test suite.
if (import.meta.main) {
  process.exit(await main(Bun.argv.slice(2)));
}
