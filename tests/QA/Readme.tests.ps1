BeforeAll {
    $projectPath = "$PSScriptRoot\..\.." | Convert-Path

    # Dot-sourcing the generator defines its helper functions (e.g. ConvertTo-SsisReadme)
    # in this test scope - intentional reuse of the build-tooling helpers.
    . (Join-Path -Path $projectPath -ChildPath '.build\Build-SsisReadme.ps1')

    $script:templatePath = Join-Path -Path $projectPath -ChildPath 'README.template.md'
    $script:sourcePath   = Join-Path -Path $projectPath -ChildPath 'source\Public'
    $script:readmePath   = Join-Path -Path $projectPath -ChildPath 'README.md'
}

Describe 'README is up to date' -Tag 'Readme' {
    It 'README.md matches what the generator produces from the template' {
        $expected = ConvertTo-SsisReadme -TemplatePath $script:templatePath -SourcePath $script:sourcePath
        $actual = [System.IO.File]::ReadAllText($script:readmePath)

        # Normalize CRLF -> LF and trim trailing newline/CR so the comparison is not
        # defeated by line-ending or trailing-whitespace-only differences.
        $normalize = { param ($text) ($text -replace "`r`n", "`n").TrimEnd("`r", "`n") }

        (& $normalize $actual) | Should -BeExactly (& $normalize $expected) -Because 'run ./build.ps1 -Tasks Generate_Readme and commit README.md'
    }
}
