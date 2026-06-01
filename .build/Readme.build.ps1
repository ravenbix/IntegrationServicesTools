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

    Write-Build Green 'Regenerating README.md from template'

    Update-SsisReadme @splatReadme -Confirm:$false
}

<#
    .SYNOPSIS
        Invoke-Build task that fails when the committed README.md is out of date.

    .DESCRIPTION
        Runs in the build workflow immediately after Generate_Readme. Because
        Generate_Readme rewrites README.md in place, the QA Pester test can never
        observe a stale committed copy. This task closes that gap by comparing the
        freshly regenerated working-tree README.md against the committed copy with
        'git diff'; any difference means README.md was regenerated but the committed
        copy is stale or uncommitted, and the build fails. The check is skipped (with
        a warning) when git is unavailable or this is not a git work tree, so it does
        not crash builds run outside a repository.
#>

task Assert_Readme_Clean {
    if (-not (Get-Command -Name git -ErrorAction SilentlyContinue))
    {
        Write-Build Yellow 'Skipping README clean check: git command not found.'

        return
    }

    $insideWorkTree = (& git rev-parse --is-inside-work-tree 2>$null)

    if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne 'true')
    {
        Write-Build Yellow 'Skipping README clean check: not a git work tree.'

        return
    }

    # --ignore-cr-at-eol so pure CRLF/LF (autocrlf) differences do not trip a false failure.
    & git diff --exit-code --ignore-cr-at-eol -- README.md | Out-Null

    if ($LASTEXITCODE -ne 0)
    {
        throw 'README.md is out of date with README.template.md. Run ./build.ps1 -Tasks Generate_Readme and commit README.md.'
    }

    Write-Build Green 'README.md is up to date.'
}
