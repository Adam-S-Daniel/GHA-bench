BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "ver_bak.txt" {
    It "Returns expected output" {
        ver_bak.txt | Should -Be "YOUR_EXPECTED_VALUE"
    }
}
