BeforeAll {
    $script:projectPath = "$PSScriptRoot\..\.." | Convert-Path
    . (Join-Path -Path $script:projectPath -ChildPath '.build\Build-SsisReadme.ps1')
}

Describe 'Get-SsisReadmeNounGroup' {
    It 'returns the noun after the Ssis prefix' {
        Get-SsisReadmeNounGroup -CommandName 'Get-SsisFolder' | Should -BeExactly 'Folder'
    }

    It 'collapses EnvironmentVariable under Environment' {
        Get-SsisReadmeNounGroup -CommandName 'Set-SsisEnvironmentVariable' | Should -BeExactly 'Environment'
    }

    It 'collapses EnvironmentReference under Environment' {
        Get-SsisReadmeNounGroup -CommandName 'New-SsisEnvironmentReference' | Should -BeExactly 'Environment'
    }

    It 'keeps a plain Environment noun as Environment' {
        Get-SsisReadmeNounGroup -CommandName 'Get-SsisEnvironment' | Should -BeExactly 'Environment'
    }
}

Describe 'Get-SsisReadmeGroupRank' {
    It 'orders known groups in workflow precedence' {
        (Get-SsisReadmeGroupRank -Group 'Catalog') |
            Should -BeLessThan (Get-SsisReadmeGroupRank -Group 'Project')
    }

    It 'ranks unknown groups after known ones' {
        (Get-SsisReadmeGroupRank -Group 'Catalog') |
            Should -BeLessThan (Get-SsisReadmeGroupRank -Group 'Zebra')
    }

    It 'ranks Catalog first (0)' {
        Get-SsisReadmeGroupRank -Group 'Catalog' | Should -Be 0
    }
}

Describe 'Get-SsisReadmeVerbRank' {
    It 'orders Get before Remove' {
        (Get-SsisReadmeVerbRank -Verb 'Get') |
            Should -BeLessThan (Get-SsisReadmeVerbRank -Verb 'Remove')
    }

    It 'ranks Get first (0)' {
        Get-SsisReadmeVerbRank -Verb 'Get' | Should -Be 0
    }
}
