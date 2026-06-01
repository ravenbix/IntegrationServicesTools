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
}

Describe 'Get-SsisReadmeGroupRank / Get-SsisReadmeVerbRank' {
    It 'orders known groups in workflow precedence' {
        (Get-SsisReadmeGroupRank -Group 'Catalog') |
            Should -BeLessThan (Get-SsisReadmeGroupRank -Group 'Project')
    }

    It 'ranks unknown groups after known ones' {
        (Get-SsisReadmeGroupRank -Group 'Catalog') |
            Should -BeLessThan (Get-SsisReadmeGroupRank -Group 'Zebra')
    }

    It 'orders Get before Remove' {
        (Get-SsisReadmeVerbRank -Verb 'Get') |
            Should -BeLessThan (Get-SsisReadmeVerbRank -Verb 'Remove')
    }
}
