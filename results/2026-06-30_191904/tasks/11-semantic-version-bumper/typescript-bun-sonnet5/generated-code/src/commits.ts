// Parses `git log` (default, non---format) style commit logs and derives a
// semver bump type from Conventional Commits headers
// (https://www.conventionalcommits.org/).
import type { BumpType } from "./semver.ts";

export interface Commit {
  hash: string;
  subject: string;
  body: string;
}

const COMMIT_HEADER = /^commit ([0-9a-f]{7,40})/;
// Conventional Commits header: "<type>[(scope)][!]: <description>"
const CONVENTIONAL_HEADER = /^(\w+)(\([^)]*\))?(!)?:\s*.+/;
const BREAKING_FOOTER = /^BREAKING[ -]CHANGE:/m;

/**
 * Parses raw `git log` text into a list of commits, extracting the
 * hash, the message subject (first indented line), and the message body
 * (remaining indented lines, de-indented and trimmed).
 */
export function parseCommitLog(raw: string): Commit[] {
  const trimmed = raw.trim();
  if (trimmed === "") {
    return [];
  }

  const lines = raw.split("\n");
  const commits: Commit[] = [];
  let currentHash: string | null = null;
  let messageLines: string[] = [];

  const flush = (): void => {
    if (currentHash === null) return;
    // Message lines are indented 4 spaces by `git log`; de-indent them.
    const dedented = messageLines.map((line) => line.replace(/^ {4}/, ""));
    // Drop leading/trailing blank lines but keep internal blank lines
    // (they separate the subject from body paragraphs).
    while (dedented.length > 0 && dedented[0] === "") dedented.shift();
    while (dedented.length > 0 && dedented[dedented.length - 1] === "")
      dedented.pop();
    const subject = dedented[0] ?? "";
    const body = dedented.slice(1).join("\n").trim();
    commits.push({ hash: currentHash, subject, body });
  };

  for (const line of lines) {
    const headerMatch = COMMIT_HEADER.exec(line);
    if (headerMatch) {
      flush();
      currentHash = headerMatch[1]!;
      messageLines = [];
      continue;
    }
    if (currentHash !== null && /^Author:|^Date:/.test(line)) {
      continue;
    }
    if (currentHash !== null) {
      messageLines.push(line);
    }
  }
  flush();

  if (commits.length === 0) {
    throw new Error(
      "No commits found in commit log: expected `git log` output with 'commit <hash>' headers.",
    );
  }

  return commits;
}

/**
 * Determines the semver bump implied by a set of commits, following
 * Conventional Commits precedence: a breaking change (major) always wins
 * over a feature (minor), which always wins over a fix (patch).
 */
export function determineBumpType(commits: Commit[]): BumpType {
  let highest: BumpType = "none";

  for (const commit of commits) {
    const headerMatch = CONVENTIONAL_HEADER.exec(commit.subject);
    const isBreaking =
      headerMatch?.[3] === "!" || BREAKING_FOOTER.test(commit.body);

    if (isBreaking) {
      return "major"; // nothing outranks major; short-circuit
    }

    const type = headerMatch?.[1];
    if (type === "feat" && highest !== "minor") {
      highest = "minor";
    } else if (type === "fix" && highest === "none") {
      highest = "patch";
    }
  }

  return highest;
}
