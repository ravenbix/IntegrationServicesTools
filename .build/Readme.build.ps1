<#
    .SYNOPSIS
        Invoke-Build task that regenerates README.md from README.template.md.

    .DESCRIPTION
        Dot-sources the README generator and rewrites README.md from the template and
        the public command sources, so the command reference can never drift.
#>

task Generate_Readme {
    . (Join-Path -Path $BuildRoot -ChildPath '.build\Build-SsisReadme.ps1')

    $splatReadme = @{
        TemplatePath = Join-Path -Path $BuildRoot -ChildPath 'README.template.md'
        SourcePath   = Join-Path -Path $BuildRoot -ChildPath 'source\Public'
        OutputPath   = Join-Path -Path $BuildRoot -ChildPath 'README.md'
    }

    Write-Build -Color 'Green' -Text 'Regenerating README.md from template'

    Update-SsisReadme @splatReadme -Confirm:$false
}
