// Semantic Version Bumper
// Follows conventional commits and semantic versioning
// Uses TDD approach: minimal implementation for each test

const fs = require('fs');
const path = require('path');

// Parse semantic version from package.json or VERSION file
function parseVersion(filePath = 'package.json') {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Version file not found: ${filePath}`);
  }

  if (filePath.endsWith('.json')) {
    const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    if (!content.version) {
      throw new Error('No version field in ' + filePath);
    }
    return content.version;
  } else {
    return fs.readFileSync(filePath, 'utf8').trim();
  }
}

// Determine version bump type based on conventional commits
// Priority: breaking > minor > patch
function determineVersionBump(commits) {
  let hasMajor = false;
  let hasMinor = false;
  let hasPatch = false;

  for (const commit of commits) {
    const message = commit.message || '';

    // Check for breaking changes
    if (message.includes('BREAKING CHANGE:') || message.startsWith('BREAKING CHANGE:')) {
      hasMajor = true;
    }

    // Check commit type
    if (message.startsWith('feat:') || message.startsWith('feat(')) {
      hasMinor = true;
    } else if (message.startsWith('fix:') || message.startsWith('fix(')) {
      hasPatch = true;
    }
  }

  if (hasMajor) return 'major';
  if (hasMinor) return 'minor';
  if (hasPatch) return 'patch';

  return 'patch'; // Default to patch if no conventional commits found
}

// Calculate next version based on current version and bump type
function calculateNextVersion(currentVersion, bumpType) {
  const parts = currentVersion.split('.').map(Number);
  const [major, minor, patch] = parts;

  if (bumpType === 'major') {
    return `${major + 1}.0.0`;
  } else if (bumpType === 'minor') {
    return `${major}.${minor + 1}.0`;
  } else if (bumpType === 'patch') {
    return `${major}.${minor}.${patch + 1}`;
  }

  throw new Error(`Unknown bump type: ${bumpType}`);
}

// Update version in file (package.json or VERSION)
function updateVersion(newVersion, filePath = 'package.json') {
  if (filePath.endsWith('.json')) {
    const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    content.version = newVersion;
    fs.writeFileSync(filePath, JSON.stringify(content, null, 2) + '\n', 'utf8');
  } else {
    fs.writeFileSync(filePath, newVersion + '\n', 'utf8');
  }
}

// Generate changelog entry from commits
function generateChangelogEntry(version, commits) {
  const date = new Date().toISOString().split('T')[0];
  const lines = [`## [${version}] - ${date}`];

  // Categorize commits
  const features = [];
  const fixes = [];
  const breaking = [];

  for (const commit of commits) {
    const message = commit.message || '';

    // Extract breaking changes
    if (message.includes('BREAKING CHANGE:') || message.startsWith('BREAKING CHANGE:')) {
      const match = message.match(/BREAKING CHANGE:\s*(.+?)(?:\n|$)/);
      if (match) {
        breaking.push(match[1].trim());
      }
    }

    // Categorize by type
    if (message.startsWith('feat:') || message.startsWith('feat(')) {
      const description = message.replace(/^feat\(\w+\):\s*/, '').replace(/^feat:\s*/, '');
      features.push(description.split('\n')[0]);
    } else if (message.startsWith('fix:') || message.startsWith('fix(')) {
      const description = message.replace(/^fix\(\w+\):\s*/, '').replace(/^fix:\s*/, '');
      fixes.push(description.split('\n')[0]);
    }
  }

  // Format sections
  if (breaking.length > 0) {
    lines.push('');
    lines.push('### BREAKING CHANGES');
    breaking.forEach(b => lines.push(`- ${b}`));
  }

  if (features.length > 0) {
    lines.push('');
    lines.push('### Features');
    features.forEach(f => lines.push(`- ${f}`));
  }

  if (fixes.length > 0) {
    lines.push('');
    lines.push('### Bug Fixes');
    fixes.forEach(fix => lines.push(`- ${fix}`));
  }

  return lines.join('\n');
}

// Main function: run the complete version bumper
function runVersionBumper(commits, versionFile = 'package.json') {
  // Parse current version
  const currentVersion = parseVersion(versionFile);

  // Determine bump type from commits
  const bumpType = determineVersionBump(commits);

  // Calculate next version
  const newVersion = calculateNextVersion(currentVersion, bumpType);

  // Update version file
  updateVersion(newVersion, versionFile);

  // Generate changelog
  const changelog = generateChangelogEntry(newVersion, commits);

  return {
    currentVersion,
    newVersion,
    bumpType,
    changelog
  };
}

module.exports = {
  parseVersion,
  determineVersionBump,
  calculateNextVersion,
  updateVersion,
  generateChangelogEntry,
  runVersionBumper
};
