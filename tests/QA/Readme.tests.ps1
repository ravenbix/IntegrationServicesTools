BeforeAll {
    $projectPath = "$PSScriptRoot\..\.." | Convert-Path

    . (Join-Path -Path $projectPath -ChildPath '.build\Build-SsisReadme.ps1')

    $script:templatePath = Join-Path -Path $projectPath -ChildPath 'README.template.md'
    $script:sourcePath   = Join-Path -Path $projectPath -ChildPath 'source\Public'
    $script:readmePath   = Join-Path -Path $projectPath -ChildPath 'README.md'
}

Describe 'README is up to date' -Tag 'Readme' {
    It 'README.md matches what the generator produces from the template' {
        $expected = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourcePath
        $actual = [System.IO.File]::ReadAllText((Convert-Path -Path $script:readmePath))

        # Normalize line endings so the comparison is not defeated by CRLF/LF differences.
        $normalize = { param ($text) ($text -replace "`r`n", "`n").TrimEnd("`n") }

        (& $normalize $actual) | Should -BeExactly (& $normalize $expected) -Because 'run ./build.ps1 -Tasks Generate_Readme and commit README.md'
    }
}
