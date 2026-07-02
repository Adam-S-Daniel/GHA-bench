# RED -> GREEN cycle for commit log parsing and bump-type classification.
BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
    $fixturesDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'Get-CommitMessages' {
    It 'splits a mock commit log fixture into individual commit messages' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-feat.txt')
        $messages.Count | Should -Be 3
        $messages[0] | Should -Be 'feat(auth): add OAuth2 login support'
        $messages[1] | Should -Be 'fix(auth): correct token refresh race condition'
    }

    It 'preserves multi-line commit bodies (e.g. BREAKING CHANGE footers)' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-breaking.txt')
        $messages.Count | Should -Be 3
        $messages[2] | Should -Match 'BREAKING CHANGE'
    }

    It 'throws a meaningful error when the commit log file does not exist' {
        { Get-CommitMessages -Path (Join-Path $fixturesDir 'nope.txt') } | Should -Throw '*not found*'
    }
}

Describe 'Get-CommitBumpType' {
    It 'returns "major" when any commit has a BREAKING CHANGE footer or "!" marker' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-breaking.txt')
        Get-CommitBumpType -Messages $messages | Should -Be 'major'
    }

    It 'returns "minor" when the highest-impact commit is a feat' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-feat.txt')
        Get-CommitBumpType -Messages $messages | Should -Be 'minor'
    }

    It 'returns "patch" when the highest-impact commit is a fix' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-fix.txt')
        Get-CommitBumpType -Messages $messages | Should -Be 'patch'
    }

    It 'returns "none" when there are no feat/fix/breaking commits' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-none.txt')
        Get-CommitBumpType -Messages $messages | Should -Be 'none'
    }

    It 'throws a meaningful error when given an empty commit list' {
        { Get-CommitBumpType -Messages @() } | Should -Throw '*commit*'
    }
}
