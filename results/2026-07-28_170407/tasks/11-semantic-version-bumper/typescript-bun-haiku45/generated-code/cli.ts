import * as fs from "fs";
import * as path from "path";
import {
  parseVersion,
  bumpVersion,
  updateVersion,
  parseGitLog,
} from "./version-bumper";

interface CLIOptions {
  packageJsonPath: string;
  updateFile: boolean;
  updateChangelog: boolean;
}

function getGitLog(baseBranch: string = "origin/main"): string {
  try {
    const proc = Bun.spawnSync(["git", "log", "--oneline", `${baseBranch}..HEAD`], {
      stdio: ["ignore", "pipe", "ignore"],
    });
    if (proc.success && proc.stdout) {
      return new TextDecoder().decode(proc.stdout);
    }
    return "";
  } catch {
    return "";
  }
}

function main(): void {
  const args = process.argv.slice(2);
  const options: CLIOptions = {
    packageJsonPath: "package.json",
    updateFile: false,
    updateChangelog: false,
  };

  // Parse CLI arguments
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--package-json" && args[i + 1]) {
      options.packageJsonPath = args[i + 1];
      i++;
    } else if (args[i] === "--update") {
      options.updateFile = true;
    } else if (args[i] === "--update-changelog") {
      options.updateChangelog = true;
    }
  }

  try {
    // Parse current version
    const currentVersion = parseVersion(options.packageJsonPath);
    console.log(`Current version: ${currentVersion}`);

    // Get git log
    const gitLog = getGitLog();
    const commits = parseGitLog(gitLog);

    if (commits.length === 0) {
      console.log("No conventional commits found");
      console.log(currentVersion);
      return;
    }

    // Bump version
    const result = bumpVersion(currentVersion, commits);
    console.log(`New version: ${result.newVersion}`);
    console.log(`Change type: ${result.changeType}`);

    if (options.updateFile) {
      const changelogContent = options.updateChangelog ? result.changelog : undefined;
      updateVersion(options.packageJsonPath, result.newVersion, changelogContent);
      console.log("Version file updated");
    }

    if (options.updateChangelog && !options.updateFile) {
      const changelogPath = path.join(
        path.dirname(options.packageJsonPath),
        "CHANGELOG.md"
      );
      if (fs.existsSync(changelogPath)) {
        const existing = fs.readFileSync(changelogPath, "utf-8");
        fs.writeFileSync(changelogPath, result.changelog + "\n" + existing);
      } else {
        fs.writeFileSync(
          changelogPath,
          "# Changelog\n\n" + result.changelog
        );
      }
      console.log("Changelog updated");
    }

    // Output new version
    console.log(result.newVersion);
  } catch (error) {
    console.error("Error:", error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

main();
