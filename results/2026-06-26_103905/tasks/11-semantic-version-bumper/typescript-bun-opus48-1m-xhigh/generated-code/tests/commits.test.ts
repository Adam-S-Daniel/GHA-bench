// RED phase for the conventional-commit parser.
//
// Conventional Commits (https://www.conventionalcommits.org) encode the
// intent of a change in its message header:
//   <type>[optional scope][!]: <description>
// plus an optional body/footer that may contain "BREAKING CHANGE:".
//
// The parser must translate each commit into the SemVer bump it implies:
//   feat       -> minor
//   fix        -> patch
//   breaking   -> major   (via "!" or a "BREAKING CHANGE:" footer)
//   other      -> none
// and an aggregate "determineBump" must take the highest-precedence bump.
import { describe, expect, it } from "bun:test";
import {
  determineBump,
  parseCommitLog,
  parseCommitMessage,
} from "../src/commits.ts";

describe("parseCommitMessage", () => {
  it("classifies a feat as a minor bump", () => {
    const c = parseCommitMessage("feat: add dark mode");
    expect(c.type).toBe("feat");
    expect(c.scope).toBeUndefined();
    expect(c.breaking).toBe(false);
    expect(c.description).toBe("add dark mode");
    expect(c.bump).toBe("minor");
  });

  it("classifies a fix as a patch bump and captures the scope", () => {
    const c = parseCommitMessage("fix(parser): handle empty input");
    expect(c.type).toBe("fix");
    expect(c.scope).toBe("parser");
    expect(c.bump).toBe("patch");
  });

  it("treats a trailing '!' as a breaking (major) change", () => {
    const c = parseCommitMessage("feat(api)!: drop legacy endpoints");
    expect(c.type).toBe("feat");
    expect(c.scope).toBe("api");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  it("detects a 'BREAKING CHANGE:' footer in the body", () => {
    const message = [
      "refactor: rework config loading",
      "",
      "BREAKING CHANGE: config files now require a version field",
    ].join("\n");
    const c = parseCommitMessage(message);
    expect(c.type).toBe("refactor");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  it("also accepts the hyphenated 'BREAKING-CHANGE:' spelling", () => {
    const c = parseCommitMessage("chore: x\n\nBREAKING-CHANGE: dropped node 16");
    expect(c.breaking).toBe(true);
    expect(c.bump).toBe("major");
  });

  it("normalises the type to lower case", () => {
    expect(parseCommitMessage("FEAT: shout").type).toBe("feat");
  });

  it("maps recognised non-release types to a 'none' bump", () => {
    expect(parseCommitMessage("docs: tweak readme").bump).toBe("none");
    expect(parseCommitMessage("chore: bump deps").bump).toBe("none");
  });

  it("treats an unconventional message as 'none' with an empty type", () => {
    const c = parseCommitMessage("just some words");
    expect(c.type).toBe("");
    expect(c.bump).toBe("none");
    expect(c.description).toBe("just some words");
  });
});

describe("parseCommitLog", () => {
  it("splits a delimited log into individual commits", () => {
    const log = [
      "feat: a",
      "--COMMIT--",
      "fix: b",
      "--COMMIT--",
      "chore: c",
    ].join("\n");
    const commits = parseCommitLog(log);
    expect(commits.map((c) => c.type)).toEqual(["feat", "fix", "chore"]);
  });

  it("ignores blank blocks and trailing delimiters", () => {
    const log = "feat: a\n--COMMIT--\n\n--COMMIT--\nfix: b\n--COMMIT--\n";
    const commits = parseCommitLog(log);
    expect(commits.map((c) => c.type)).toEqual(["feat", "fix"]);
  });

  it("preserves multi-line bodies within a commit block", () => {
    const log = "feat: a\n\nBREAKING CHANGE: boom\n--COMMIT--\nfix: b";
    const commits = parseCommitLog(log);
    expect(commits[0]!.breaking).toBe(true);
    expect(commits[0]!.bump).toBe("major");
  });
});

describe("determineBump", () => {
  it("returns the highest-precedence bump across commits", () => {
    expect(
      determineBump([
        parseCommitMessage("fix: a"),
        parseCommitMessage("feat: b"),
        parseCommitMessage("chore: c"),
      ]),
    ).toBe("minor");
  });

  it("a single breaking change wins over everything", () => {
    expect(
      determineBump([
        parseCommitMessage("feat: a"),
        parseCommitMessage("fix(x)!: b"),
      ]),
    ).toBe("major");
  });

  it("returns 'none' when nothing is release-worthy", () => {
    expect(
      determineBump([
        parseCommitMessage("docs: a"),
        parseCommitMessage("chore: b"),
      ]),
    ).toBe("none");
  });

  it("returns 'none' for an empty commit list", () => {
    expect(determineBump([])).toBe("none");
  });
});
