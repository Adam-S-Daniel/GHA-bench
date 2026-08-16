#!/usr/bin/env python3
"""
Test fixtures: mock commit logs and test data for integration tests.
"""

# Test case 1: Simple patch bump
FIXTURE_FIX_ONLY = {
    "name": "Fix only - patch bump",
    "current_version": "1.0.0",
    "commits": [
        {
            "type": "fix",
            "message": "fix: handle edge case in parser"
        }
    ],
    "expected_version": "1.0.1",
    "expected_changelog_has": ["Bug Fixes", "edge case in parser"]
}

# Test case 2: Feature added - minor bump
FIXTURE_FEAT_ONLY = {
    "name": "Feature only - minor bump",
    "current_version": "2.0.0",
    "commits": [
        {
            "type": "feat",
            "message": "feat: add async support"
        }
    ],
    "expected_version": "2.1.0",
    "expected_changelog_has": ["Features", "async support"]
}

# Test case 3: Breaking change - major bump
FIXTURE_BREAKING_CHANGE = {
    "name": "Breaking change - major bump",
    "current_version": "1.5.3",
    "commits": [
        {
            "type": "feat",
            "message": "feat!: redesign API endpoints",
            "breaking": True
        }
    ],
    "expected_version": "2.0.0",
    "expected_changelog_has": ["redesign API endpoints"]
}

# Test case 4: Mixed commits - highest priority wins
FIXTURE_MIXED_COMMITS = {
    "name": "Mixed commits - minor wins over patch",
    "current_version": "1.2.0",
    "commits": [
        {
            "type": "fix",
            "message": "fix: memory leak in cache"
        },
        {
            "type": "feat",
            "message": "feat: add caching layer"
        },
        {
            "type": "docs",
            "message": "docs: update readme"
        }
    ],
    "expected_version": "1.3.0",
    "expected_changelog_has": ["Features", "caching layer", "Bug Fixes", "memory leak"]
}

# Test case 5: No functional changes
FIXTURE_NO_FUNCTIONAL_CHANGES = {
    "name": "No functional changes - no bump",
    "current_version": "3.0.0",
    "commits": [
        {
            "type": "chore",
            "message": "chore: update dependencies"
        },
        {
            "type": "docs",
            "message": "docs: add examples"
        }
    ],
    "expected_version": "3.0.0",
    "expected_changelog_has": []  # No changelog for non-functional
}

# Test case 6: Complex breaking change with details
FIXTURE_BREAKING_WITH_BODY = {
    "name": "Breaking change with detailed body",
    "current_version": "0.9.0",
    "commits": [
        {
            "type": "feat",
            "message": "feat: reorganize module structure\n\nBREAKING CHANGE: Old import paths no longer work",
            "breaking": True
        }
    ],
    "expected_version": "1.0.0",
    "expected_changelog_has": ["reorganize module structure"]
}

# Test case 7: Multiple features and fixes
FIXTURE_MANY_COMMITS = {
    "name": "Many commits with multiple types",
    "current_version": "1.0.0",
    "commits": [
        {"type": "feat", "message": "feat: add JSON export"},
        {"type": "feat", "message": "feat: add XML support"},
        {"type": "fix", "message": "fix: parsing error on empty input"},
        {"type": "fix", "message": "fix: memory optimization"},
        {"type": "chore", "message": "chore: refactor tests"},
    ],
    "expected_version": "1.1.0",
    "expected_changelog_has": [
        "Features",
        "JSON export",
        "XML support",
        "Bug Fixes",
        "parsing error",
        "memory optimization"
    ]
}

ALL_FIXTURES = [
    FIXTURE_FIX_ONLY,
    FIXTURE_FEAT_ONLY,
    FIXTURE_BREAKING_CHANGE,
    FIXTURE_MIXED_COMMITS,
    FIXTURE_NO_FUNCTIONAL_CHANGES,
    FIXTURE_BREAKING_WITH_BODY,
    FIXTURE_MANY_COMMITS,
]
