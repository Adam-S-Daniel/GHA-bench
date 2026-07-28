import { expect, describe, it } from "bun:test";
import { parseCommit, determineBumpType, Commit } from "./commits";

describe("parseCommit", () => {
  it("should parse a feat commit", () => {
    const commit: Commit = {
      hash: "abc123",
      message: "feat: add new feature",
      body: "",
    };
    const result = parseCommit(commit);
    expect(result).toBe("minor");
  });

  it("should parse a fix commit", () => {
    const commit: Commit = {
      hash: "def456",
      message: "fix: resolve bug",
      body: "",
    };
    const result = parseCommit(commit);
    expect(result).toBe("patch");
  });

  it("should detect breaking change in commit", () => {
    const commit: Commit = {
      hash: "ghi789",
      message: "feat: new API endpoint",
      body: "BREAKING CHANGE: old endpoint removed",
    };
    const result = parseCommit(commit);
    expect(result).toBe("major");
  });

  it("should detect breaking change in message", () => {
    const commit: Commit = {
      hash: "jkl012",
      message: "feat!: redesign API",
      body: "",
    };
    const result = parseCommit(commit);
    expect(result).toBe("major");
  });

  it("should treat unknown type as patch", () => {
    const commit: Commit = {
      hash: "xyz999",
      message: "docs: update readme",
      body: "",
    };
    const result = parseCommit(commit);
    expect(result).toBe("patch");
  });
});

describe("determineBumpType", () => {
  it("should return major if any commit requires major bump", () => {
    const commits = [
      { hash: "a", message: "fix: minor fix", body: "" },
      { hash: "b", message: "feat: new feature", body: "" },
      { hash: "c", message: "feat!: breaking change", body: "" },
    ];
    expect(determineBumpType(commits)).toBe("major");
  });

  it("should return minor if highest is minor", () => {
    const commits = [
      { hash: "a", message: "fix: minor fix", body: "" },
      { hash: "b", message: "feat: new feature", body: "" },
    ];
    expect(determineBumpType(commits)).toBe("minor");
  });

  it("should return patch if only patches", () => {
    const commits = [
      { hash: "a", message: "fix: minor fix", body: "" },
      { hash: "b", message: "docs: update docs", body: "" },
    ];
    expect(determineBumpType(commits)).toBe("patch");
  });

  it("should return patch for empty commit list", () => {
    expect(determineBumpType([])).toBe("patch");
  });
});
