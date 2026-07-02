// Core logic for the semantic version bumper.
// Parses a semver string, inspects conventional-commit messages to decide
// the bump type, applies the bump, and renders a changelog entry.

export interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

export type BumpType = "major" | "minor" | "patch" | "none";

const SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)$/;

/** Parses a strict "major.minor.patch" string into a SemVer object. */
export function parseVersion(version: string): SemVer {
  const match = SEMVER_PATTERN.exec(version.trim());
  if (!match) {
    throw new Error(
      `Invalid semantic version string: "${version}". Expected format "major.minor.patch".`,
    );
  }
  const [, major, minor, patch] = match;
  return { major: Number(major), minor: Number(minor), patch: Number(patch) };
}

/** Renders a SemVer object back into its canonical "major.minor.patch" string. */
export function formatVersion(version: SemVer): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}

const BREAKING_MARKER = /^\w+(\([^)]*\))?!:/; // e.g. "feat!:" or "feat(api)!:"
const BREAKING_FOOTER = /BREAKING CHANGE:/;
const FEAT_PREFIX = /^feat(\([^)]*\))?:/;
const FIX_PREFIX = /^fix(\([^)]*\))?:/;

/**
 * Inspects a list of conventional-commit messages and determines the
 * highest-priority bump type they trigger: breaking -> major, feat -> minor,
 * fix -> patch, anything else -> none.
 */
export function determineBumpType(commits: string[]): BumpType {
  if (commits.length === 0) {
    throw new Error("Cannot determine bump type: no commits were provided.");
  }

  let hasFeat = false;
  let hasFix = false;

  for (const commit of commits) {
    const firstLine = commit.split("\n")[0]?.trim() ?? "";
    if (BREAKING_MARKER.test(firstLine) || BREAKING_FOOTER.test(commit)) {
      return "major";
    }
    if (FEAT_PREFIX.test(firstLine)) {
      hasFeat = true;
    } else if (FIX_PREFIX.test(firstLine)) {
      hasFix = true;
    }
  }

  if (hasFeat) return "minor";
  if (hasFix) return "patch";
  return "none";
}

/** Applies a bump type to a SemVer, resetting lower-precision fields as needed. */
export function bumpVersion(version: SemVer, bump: BumpType): SemVer {
  switch (bump) {
    case "major":
      return { major: version.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: version.major, minor: version.minor + 1, patch: 0 };
    case "patch":
      return {
        major: version.major,
        minor: version.minor,
        patch: version.patch + 1,
      };
    case "none":
      return { ...version };
  }
}

interface CommitGroups {
  breaking: string[];
  features: string[];
  fixes: string[];
  other: string[];
}

function groupCommits(commits: string[]): CommitGroups {
  const groups: CommitGroups = { breaking: [], features: [], fixes: [], other: [] };
  for (const commit of commits) {
    const firstLine = commit.split("\n")[0]?.trim() ?? "";
    if (BREAKING_MARKER.test(firstLine) || BREAKING_FOOTER.test(commit)) {
      groups.breaking.push(firstLine);
    } else if (FEAT_PREFIX.test(firstLine)) {
      groups.features.push(firstLine);
    } else if (FIX_PREFIX.test(firstLine)) {
      groups.fixes.push(firstLine);
    } else {
      groups.other.push(firstLine);
    }
  }
  return groups;
}

/** Builds a markdown changelog section for a released version from its commits. */
export function generateChangelogEntry(
  newVersion: string,
  commits: string[],
): string {
  const groups = groupCommits(commits);
  const sections: string[] = [`## ${newVersion}`];

  if (groups.breaking.length > 0) {
    sections.push("### BREAKING CHANGES", ...groups.breaking.map((c) => `- ${c}`));
  }
  if (groups.features.length > 0) {
    sections.push("### Features", ...groups.features.map((c) => `- ${c}`));
  }
  if (groups.fixes.length > 0) {
    sections.push("### Bug Fixes", ...groups.fixes.map((c) => `- ${c}`));
  }
  if (groups.other.length > 0) {
    sections.push("### Other", ...groups.other.map((c) => `- ${c}`));
  }

  return sections.join("\n\n");
}

interface VersionFileShape {
  version: string;
  [key: string]: unknown;
}

/** Reads the "version" field out of a JSON version file (or package.json). */
export async function readVersionFile(path: string): Promise<string> {
  const file = Bun.file(path);
  if (!(await file.exists())) {
    throw new Error(`Version file not found: "${path}".`);
  }
  const contents: VersionFileShape = await file.json();
  if (typeof contents.version !== "string") {
    throw new Error(`Version file "${path}" is missing a "version" string field.`);
  }
  return contents.version;
}

/** Writes a new version into a JSON version file, preserving other fields. */
export async function writeVersionFile(
  path: string,
  newVersion: SemVer,
): Promise<void> {
  const file = Bun.file(path);
  const existing: VersionFileShape = (await file.exists())
    ? await file.json()
    : { version: "0.0.0" };
  const updated = { ...existing, version: formatVersion(newVersion) };
  await Bun.write(path, JSON.stringify(updated, null, 2) + "\n");
}
