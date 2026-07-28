// Integration tests for the complete semantic version bumper workflow

import { expect, test, describe, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { commitExec } from "./test-fixtures";

describe("Integration: Complete version bumping workflow", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync("/tmp/semver-integration-");
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  test("should bump from 1.0.0 to 1.1.0 with feature commit", () => {
    // Initialize git repo
    commitExec("git init", tempDir);
    commitExec("git config user.email test@test.com", tempDir);
    commitExec("git config user.name Test", tempDir);

    // Create package.json with version 1.0.0
    const pkgPath = join(tempDir, "package.json");
    writeFileSync(
      pkgPath,
      JSON.stringify({ name: "test", version: "1.0.0" }, null, 2)
    );
    commitExec("git add package.json", tempDir);
    commitExec("git commit -m 'initial: setup'", tempDir);
    commitExec("git tag v1.0.0", tempDir);

    // Add a feature commit
    commitExec("mkdir -p src", tempDir);
    writeFileSync(
      join(tempDir, "src/feature.ts"),
      "export function newFeature() {}"
    );
    commitExec("git add src/feature.ts", tempDir);
    commitExec("git commit -m 'feat: add new feature'", tempDir);

    // Run the version bumper
    const scriptPath = join(
      process.cwd(),
      "src/index.ts"
    );
    const result = commitExec(
      `bun ${scriptPath} --version-file package.json --previous-tag v1.0.0`,
      tempDir
    );

    expect(result).toContain("::VERSION::1.1.0");

    // Verify package.json was updated
    const pkg = JSON.parse(readFileSync(pkgPath, "utf-8"));
    expect(pkg.version).toBe("1.1.0");
  });

  test("should bump from 1.0.0 to 1.0.1 with fix commit", () => {
    // Initialize git repo
    commitExec("git init", tempDir);
    commitExec("git config user.email test@test.com", tempDir);
    commitExec("git config user.name Test", tempDir);

    // Create package.json
    const pkgPath = join(tempDir, "package.json");
    writeFileSync(
      pkgPath,
      JSON.stringify({ name: "test", version: "1.0.0" }, null, 2)
    );
    commitExec("git add package.json", tempDir);
    commitExec("git commit -m 'initial: setup'", tempDir);
    commitExec("git tag v1.0.0", tempDir);

    // Add a fix commit
    commitExec("mkdir -p src", tempDir);
    writeFileSync(
      join(tempDir, "src/bug.ts"),
      "export function fixedBug() {}"
    );
    commitExec("git add src/bug.ts", tempDir);
    commitExec("git commit -m 'fix: resolve critical bug'", tempDir);

    // Run the version bumper
    const scriptPath = join(
      process.cwd(),
      "src/index.ts"
    );
    const result = commitExec(
      `bun ${scriptPath} --version-file package.json --previous-tag v1.0.0`,
      tempDir
    );

    expect(result).toContain("::VERSION::1.0.1");

    const pkg = JSON.parse(readFileSync(pkgPath, "utf-8"));
    expect(pkg.version).toBe("1.0.1");
  });

  test("should bump from 1.0.0 to 2.0.0 with breaking change", () => {
    // Initialize git repo
    commitExec("git init", tempDir);
    commitExec("git config user.email test@test.com", tempDir);
    commitExec("git config user.name Test", tempDir);

    // Create package.json
    const pkgPath = join(tempDir, "package.json");
    writeFileSync(
      pkgPath,
      JSON.stringify({ name: "test", version: "1.0.0" }, null, 2)
    );
    commitExec("git add package.json", tempDir);
    commitExec("git commit -m 'initial: setup'", tempDir);
    commitExec("git tag v1.0.0", tempDir);

    // Add a breaking change commit
    commitExec("mkdir -p src", tempDir);
    writeFileSync(
      join(tempDir, "src/api.ts"),
      "export function newAPI() {}"
    );
    commitExec("git add src/api.ts", tempDir);
    commitExec(
      "git commit -m 'feat!: remove deprecated API' -m 'BREAKING CHANGE: old API no longer supported'",
      tempDir
    );

    // Run the version bumper
    const scriptPath = join(
      process.cwd(),
      "src/index.ts"
    );
    const result = commitExec(
      `bun ${scriptPath} --version-file package.json --previous-tag v1.0.0`,
      tempDir
    );

    expect(result).toContain("::VERSION::2.0.0");

    const pkg = JSON.parse(readFileSync(pkgPath, "utf-8"));
    expect(pkg.version).toBe("2.0.0");
  });
});
