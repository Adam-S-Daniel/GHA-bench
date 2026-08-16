BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe "ver_upd.txt" {
    It "Returns expected output" {
        ver_upd.txt | Should -Be "YOUR_EXPECTED_VALUE"
    }
}
