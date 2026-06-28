// Glob matcher used by the label rules.
//
// Supported syntax:
//   *    - any run of characters within a single path segment (does not cross "/")
//   ?    - exactly one non-"/" character
//   **   - any number of characters including "/" (crosses path segments)
//          As a path component it matches zero or more directories, so
//          "docs/**" matches "docs" itself and everything beneath it.
//
// Matching convention: a pattern that contains no "/" (e.g. "*.test.*") is
// matched against the file's basename, so bare patterns catch matching files at
// any depth. Patterns containing "/" are matched against the full path.
//
// We compile the glob to a single anchored RegExp. All literal characters have
// their regex metacharacters escaped so that, for example, the "." in
// "README.md" is treated literally rather than as a wildcard.

function escapeRegexLiteral(char: string): string {
  return char.replace(/[.+^${}()|[\]\\]/g, "\\$&");
}

export function globToRegExp(glob: string): RegExp {
  let re = "";
  let i = 0;
  const n = glob.length;

  while (i < n) {
    const c = glob[i]!;

    // Globstar: a run of two or more consecutive "*".
    if (c === "*" && glob[i + 1] === "*") {
      let j = i + 2;
      while (glob[j] === "*") j++;
      const prevIsSlash = i > 0 && glob[i - 1] === "/";
      const atEnd = j >= n;
      const nextIsSlash = glob[j] === "/";

      if (prevIsSlash) {
        // A preceding "/" was already emitted; drop it so we can express the
        // "zero or more directories" semantics around the globstar.
        re = re.slice(0, -1);
        if (atEnd) {
          re += "(?:/.*)?"; // trailing "/**": this dir and anything below it
        } else if (nextIsSlash) {
          re += "(?:/.*)?/"; // mid "/**/": zero or more intermediate dirs
          i = j + 1; // consume the following "/"
          continue;
        } else {
          re += "(?:/.*)?";
        }
      } else if (i === 0 && nextIsSlash) {
        re += "(?:.*/)?"; // leading "**/": zero or more leading dirs
        i = j + 1; // consume the following "/"
        continue;
      } else {
        re += ".*"; // bare or embedded "**"
      }
      i = j;
      continue;
    }

    if (c === "*") {
      re += "[^/]*";
    } else if (c === "?") {
      re += "[^/]";
    } else if (c === "/") {
      re += "/";
    } else {
      re += escapeRegexLiteral(c);
    }
    i++;
  }

  return new RegExp("^" + re + "$");
}

function basename(path: string): string {
  const idx = path.lastIndexOf("/");
  return idx === -1 ? path : path.slice(idx + 1);
}

export function matchGlob(path: string, glob: string): boolean {
  const target = glob.includes("/") ? path : basename(path);
  return globToRegExp(glob).test(target);
}
