/**
 * Minimal glob matcher for path-to-label rules.
 * Supports:
 *   `*`   matches any run of characters except `/`
 *   `**`  matches any run of characters including `/`
 *   `?`   matches exactly one character except `/`
 * Matching is anchored to the whole path (i.e. "docs/*" does not match "a/docs/b").
 * A pattern containing no `/` (e.g. "*.test.*") is matched against the file's
 * basename instead, so it applies regardless of directory depth.
 */
export function matchGlob(pattern: string, filePath: string): boolean {
  const regex = globToRegExp(pattern);
  if (!pattern.includes("/")) {
    const basename = filePath.slice(filePath.lastIndexOf("/") + 1);
    return regex.test(basename);
  }
  return regex.test(filePath);
}

function globToRegExp(pattern: string): RegExp {
  let result = "";
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i];
    if (char === "*") {
      if (pattern[i + 1] === "*") {
        // `**` matches across path separators, including zero segments.
        i++;
        if (pattern[i + 1] === "/") {
          result += "(?:.*/)?";
          i++;
        } else {
          result += ".*";
        }
      } else {
        result += "[^/]*";
      }
    } else if (char === "?") {
      result += "[^/]";
    } else {
      result += escapeRegExpChar(char as string);
    }
  }
  return new RegExp(`^${result}$`);
}

function escapeRegExpChar(char: string): string {
  return /[.+^${}()|[\]\\]/.test(char) ? `\\${char}` : char;
}
