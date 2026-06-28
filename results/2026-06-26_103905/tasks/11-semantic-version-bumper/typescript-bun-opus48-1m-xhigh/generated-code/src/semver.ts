// semver.ts — parsing, formatting and bumping of Semantic Versions.
//
// We deliberately implement a small, dependency-free subset of SemVer 2.0.0
// (https://semver.org). The bumper only needs to: read a version, increment
// one of its three numeric components, and write it back. Prerelease and
// build metadata are preserved on parse/format so we never silently lose
// information, but a release bump clears them (a freshly released version is
// not a prerelease).

/** A parsed Semantic Version. */
export interface SemVer {
  major: number;
  minor: number;
  patch: number;
  /** Dot-separated prerelease identifiers, e.g. "rc.1" (without the leading "-"). */
  prerelease?: string;
  /** Dot-separated build metadata, e.g. "build.5" (without the leading "+"). */
  build?: string;
}

/**
 * The kind of version increment implied by a set of commits.
 * "none" means no release-worthy change was found.
 */
export type BumpType = "major" | "minor" | "patch" | "none";

// MAJOR.MINOR.PATCH with optional `-prerelease` and `+build` sections.
// A leading "v" and surrounding whitespace are stripped before matching.
const SEMVER_RE =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-.]+))?(?:\+([0-9A-Za-z-.]+))?$/;

/**
 * Parse a version string into a {@link SemVer}.
 * Accepts an optional leading "v" and surrounding whitespace.
 * @throws Error with a meaningful message when the string is not valid SemVer.
 */
export function parseVersion(input: string): SemVer {
  const cleaned = input.trim().replace(/^v/i, "");
  const match = SEMVER_RE.exec(cleaned);
  if (!match) {
    throw new Error(
      `Invalid semantic version: ${JSON.stringify(input)}. ` +
        `Expected MAJOR.MINOR.PATCH (e.g. "1.2.3").`,
    );
  }
  const [, major, minor, patch, prerelease, build] = match;
  return {
    major: Number(major),
    minor: Number(minor),
    patch: Number(patch),
    prerelease: prerelease,
    build: build,
  };
}

/** Render a {@link SemVer} back into its canonical string form. */
export function formatVersion(v: SemVer): string {
  let out = `${v.major}.${v.minor}.${v.patch}`;
  if (v.prerelease) out += `-${v.prerelease}`;
  if (v.build) out += `+${v.build}`;
  return out;
}

/**
 * Return a new {@link SemVer} incremented per SemVer rules. A real release
 * bump (major/minor/patch) discards any prerelease/build metadata. A "none"
 * bump returns the version unchanged.
 */
export function bumpVersion(v: SemVer, bump: BumpType): SemVer {
  switch (bump) {
    case "major":
      return { major: v.major + 1, minor: 0, patch: 0 };
    case "minor":
      return { major: v.major, minor: v.minor + 1, patch: 0 };
    case "patch":
      return { major: v.major, minor: v.minor, patch: v.patch + 1 };
    case "none":
      return { ...v };
  }
}
