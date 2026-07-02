# MockArtifacts.psm1
# Provides mock artifact metadata for demoing/testing the cleanup script
# without needing a real GitHub Actions API connection.

function Get-MockArtifacts {
    <#
    .SYNOPSIS
        Returns a fixed, deterministic set of mock artifacts relative to $Now.
    #>
    param(
        [DateTime]$Now = (Get-Date)
    )

    @(
        [PSCustomObject]@{ Name = 'build-logs-101'; SizeBytes = 52428800;  CreatedAt = $Now.AddDays(-2);  WorkflowRunId = 'run-1001' }
        [PSCustomObject]@{ Name = 'build-logs-102'; SizeBytes = 52428800;  CreatedAt = $Now.AddDays(-3);  WorkflowRunId = 'run-1001' }
        [PSCustomObject]@{ Name = 'build-logs-103'; SizeBytes = 52428800;  CreatedAt = $Now.AddDays(-4);  WorkflowRunId = 'run-1001' }
        [PSCustomObject]@{ Name = 'test-report-201'; SizeBytes = 104857600; CreatedAt = $Now.AddDays(-10); WorkflowRunId = 'run-1002' }
        [PSCustomObject]@{ Name = 'test-report-202'; SizeBytes = 104857600; CreatedAt = $Now.AddDays(-45); WorkflowRunId = 'run-1002' }
        [PSCustomObject]@{ Name = 'coverage-301'; SizeBytes = 20971520;   CreatedAt = $Now.AddDays(-60); WorkflowRunId = 'run-1003' }
        [PSCustomObject]@{ Name = 'release-401'; SizeBytes = 209715200;  CreatedAt = $Now.AddDays(-1);  WorkflowRunId = 'run-1004' }
    )
}

Export-ModuleMember -Function Get-MockArtifacts
