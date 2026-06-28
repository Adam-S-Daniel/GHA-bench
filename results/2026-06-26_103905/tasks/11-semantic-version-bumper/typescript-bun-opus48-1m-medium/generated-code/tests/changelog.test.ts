// TDD step 3 (RED): build a changelog entry from commits.
import { describe, expect, test } from "bun:test";
import { generateChangelog } from "../src/changelog";
import type { Commit } from "../src/commits";

const mk = (o: Partial<Commit>): Commit => ({
  type: "other",
  scope: null,
  subject: "",
  breaking: false,
  ...o,
});

describe("generateChangelog", () => {
  test("groups commits under headed sections with a version + date header", () => {
    const commits: Commit[] = [
      mk({ type: "feat", subject: "add pagination", scope: "api" }),
      mk({ type: "fix", subject: "off-by-one" }),
      mk({ type: "feat", subject: "drop node 16", breaking: true }),
    ];

    const entry = generateChangelog("1.2.0", commits, "2026-06-26");

    expect(entry).toContain("## 1.2.0 (2026-06-26)");
    expect(entry).toContain("### Breaking Changes");
    expect(entry).toContain("- drop node 16");
    expect(entry).toContain("### Features");
    expect(entry).toContain("- **api:** add pagination");
    expect(entry).toContain("### Fixes");
    expect(entry).toContain("- off-by-one");
  });

  test("omits empty sections", () => {
    const entry = generateChangelog(
      "1.0.1",
      [mk({ type: "fix", subject: "a bug" })],
      "2026-01-01",
    );
    expect(entry).toContain("### Fixes");
    expect(entry).not.toContain("### Features");
    expect(entry).not.toContain("### Breaking Changes");
  });
});
