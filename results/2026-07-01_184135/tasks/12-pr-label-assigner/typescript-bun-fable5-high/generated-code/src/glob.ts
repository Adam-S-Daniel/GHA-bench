// Minimal glob matcher for path-to-label rules.
//
// Approach: compile the glob to a RegExp once. To avoid the classic pitfall
// where the "*" replacement corrupts the ".*" produced by an earlier "**"
// replacement, wildcards are first swapped for control-character placeholders
// (which cannot appear in a valid glob), then regex metacharacters are
// escaped, and finally the placeholders are expanded to their regex forms.

const GLOBSTAR_SLASH = ""; // "**/" — zero or more whole directories
const GLOBSTAR = ""; // "**"  — anything, may cross "/"
const STAR = ""; // "*"   — anything within one segment
const QMARK = ""; // "?"   — one character within a segment

/** Compile a glob pattern into an anchored RegExp. */
export function globToRegExp(pattern: string): RegExp {
  const withPlaceholders = pattern
    .replaceAll("**/", GLOBSTAR_SLASH)
    .replaceAll("**", GLOBSTAR)
    .replaceAll("*", STAR)
    .replaceAll("?", QMARK);

  const escaped = withPlaceholders.replace(/[.+^${}()|[\]\\]/g, "\\$&");

  const body = escaped
    .replaceAll(GLOBSTAR_SLASH, "(?:[^/]+/)*")
    .replaceAll(GLOBSTAR, ".*")
    .replaceAll(STAR, "[^/]*")
    .replaceAll(QMARK, "[^/]");

  return new RegExp(`^${body}$`);
}

/**
 * Does `filePath` match `pattern`?
 * Gitignore-style convention: a pattern without "/" is matched against the
 * basename, so "*.test.*" matches test files at any depth.
 */
export function matchesGlob(pattern: string, filePath: string): boolean {
  const target = pattern.includes("/")
    ? filePath
    : (filePath.split("/").pop() ?? filePath);
  return globToRegExp(pattern).test(target);
}
