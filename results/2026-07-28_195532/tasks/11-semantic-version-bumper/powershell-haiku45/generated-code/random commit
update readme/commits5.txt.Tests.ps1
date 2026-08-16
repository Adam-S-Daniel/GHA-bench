BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "commits5.txt" {
    It "Returns expected output" {
        commits5.txt | Should -Be "YOUR_EXPECTED_VALUE"
    }
}
