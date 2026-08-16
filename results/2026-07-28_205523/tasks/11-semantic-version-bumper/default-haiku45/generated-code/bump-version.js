#!/usr/bin/env node

// CLI for semantic version bumper
// Reads git commits, determines version bump, and updates version file

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const {
  parseVersion,
  determineVersionBump,
  calculateNextVersion,
  updateVersion,
  generateChangelogEntry
} = require('./version-bumper');

function getGitCommits(fromRef = 'HEAD~10..HEAD') {
  try {
    const output = execSync(`git log ${fromRef} --format=%B%n---END---`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore']
    });

    if (!output.trim()) {
      return [];
    }

    const commits = output
      .split('---END---')
      .filter(msg => msg.trim())
      .map(msg => ({
        message: msg.trim()
      }));

    return commits;
  } catch (error) {
    console.error('Error reading git commits:', error.message);
    return [];
  }
}

function main() {
  const args = process.argv.slice(2);
  const versionFile = args[0] || 'package.json';
  const fromRef = args[1] || 'HEAD~10..HEAD';

  // Check if version file exists
  if (!fs.existsSync(versionFile)) {
    console.error(`Error: Version file not found: ${versionFile}`);
    process.exit(1);
  }

  // Parse current version
  let currentVersion;
  try {
    currentVersion = parseVersion(versionFile);
  } catch (error) {
    console.error('Error parsing version:', error.message);
    process.exit(1);
  }

  console.log(`Current version: ${currentVersion}`);

  // Get commits
  const commits = getGitCommits(fromRef);

  if (commits.length === 0) {
    console.log('No commits found, skipping version bump');
    console.log(`Version: ${currentVersion}`);
    process.exit(0);
  }

  console.log(`Found ${commits.length} commit(s)`);

  // Determine bump type
  const bumpType = determineVersionBump(commits);
  console.log(`Bump type: ${bumpType}`);

  // Calculate next version
  const newVersion = calculateNextVersion(currentVersion, bumpType);
  console.log(`New version: ${newVersion}`);

  // Update version file
  updateVersion(newVersion, versionFile);
  console.log(`Updated ${versionFile}`);

  // Generate changelog
  const changelog = generateChangelogEntry(newVersion, commits);
  console.log('\n=== Changelog ===');
  console.log(changelog);
  console.log('=== End Changelog ===\n');

  console.log(`Version bumped: ${currentVersion} -> ${newVersion}`);
}

main();
