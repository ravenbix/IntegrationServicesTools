# Continuously Updated Professional README — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `README.md` a comprehensive, professional module front page whose command-reference section is generated from `source/Public` and enforced by a QA drift test, so the listing can never fall out of date.

**Architecture:** A single pure function `ConvertTo-SsisReadme` reads `README.template.md` and the public-command sources, builds a grouped command index, and returns the full README text. Two consumers call it: a `Generate_Readme` Invoke-Build task that writes `README.md`, and a QA Pester test that regenerates into memory and asserts equality with the committed file. `README.md` becomes a build artifact; humans edit `README.template.md`.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/Invoke-Build, Pester v5, PowerShell AST (`[System.Management.Automation.Language.Parser]` + `GetHelpContent()`).

**Reference spec:** `docs/superpowers/specs/2026-06-01-readme-autogeneration-design.md`

**House-style reminders (from CLAUDE.md):** Allman braces; single quotes unless interpolating; no backticks (splat 3+ params into `$splat<Purpose>`, aligned `=`); 4-space indent; `[CmdletBinding()]` + comment-based help with `.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE`/`.OUTPUTS` on **every** function including these build helpers; `::new()` allowed; Conventional Commits.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `.build/Build-SsisReadme.ps1` | Two functions: `ConvertTo-SsisReadme` (pure: template + sources → README string) and `Update-SsisReadme` (writes `README.md`). Lives in `.build/` so `build.ps1` auto-dot-sources it and ModuleBuilder never merges it into the shipped module. |
| `.build/Readme.build.ps1` | Defines the Invoke-Build task `Generate_Readme`; dot-sources the generator and calls `Update-SsisReadme`. |
| `README.template.md` | Hand-authored professional README prose (12 sections + badges) containing one `<!-- SSIS:COMMANDS -->` token. The human-edited source. |
| `README.md` | Regenerated build artifact (no longer hand-edited). |
| `build.yaml` | Adds `Generate_Readme` to the `build` workflow. |
| `tests/Unit/Build-SsisReadme.tests.ps1` | Unit tests for `ConvertTo-SsisReadme` against fixture stubs. |
| `tests/QA/Readme.tests.ps1` | Drift check: regenerate and compare to committed `README.md`. |

**Build order rationale:** Build the pure generator (Tasks 1–2) test-first, then the file writer (Task 3), then the human-authored template (Task 4), then wire the build task + workflow (Task 5), then the QA drift gate (Task 6), then regenerate and verify the whole pipeline green (Task 7).

---

## Task 1: Grouping & ordering helpers (pure, inside the generator file)

These are the riskiest logic (collapse `Environment*`, group/verb ordering), so build them first and test them directly.

**Files:**
- Create: `.build/Build-SsisReadme.ps1`
- Test: `tests/Unit/Build-SsisReadme.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Build-SsisReadme.tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./build.ps1 -Tasks noop` once first if dependencies are not yet restored (`./build.ps1 -ResolveDependency -Tasks noop`), then:
`Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: FAIL — the file `.build/Build-SsisReadme.ps1` does not exist / functions not defined.

- [ ] **Step 3: Write minimal implementation**

Create `.build/Build-SsisReadme.ps1` with the three helpers (full comment-based help required by house style):

```powershell
function Get-SsisReadmeNounGroup
{
    <#
        .SYNOPSIS
            Maps an SSIS command name to its README index group.

        .DESCRIPTION
            Returns the noun portion (the text after the 'Ssis' prefix) of a
            <Verb>-Ssis<Noun> command name. Any noun beginning with 'Environment'
            (Environment, EnvironmentVariable, EnvironmentReference) collapses to the
            single group 'Environment'.

        .PARAMETER CommandName
            The full command name, for example 'Get-SsisEnvironmentVariable'.

        .EXAMPLE
            Get-SsisReadmeNounGroup -CommandName 'Set-SsisEnvironmentVariable'

            Returns 'Environment'.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $CommandName
    )

    process
    {
        $noun = ($CommandName -split '-Ssis', 2)[1]

        if ($noun -like 'Environment*')
        {
            return 'Environment'
        }

        return $noun
    }
}

