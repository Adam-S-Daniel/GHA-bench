BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "ver1.txt" {
    It "Returns expected output" {
        ver1.txt | Should -Be "YOUR_EXPECTED_VALUE"
    }
}
