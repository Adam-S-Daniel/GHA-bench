const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Parse semantic version from package.json or VERSION file
function parseVersion(filePath) {
  const ext = path.extname(filePath);

  if (ext === '.json') {
    const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return content.version;
  }

  // For VERSION file or plain text
  return fs.readFileSync(filePath, 'utf8').trim();
}

// Parse conventional commit message to extract type and scope
function parseConventionalCommit(message) {
  // Pattern: type(scope): message or type!: message for breaking changes
  const regex = /^(feat|fix|docs|style|refactor|perf|test|chore|ci)(\(.+\))?(!)?:/;
  const match = message.match(regex);

  if (!match) {
    return null;
  }

  const type = match[1];
  const isBreaking = !!match[3];

  return {
    type,
    isBreaking,
    message: message.substring(match[0].length).trim(),
  };
}

// Get commits since a certain ref with conventional commit format
function getConventionalCommits(sinceRef) {
  try {
    const output = execSync(`git log ${sinceRef}..HEAD --pretty=format:%s`, {
      encoding: 'utf8',
    });

    if (!output.trim()) {
      return [];
    }

    return output
      .split('\n')
      .filter(line => line.trim())
      .map(message => {
        const parsed = parseConventionalCommit(message);
        return parsed || { type: 'chore', message, isBreaking: false };
      })
      .filter(c => c.type !== null);
  } catch (error) {
    // If sinceRef doesn't exist, try all commits
    if (error.message.includes('unknown revision')) {
      const output = execSync('git log --pretty=format:%s', { encoding: 'utf8' });
      return output
        .split('\n')
        .filter(line => line.trim())
        .map(message => {
          const parsed = parseConventionalCommit(message);
          return parsed || { type: 'chore', message, isBreaking: false };
        })
        .filter(c => c.type !== null);
    }
    throw error;
  }
}

// Determine the next version based on commits
function getNextVersion(currentVersion, commits) {
  const [major, minor, patch] = currentVersion.split('.').map(Number);

  // Determine the type of bump needed
  let bumpType = 'none'; // none, patch, minor, major

  for (const commit of commits) {
    // Check for breaking changes (indicated by isBreaking flag or ! in type)
    if (commit.isBreaking) {
      bumpType = 'major';
      break;
    }

    if (commit.type === 'feat' && bumpType !== 'major') {
      bumpType = 'minor';
    }

    if (commit.type === 'fix' && bumpType === 'none') {
      bumpType = 'patch';
    }
  }

  // Calculate new version
  if (bumpType === 'major') {
    return `${major + 1}.0.0`;
  }

  if (bumpType === 'minor') {
    return `${major}.${minor + 1}.0`;
  }

  if (bumpType === 'patch') {
    return `${major}.${minor}.${patch + 1}`;
  }

  return currentVersion;
}

// Update version in package.json or VERSION file
function updateVersionFile(filePath, newVersion) {
  const ext = path.extname(filePath);

  if (ext === '.json') {
    const content = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    content.version = newVersion;
    fs.writeFileSync(filePath, JSON.stringify(content, null, 2) + '\n', 'utf8');
  } else {
    fs.writeFileSync(filePath, `${newVersion}\n`, 'utf8');
  }
}

// Generate changelog entry from commits
function generateChangelog(version, commits) {
  const features = commits.filter(c => c.type === 'feat').map(c => c.message);
  const fixes = commits.filter(c => c.type === 'fix').map(c => c.message);

  let changelog = `## ${version}\n\n`;

  if (features.length > 0) {
    changelog += '### Features\n';
    features.forEach(f => {
      changelog += `- ${f}\n`;
    });
    changelog += '\n';
  }

  if (fixes.length > 0) {
    changelog += '### Bug Fixes\n';
    fixes.forEach(f => {
      changelog += `- ${f}\n`;
    });
    changelog += '\n';
  }

  return changelog;
}

// Main function to bump version
function bumpVersion(versionFilePath, fromRef = 'HEAD~10') {
  try {
    // Parse current version
    const currentVersion = parseVersion(versionFilePath);

    // Get commits since ref
    const commits = getConventionalCommits(fromRef);

    if (commits.length === 0) {
      return {
        currentVersion,
        newVersion: currentVersion,
        commits: [],
        changelog: 'No commits to process\n',
      };
    }

    // Calculate next version
    const newVersion = getNextVersion(currentVersion, commits);

    // Update version file
    updateVersionFile(versionFilePath, newVersion);

    // Generate changelog
    const changelog = generateChangelog(newVersion, commits);

    return {
      currentVersion,
      newVersion,
      commits,
      changelog,
    };
  } catch (error) {
    throw new Error(`Failed to bump version: ${error.message}`);
  }
}

module.exports = {
  parseVersion,
  getNextVersion,
  updateVersionFile,
  generateChangelog,
  getConventionalCommits,
  bumpVersion,
};