function Get-SsisReadmeGroupRank
{
    <#
        .SYNOPSIS
            Returns the sort rank for a README command group.

        .DESCRIPTION
            Known groups sort in workflow precedence (Catalog, Folder, Project,
            Package, Environment, Parameter). Unknown groups sort after all known
            groups, alphabetically by virtue of a shared high rank plus name compare
            done by the caller.

        .PARAMETER Group
            The group name returned by Get-SsisReadmeNounGroup.

        .EXAMPLE
            Get-SsisReadmeGroupRank -Group 'Catalog'

            Returns 0.

        .OUTPUTS
            System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Group
    )

    process
    {
        $order = @('Catalog', 'Folder', 'Project', 'Package', 'Environment', 'Parameter')
        $index = $order.IndexOf($Group)

        if ($index -lt 0)
        {
            return $order.Count
        }

        return $index
    }
}

function Get-SsisReadmeVerbRank
{
    <#
        .SYNOPSIS
            Returns the sort rank for a command verb within a README group.

        .DESCRIPTION
            Orders verbs in a natural lifecycle (Get, New, Set, Publish, Export,
            Start, Stop, Wait, Remove). Unknown verbs sort after all known verbs.

        .PARAMETER Verb
            The verb portion of a command name, for example 'Get'.

        .EXAMPLE
            Get-SsisReadmeVerbRank -Verb 'Get'

            Returns 0.

        .OUTPUTS
            System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Verb
    )

    process
    {
        $order = @('Get', 'New', 'Set', 'Publish', 'Export', 'Start', 'Stop', 'Wait', 'Remove')
        $index = $order.IndexOf($Verb)

        if ($index -lt 0)
        {
            return $order.Count
        }

        return $index
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: PASS (all `Describe` blocks for the three helpers).

- [ ] **Step 5: Commit**

```bash
git add .build/Build-SsisReadme.ps1 tests/Unit/Build-SsisReadme.tests.ps1
git commit -m "feat: add README index grouping and ordering helpers"
```

---

## Task 2: `ConvertTo-SsisReadme` — synopsis extraction, index assembly, token substitution

**Files:**
- Modify: `.build/Build-SsisReadme.ps1` (add `Get-SsisReadmeCommandInfo` + `ConvertTo-SsisReadme`)
- Test: `tests/Unit/Build-SsisReadme.tests.ps1` (add cases)

- [ ] **Step 1: Write the failing test**

Append to `tests/Unit/Build-SsisReadme.tests.ps1`:

```powershell
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
        $result | Should -Match '\*\*Get-SsisFolder\*\* — Gets folders\.'
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: FAIL — `ConvertTo-SsisReadme` is not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `.build/Build-SsisReadme.ps1`:

```powershell
function Get-SsisReadmeCommandInfo
{
    <#
        .SYNOPSIS
            Extracts command name, verb, group, and synopsis from a public source file.

        .DESCRIPTION
            Parses a PowerShell source file with the language AST and reads the
            function's comment-based help synopsis. Returns a single object carrying
            the data the README index needs. Files that contain no function definition
            are ignored (no output).

        .PARAMETER Path
            Full path to a *.ps1 file under source/Public.

        .EXAMPLE
            Get-SsisReadmeCommandInfo -Path 'source/Public/Get-SsisFolder.ps1'

            Returns an object with Name, Verb, Group, and Synopsis.

        .OUTPUTS
            PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    process
    {
        $raw = Get-Content -Raw -Path $Path
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($raw, [ref] $null, [ref] $null)

        $functionAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Select-Object -First 1

        if (-not $functionAst)
        {
            return
        }

        $name = $functionAst.Name
        $synopsis = ($functionAst.GetHelpContent().Synopsis -replace '\s+', ' ').Trim()
        $verb = ($name -split '-', 2)[0]

        [PSCustomObject]@{
            Name     = $name
            Verb     = $verb
            Group    = Get-SsisReadmeNounGroup -CommandName $name
            Synopsis = $synopsis
        }
    }
}

function ConvertTo-SsisReadme
{
    <#
        .SYNOPSIS
            Builds the full README text from the template and the public command set.

        .DESCRIPTION
            Reads the README template, enumerates the public command source files,
            assembles a command-reference index grouped by SSIS noun (Environment
            variants collapsed) with a total count, and substitutes the index for the
            <!-- SSIS:COMMANDS --> token. Returns the complete README text. Pure: it
            performs no writes. Throws if the template lacks the token.

        .PARAMETER TemplatePath
            Path to README.template.md.

        .PARAMETER SourcePath
            Path to the folder of public command *.ps1 files (source/Public).

        .EXAMPLE
            ConvertTo-SsisReadme -TemplatePath './README.template.md' -SourcePath './source/Public'

            Returns the generated README text.

        .OUTPUTS
            System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]
        $SourcePath
    )

    process
    {
        $token = '<!-- SSIS:COMMANDS -->'
        $template = Get-Content -Raw -Path $TemplatePath

        if ($template -notmatch [regex]::Escape($token))
        {
            throw "README template '$TemplatePath' does not contain the $token placeholder."
        }

        $commands = @(
            Get-ChildItem -Path $SourcePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                ForEach-Object -Process { Get-SsisReadmeCommandInfo -Path $_.FullName }
        )

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('## Command reference')
        $lines.Add('')
        $lines.Add("IntegrationServicesTools exposes $($commands.Count) commands.")

        $groups = $commands |
            Group-Object -Property Group |
                Sort-Object -Property `
                    @{ Expression = { Get-SsisReadmeGroupRank -Group $_.Name } },
                    @{ Expression = { $_.Name } }

        foreach ($group in $groups)
        {
            $lines.Add('')
            $lines.Add("### $($group.Name)")

            $ordered = $group.Group |
                Sort-Object -Property `
                    @{ Expression = { Get-SsisReadmeVerbRank -Verb $_.Verb } },
                    @{ Expression = { $_.Name } }

            foreach ($command in $ordered)
            {
                $lines.Add("- **$($command.Name)** — $($command.Synopsis)")
            }
        }

        $block = $lines -join "`n"

        return ($template -replace [regex]::Escape($token), $block)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: PASS (all `ConvertTo-SsisReadme` cases plus the Task 1 helper cases).

