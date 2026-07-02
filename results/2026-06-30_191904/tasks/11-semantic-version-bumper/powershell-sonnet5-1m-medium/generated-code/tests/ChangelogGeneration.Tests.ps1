BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'scripts' 'VersionBumper.psm1'
    Import-Module $modulePath -Force
    $fixturesDir = Join-Path $PSScriptRoot 'fixtures'
}

Describe 'New-ChangelogEntry' {
    It 'groups commits under Breaking/Features/Fixes headings for a given version and date' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-breaking.txt')
        $entry = New-ChangelogEntry -Version '2.0.0' -Date '2026-07-01' -Messages $messages

        $entry | Should -Match '## \[2\.0\.0\] - 2026-07-01'
        $entry | Should -Match '### Breaking Changes'
        $entry | Should -Match 'remove deprecated v1 endpoints'
        $entry | Should -Match '### Fixes'
        $entry | Should -Match 'correct token refresh race condition'
    }

    It 'omits headings for categories with no matching commits' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-fix.txt')
        $entry = New-ChangelogEntry -Version '1.2.4' -Date '2026-07-01' -Messages $messages

        $entry | Should -Not -Match '### Breaking Changes'
        $entry | Should -Not -Match '### Features'
        $entry | Should -Match '### Fixes'
    }

    It 'produces a "no notable changes" entry when there are no release-worthy commits' {
        $messages = Get-CommitMessages -Path (Join-Path $fixturesDir 'commits-none.txt')
        $entry = New-ChangelogEntry -Version '1.2.3' -Date '2026-07-01' -Messages $messages

        $entry | Should -Match 'No notable changes'
    }
}
