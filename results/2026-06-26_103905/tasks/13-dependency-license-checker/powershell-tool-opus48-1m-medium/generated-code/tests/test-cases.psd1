@{
    # Workflow act test cases. Shared by BeforeDiscovery (for -ForEach) and
    # BeforeAll (for the act execution loop) in Workflow.Tests.ps1 so the data
    # is defined exactly once.
    Cases = @(
        @{
            Name     = 'mixed-package-json'
            Manifest = 'fixtures/package.json'
            Expected = @(
                'RESULT name=express version=4.18.2 scope=prod license=MIT status=Approved'
                'RESULT name=evil-lib version=2.0.0 scope=prod license=GPL-3.0 status=Denied'
                'RESULT name=unknown-pkg version=0.0.1 scope=dev license=UNKNOWN status=Unknown'
                'SUMMARY approved=1 denied=1 unknown=1 total=3'
                'COMPLIANCE FAIL'
            )
        }
        @{
            Name     = 'clean-requirements'
            Manifest = 'fixtures/requirements.txt'
            Expected = @(
                'RESULT name=requests version=2.31.0 scope=prod license=Apache-2.0 status=Approved'
                'RESULT name=flask version=2.3.0 scope=prod license=BSD-3-Clause status=Approved'
                'RESULT name=numpy version=1.24.0 scope=prod license=BSD-3-Clause status=Approved'
                'SUMMARY approved=3 denied=0 unknown=0 total=3'
                'COMPLIANCE PASS'
            )
        }
    )
}