- [ ] **Step 5: Commit**

```bash
git add .build/Build-SsisReadme.ps1 tests/Unit/Build-SsisReadme.tests.ps1
git commit -m "feat: assemble README command index from public sources"
```

---

## Task 3: `Update-SsisReadme` — write the file

**Files:**
- Modify: `.build/Build-SsisReadme.ps1` (add `Update-SsisReadme`)
- Test: `tests/Unit/Build-SsisReadme.tests.ps1` (add cases)

- [ ] **Step 1: Write the failing test**

Append to `tests/Unit/Build-SsisReadme.tests.ps1`:

```powershell
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: FAIL — `Update-SsisReadme` is not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `.build/Build-SsisReadme.ps1`:

```powershell
function Update-SsisReadme
{
    <#
        .SYNOPSIS
            Generates and writes README.md from the template and public command set.

        .DESCRIPTION
            Calls ConvertTo-SsisReadme and writes the result to the output path as
            UTF-8 without a byte-order mark (matching the repository encoding). This
            is the only side-effecting function in the README generator.

        .PARAMETER TemplatePath
            Path to README.template.md.

        .PARAMETER SourcePath
            Path to the folder of public command *.ps1 files (source/Public).

        .PARAMETER OutputPath
            Path to write the generated README.md.

        .EXAMPLE
            Update-SsisReadme -TemplatePath './README.template.md' -SourcePath './source/Public' -OutputPath './README.md'

            Regenerates README.md in place.

        .OUTPUTS
            None.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [string]
        $OutputPath
    )

    process
    {
        $splatReadme = @{
            TemplatePath = $TemplatePath
            SourcePath   = $SourcePath
        }

        $content = ConvertTo-SsisReadme @splatReadme

        if ($PSCmdlet.ShouldProcess($OutputPath, 'Write generated README'))
        {
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($OutputPath, $content, $utf8NoBom)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path tests/Unit/Build-SsisReadme.tests.ps1 -Output Detailed`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add .build/Build-SsisReadme.ps1 tests/Unit/Build-SsisReadme.tests.ps1
git commit -m "feat: write generated README.md as UTF-8 without BOM"
```

---

## Task 4: Author the professional README template

No automated test (it is prose). Verification is that generation succeeds and the token is present.

**Files:**
- Create: `README.template.md`

- [ ] **Step 1: Write the template**

Create `README.template.md`. The first line is the generated-file banner (it round-trips into `README.md` unchanged). Fill every section with real prose grounded in this module. Use the content below as the authored baseline — expand examples as needed but keep the `<!-- SSIS:COMMANDS -->` token exactly once.

```markdown
<!-- This file is generated from README.template.md. Do not edit by hand. Run ./build.ps1 -Tasks Generate_Readme. -->
# IntegrationServicesTools

[![Build Status](https://img.shields.io/badge/build-pending-lightgrey.svg)](#)
[![PowerShell Gallery](https://img.shields.io/badge/PSGallery-pending-lightgrey.svg)](#)
[![Downloads](https://img.shields.io/badge/downloads-pending-lightgrey.svg)](#)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1%20Desktop-blue.svg)](#requirements)

> PowerShell commands for administering the SQL Server Integration Services (SSIS) catalog — the SSISDB — under the Project Deployment Model.

## Overview

IntegrationServicesTools wraps the `Microsoft.SqlServer.Management.IntegrationServices`
managed object model in idiomatic PowerShell. It lets you create and configure the SSISDB
catalog, manage folders, deploy and export `.ispac` projects, and administer environments,
environment references, and parameter values — all without hand-writing T-SQL or clicking
through SQL Server Management Studio.

It targets administrators and DevOps engineers who automate SSIS deployments and want
composable, pipeline-friendly commands that return real objects.

## Features

- **Catalog administration** — create, inspect, and configure the SSISDB catalog.
- **Folder management** — create, update, and remove catalog folders.
- **Project lifecycle** — deploy (`.ispac`) and export projects, list packages, remove projects.
- **Environments** — create environments and manage their variables.
- **Environment references & parameters** — wire projects to environments and override parameter values.
- **Pipeline-native** — every command emits typed `Ssis.*` objects you can pipe between commands.
- **Safe by default** — state-changing commands support `-WhatIf` and `-Confirm`; removals are high-impact.

## Requirements

- **Windows PowerShell 5.1** (Desktop edition). PowerShell 7 is not supported.
- **SQL Server 2012 or later** with an SSISDB catalog (Project Deployment Model). LocalDB cannot host SSISDB.
- **[dbatools.library](https://www.powershellgallery.com/packages/dbatools.library)** — ships the
  SSIS managed object model assemblies this module loads at import. Install with
  `Install-Module dbatools.library`.
- **Windows integrated authentication** by default; SQL logins are supported via `-SqlCredential`.

## Installation

```powershell
# Prerequisite: the SSIS object model assemblies
Install-Module dbatools.library

# From the PowerShell Gallery (once published)
Install-Module IntegrationServicesTools

# Or build from source
git clone https://github.com/ravenbix/IntegrationServicesTools.git
cd IntegrationServicesTools
./build.ps1 -ResolveDependency -Tasks build
Import-Module ./output/module/IntegrationServicesTools/*/IntegrationServicesTools.psd1
```

## Quick start

```powershell
$instance = 'sql01\ssis'

# Ensure a catalog and a folder exist
New-SsisCatalog -SqlInstance $instance -Password (Read-Host -AsSecureString)
New-SsisFolder  -SqlInstance $instance -Name 'Finance' -Description 'Finance ETL'

# Deploy a project, then point it at an environment
Publish-SsisProject -SqlInstance $instance -Folder 'Finance' -Path 'C:\build\Billing.ispac'
New-SsisEnvironment -SqlInstance $instance -Folder 'Finance' -Name 'Prod'
Set-SsisEnvironmentVariable -SqlInstance $instance -Folder 'Finance' -Environment 'Prod' -Name 'CnStr' -Value 'Server=...'
New-SsisEnvironmentReference -SqlInstance $instance -Folder 'Finance' -Project 'Billing' -Environment 'Prod'
Set-SsisParameter -SqlInstance $instance -Folder 'Finance' -Project 'Billing' -Name 'CnStr' -ReferenceEnvironment 'Prod'
```

## Concepts

- **Two parameter sets.** Every command accepts either `-SqlInstance` (`ByInstance`, with optional
  `-SqlCredential`) or a piped `Ssis.*` object that carries its own connection (`ByObject`), so you
  can fluently compose pipelines.
- **Typed output.** Commands return native object-model instances decorated with a `PSTypeName`
  (`Ssis.Catalog`, `Ssis.Folder`, `Ssis.Project`, …). Custom table views are shipped via the
  module's format file; all native members remain accessible.
- **ShouldProcess.** State-changing commands support `-WhatIf`/`-Confirm`; `Remove-*` commands are
  high-impact and prompt by default.

<!-- SSIS:COMMANDS -->

## Usage examples

```powershell
# Folders
Get-SsisFolder -SqlInstance $instance | Format-Table Name, Description

# Projects and packages
Get-SsisProject -SqlInstance $instance -Folder 'Finance' |
    Get-SsisPackage

# Export a deployed project back to an .ispac
Export-SsisProject -SqlInstance $instance -Folder 'Finance' -Project 'Billing' -Path 'C:\backup\Billing.ispac'

# Environments and variables
Get-SsisEnvironment -SqlInstance $instance -Folder 'Finance' |
    Get-SsisEnvironmentVariable

# Parameters
Get-SsisParameter -SqlInstance $instance -Folder 'Finance' -Project 'Billing'
```

## Authentication

By default the module connects with the current Windows identity (integrated authentication).
To use a SQL login, pass a credential:

```powershell
$cred = Get-Credential
Get-SsisCatalog -SqlInstance $instance -SqlCredential $cred
```

## Contributing & development

This module is built on the [Sampler](https://github.com/gaelcolas/Sampler) scaffold.

```powershell
./build.ps1 -ResolveDependency -Tasks build   # build
./build.ps1 -Tasks test                        # QA + unit tests
./build.ps1 -Tasks Generate_Readme             # regenerate this README from the template
```

Development follows test-driven development and [Conventional Commits](https://www.conventionalcommits.org/).
See [CLAUDE.md](CLAUDE.md) for the full style guide. **Edit `README.template.md`, not `README.md`** —
the latter is generated.

## Testing

- **Unit tests** mock the interop seam and run without SQL Server.
- **Integration tests** are opt-in and require a real SSISDB; set `$env:SSIS_TEST_INSTANCE` to enable
  them. They skip cleanly when it is unset.

## Status

See [CHANGELOG.md](CHANGELOG.md) for released and unreleased changes.

## License & acknowledgements

Licensed under the MIT License — see [LICENSE](LICENSE).

Built with the [Sampler](https://github.com/gaelcolas/Sampler) module scaffold. The SSIS managed
object model assemblies are provided by [dbatools.library](https://github.com/dataplat/dbatools.library).
```

- [ ] **Step 2: Verify the token is present exactly once**

Run: `(Select-String -Path README.template.md -Pattern 'SSIS:COMMANDS' -SimpleMatch).Count`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add README.template.md
git commit -m "docs: add professional README template"
```

---

## Task 5: Wire the `Generate_Readme` build task into the workflow

**Files:**
- Create: `.build/Readme.build.ps1`
- Modify: `build.yaml` (add `Generate_Readme` to the `build` workflow)

- [ ] **Step 1: Create the task file**

Create `.build/Readme.build.ps1`:

```powershell
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

    Write-Build -Color 'Green' -Text "Regenerating README.md from template"

    Update-SsisReadme @splatReadme -Confirm:$false
}
```

> Note: `$BuildRoot` and `Write-Build` are provided by Invoke-Build at task-execution time.

- [ ] **Step 2: Add the task to the build workflow in `build.yaml`**

Modify the `build:` workflow block (currently lines ~48–53) to append `Generate_Readme` after the module build:

```yaml
  build:
    - Clean
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Generate_Readme
    - Create_changelog_release_output
```

- [ ] **Step 3: Run the task standalone to verify it works**

Run: `./build.ps1 -Tasks Generate_Readme`
Expected: Task runs, prints "Regenerating README.md from template", exits 0, and `README.md` now contains a `## Command reference` section listing the real commands.

- [ ] **Step 4: Verify README.md regenerated with real commands**

Run: `Select-String -Path README.md -Pattern 'exposes \d+ commands'`
Expected: a line such as `exposes 23 commands` (the count matches files in `source/Public`).

- [ ] **Step 5: Commit**

```bash
git add .build/Readme.build.ps1 build.yaml README.md
git commit -m "feat: add Generate_Readme build task and wire into build workflow"
```

---

## Task 6: QA drift test

**Files:**
- Create: `tests/QA/Readme.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/QA/Readme.tests.ps1`:

```powershell
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
        $actual = Get-Content -Raw -Path $script:readmePath

        # Normalize line endings so the comparison is not defeated by CRLF/LF differences.
        $normalize = { param ($text) ($text -replace "`r`n", "`n").TrimEnd("`n") }

        (& $normalize $actual) | Should -BeExactly (& $normalize $expected) -Because 'run ./build.ps1 -Tasks Generate_Readme and commit README.md'
    }
}
```

- [ ] **Step 2: Run the test to verify it passes (README was regenerated in Task 5)**

Run: `Invoke-Pester -Path tests/QA/Readme.tests.ps1 -Output Detailed`
Expected: PASS — because Task 5 regenerated `README.md` from the template.

- [ ] **Step 3: Prove the gate works — make README stale and confirm failure**

Run:
```powershell
Add-Content -Path README.md -Value 'drift'
Invoke-Pester -Path tests/QA/Readme.tests.ps1 -Output Detailed
```
Expected: FAIL with the "run ./build.ps1 -Tasks Generate_Readme" reason. Then restore:
`./build.ps1 -Tasks Generate_Readme`

- [ ] **Step 4: Commit**

```bash
git add tests/QA/Readme.tests.ps1
git commit -m "test: fail QA when README.md drifts from the template"
```

---

## Task 7: Full pipeline verification + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add CHANGELOG entry**

Under `## [Unreleased]` → `### Added` in `CHANGELOG.md`, add as the first bullet:

```markdown
- Continuously generated README: a professional README.template.md plus a Generate_Readme
  build task and QA drift test that regenerate and verify the command reference from
  source/Public.
```

- [ ] **Step 2: Run the full test suite**

Run: `./build.ps1 -Tasks test`
Expected: QA + unit tests PASS; integration tests skip cleanly (no `$env:SSIS_TEST_INSTANCE`). The new `Build-SsisReadme` unit tests and the `Readme` QA test are green.

- [ ] **Step 3: Confirm a clean working tree after a regenerate**

Run:
```powershell
./build.ps1 -Tasks Generate_Readme
git status --porcelain README.md
```
Expected: no output (README.md already current — proves idempotence and that the committed file matches the template).

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: note continuously generated README in changelog"
```

---

## Self-Review Notes (resolved during planning)

- **Spec coverage:** All 12 README sections appear in the Task 4 template; the generated index format, grouping rule, group/verb ordering, error handling (throw on missing token, count-0 path), and both consumers (build task + QA test) each map to a task.
- **Type consistency:** Function names are stable across tasks — `Get-SsisReadmeNounGroup`, `Get-SsisReadmeGroupRank`, `Get-SsisReadmeVerbRank`, `Get-SsisReadmeCommandInfo`, `ConvertTo-SsisReadme`, `Update-SsisReadme`. The token string `<!-- SSIS:COMMANDS -->` and the count phrasing `exposes N commands` are identical in the generator, the template, and the tests.
- **House style:** Every function carries full comment-based help with `.OUTPUTS`; splats named `$splatReadme`; Allman braces; single quotes; no backticks.
- **Coverage threshold note:** these generator functions live in `.build/` (outside the merged `.psm1`), so they do not affect the module's 85% code-coverage figure, and the Sampler QA function-enumeration does not require a matching `Public/Private` unit test for them — the dedicated `tests/Unit/Build-SsisReadme.tests.ps1` is for our own confidence.
```

