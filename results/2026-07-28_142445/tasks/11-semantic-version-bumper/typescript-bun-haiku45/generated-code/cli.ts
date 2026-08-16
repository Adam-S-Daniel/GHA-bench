import { promises as fs } from "fs";
import { exec } from "child_process";
import { promisify } from "util";
import {
  bumpSemanticVersion,
  CommitType,
  Commit,
  parseVersion,
} from "./version-bumper";

const execAsync = promisify(exec);

// Parse conventional commit message and extract type
function parseCommitType(message: string): CommitType {
  if (message.includes("!:") || message.startsWith("feat!")) {
    return CommitType.BREAKING;
  }
  if (message.startsWith("feat")) {
    return CommitType.FEAT;
  }
  if (message.startsWith("fix")) {
    return CommitType.FIX;
  }
  return CommitType.OTHER;
}

// Extract commits from git log
// Format: get all commits between HEAD and a tag/ref, or just recent commits
async function getCommitsSinceLast(): Promise<Commit[]> {
  try {
    // Get the last tag, or use a wide range
    let range = "HEAD~10..HEAD";

    try {
      const { stdout } = await execAsync("git describe --tags --abbrev=0");
      if (stdout.trim()) {
        range = `${stdout.trim()}..HEAD`;
      }
    } catch {
      // No tags found, use recent commits
    }

    // Get commit messages
    const { stdout } = await execAsync(
      `git log ${range} --format=%B --no-merges`
    );

    const messages = stdout
      .split("\n")
      .map((msg) => msg.trim())
      .filter((msg) => msg.length > 0 && !msg.startsWith("Author:"));

    return messages.map((message) => ({
      message,
      type: parseCommitType(message),
    }));
  } catch (error) {
    console.error("Failed to get commits from git:", error);
    throw new Error("Could not parse git commits");
  }
}

// Load fixture commits from a file (for testing)
async function loadFixtureCommits(fixturePath: string): Promise<Commit[]> {
  try {
    const content = await fs.readFile(fixturePath, "utf-8");
    const lines = content.split("\n").filter((line) => line.trim());
    return lines.map((line) => ({
      message: line,
      type: parseCommitType(line),
    }));
  } catch (error) {
    console.error(`Failed to load fixture from ${fixturePath}:`, error);
    return [];
  }
}

// Main CLI function
async function main() {
  const args = Bun.argv.slice(2);
  const command = args[0];

  if (command === "--help" || command === "-h") {
    console.log(`Usage: bun run cli.ts [options]

Options:
  bump [--fixture <path>]   Bump version based on commits
  --fixture <path>          Load commits from fixture file instead of git log
  --help, -h                Show this help message

Example:
  bun run cli.ts bump
  bun run cli.ts bump --fixture commits.txt
`);
    return;
  }

  if (command === "bump") {
    try {
      const fixtureIndex = args.indexOf("--fixture");
      let commits: Commit[];

      if (fixtureIndex !== -1 && args[fixtureIndex + 1]) {
        commits = await loadFixtureCommits(args[fixtureIndex + 1]);
      } else {
        commits = await getCommitsSinceLast();
      }

      if (commits.length === 0) {
        console.error("No commits found to bump version");
        process.exit(1);
      }

      const packageJsonPath = "package.json";
      const result = await bumpSemanticVersion(packageJsonPath, commits);

      console.log(JSON.stringify(result, null, 2));

      // Also write changelog to file
      const changelogPath = "CHANGELOG.md";
      try {
        const existing = await fs.readFile(changelogPath, "utf-8");
        await fs.writeFile(changelogPath, result.changelog + "\n" + existing);
      } catch {
        // File doesn't exist, create it
        await fs.writeFile(changelogPath, result.changelog);
      }

      console.log(`\n✓ Version bumped from ${result.oldVersion} to ${result.newVersion}`);
      console.log(`✓ Changelog updated`);
      console.log(`✓ package.json updated`);
    } catch (error) {
      console.error("Error:", error instanceof Error ? error.message : error);
      process.exit(1);
    }
  } else {
    console.error(`Unknown command: ${command}`);
    console.error("Use --help for usage information");
    process.exit(1);
  }
}

main();
