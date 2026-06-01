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

Describe 'ConvertTo-SsisReadme' {
    BeforeAll {
        $script:sourceDir = Join-Path -Path $TestDrive -ChildPath 'Public'
        New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null

        function New-StubCommand
        {
            param ($Name, $Synopsis)

            $body = @"
function $Name
{
    <#
        .SYNOPSIS
            $Synopsis
    #>
    [CmdletBinding()]
    param ()
}
"@
            Set-Content -Path (Join-Path $script:sourceDir "$Name.ps1") -Value $body -Encoding UTF8
        }

        New-StubCommand -Name 'Get-SsisCatalog' -Synopsis 'Gets the catalog.'
        New-StubCommand -Name 'New-SsisCatalog' -Synopsis 'Creates the catalog.'
        New-StubCommand -Name 'Get-SsisFolder' -Synopsis 'Gets folders.'
        New-StubCommand -Name 'Set-SsisEnvironmentVariable' -Synopsis 'Sets a variable.'
        New-StubCommand -Name 'Get-SsisEnvironmentReference' -Synopsis 'Gets a reference.'

        $script:templatePath = Join-Path -Path $TestDrive -ChildPath 'README.template.md'
        Set-Content -Path $script:templatePath -Encoding UTF8 -Value @'
# Title

Intro prose.

<!-- SSIS:COMMANDS -->

## License
MIT
'@
    }

    It 'reports the total command count' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $result | Should -Match 'exposes 5 commands'
    }

    It 'collapses Environment commands under one heading' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        ([regex]::Matches($result, '(?m)^### Environment$')).Count | Should -Be 1
    }

    It 'emits the Catalog group before the Environment group' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $result.IndexOf('### Catalog') | Should -BeLessThan $result.IndexOf('### Environment')
    }

    It 'orders Get before New within a group' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $result.IndexOf('Get-SsisCatalog') | Should -BeLessThan $result.IndexOf('New-SsisCatalog')
    }

    It 'includes each synopsis next to its command' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $dash = [char]0x2014
        $result | Should -Match "\*\*Get-SsisFolder\*\* $dash Gets folders\."
    }

    It 'preserves the surrounding template prose' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $result | Should -Match '# Title'
        $result | Should -Match 'Intro prose\.'
        $result | Should -Match '## License'
    }

    It 'removes the placeholder token' {
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourceDir
        $result | Should -Not -Match 'SSIS:COMMANDS'
    }

    It 'throws when the template lacks the token' {
        $badTemplate = Join-Path -Path $TestDrive -ChildPath 'bad.md'
        Set-Content -Path $badTemplate -Value '# No token here' -Encoding UTF8
        { ConvertTo-SsisReadme -TemplatePath $badTemplate -SourcePath $script:sourceDir } |
            Should -Throw -ExpectedMessage '*SSIS:COMMANDS*'
    }

    It 'reports zero commands on an empty source folder' {
        $emptyDir = Join-Path -Path $TestDrive -ChildPath 'Empty'
        New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
        $result = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $emptyDir
        $result | Should -Match 'exposes 0 commands'
    }
}

Describe 'Update-SsisReadme' {
    BeforeAll {
        $script:srcDir = Join-Path -Path $TestDrive -ChildPath 'PublicW'
        New-Item -Path $script:srcDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $script:srcDir 'Get-SsisCatalog.ps1') -Encoding UTF8 -Value @'
function Get-SsisCatalog
{
    <#
        .SYNOPSIS
            Gets the catalog.
    #>
    [CmdletBinding()]
    param ()
}
'@
        $script:tpl = Join-Path -Path $TestDrive -ChildPath 'README.template.md'
        Set-Content -Path $script:tpl -Encoding UTF8 -Value @'
# Title
<!-- SSIS:COMMANDS -->
'@
        $script:outFile = Join-Path -Path $TestDrive -ChildPath 'README.md'
    }

    It 'writes the generated README to the output path' {
        Update-SsisReadme -TemplatePath $script:tpl -SourcePath $script:srcDir -OutputPath $script:outFile
        Test-Path -Path $script:outFile | Should -BeTrue
        Get-Content -Raw -Path $script:outFile | Should -Match 'Get-SsisCatalog'
    }

    It 'writes UTF-8 without a BOM' {
        Update-SsisReadme -TemplatePath $script:tpl -SourcePath $script:srcDir -OutputPath $script:outFile
        $bytes = [System.IO.File]::ReadAllBytes($script:outFile)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'does not write the file when -WhatIf is given' {
        $noWrite = Join-Path -Path $TestDrive -ChildPath 'whatif.md'
        Update-SsisReadme -TemplatePath $script:tpl -SourcePath $script:srcDir -OutputPath $noWrite -WhatIf
        Test-Path -Path $noWrite | Should -BeFalse
    }
}
