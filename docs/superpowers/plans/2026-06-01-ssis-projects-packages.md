# SSIS Tools — Phase 2 (Projects & Packages) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Projects/Packages command surface to `IntegrationServicesTools` — `Get-SsisProject`, `Publish-SsisProject` (deploy an `.ispac`), `Export-SsisProject` (retrieve an `.ispac`), `Remove-SsisProject`, and `Get-SsisPackage` — enabling a composable `Get-SsisFolder | Get-SsisProject | Get-SsisPackage` pipeline.

**Architecture:** Public `Verb-Ssis*` functions own parameter sets, `ShouldProcess`, file I/O, and output decoration; they delegate every real MOM call to thin private interop wrappers (`Get-SsisProjectObject`, `Publish-SsisProjectObject`, `Export-SsisProjectObject`, `Remove-SsisProjectObject`, `Get-SsisPackageObject`) and reuse the Phase 1 seam (`Connect-SsisCatalog`, `Get-SsisCatalogObject`, `Get-SsisFolderObject`, `Add-SsisTypeName`). Unit tests mock the seam so logic is testable without SQL Server; integration tests (tagged `Integration`) exercise the real types against a deployed `.ispac` fixture.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder build, Pester v5, PSScriptAnalyzer, `Microsoft.SqlServer.Management.IntegrationServices` MOM (loaded from `dbatools.library`), SMO.

**Spec:** `docs/superpowers/specs/2026-06-01-ssis-projects-packages-design.md`

---

## Read before starting (carried over from Phase 0/1)

1. **Two real parameter sets this phase.** Unlike Phase 1 (which overloaded `-SqlInstance [object]`), Phase 2 commands declare `DefaultParameterSetName = 'ByInstance'` plus a `ByObject` set whose `-InputObject` binds a piped `Ssis.*` MOM object (`ValueFromPipeline`). `-SqlInstance` is positional/mandatory in `ByInstance` and carries **no** pipeline-binding attribute — VERIFIED in Task 4 that adding `ValueFromPipelineByPropertyName` to `-SqlInstance` breaks routing of a piped object to `ByObject`. Keep `-SqlInstance` free of any `ValueFrom*` attribute; `-InputObject` (ValueFromPipeline) is the only pipeline-bound parameter, so piped objects route to `ByObject` cleanly.
2. **Sampler QA gates *private* functions too.** Every new private wrapper needs its own `tests/Unit/Private/<Name>.tests.ps1`, must pass PSScriptAnalyzer, and must have full comment-based help (`.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` whose text contains the function name, and a > 25-char description for **every** parameter).
3. **State-changing private wrappers** trip `PSUseShouldProcessForStateChangingFunctions` only for verbs New/Set/Remove/Start/Stop/Restart/Reset/Update. Of the new wrappers, **only `Remove-SsisProjectObject`** needs the `[SuppressMessageAttribute(...)]` (verb `Remove`); `Publish-`/`Export-`/`Get-` wrappers do not trigger the rule.
4. **File I/O uses mockable cmdlets, not static methods.** The spec describes reading/writing `.ispac` bytes; implement with `Get-Content -Encoding Byte -Raw` and `Set-Content -Encoding Byte` (PS 5.1) — Pester 5 **cannot** mock `[System.IO.File]` static methods, but it can mock these cmdlets. File I/O still lives in the public layer (not the MOM seam), as the spec requires.
5. **Coverage threshold stays 85%, met via Integration tests.** `build.yaml`'s `ExcludeFromCodeCoverage` is intentionally empty (per-function paths match nothing once ModuleBuilder merges to one `.psm1`). The new interop wrappers open real MOM connections, so the gate is only reached when the run includes Integration tests against a real SSISDB (`$env:SSIS_TEST_INSTANCE`). Do **not** add coverage-exclusion entries.
6. **Inner TDD loop** — rebuild before tests see a source change:
   ```powershell
   ./build.ps1 -Tasks build
   # once per shell — prepend BOTH the built module and resolved RequiredModules:
   $env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
   Invoke-Pester -Path ./tests/Unit/Public/<File>.tests.ps1 -Output Detailed
   ```
   Full QA/test run: `./build.ps1 -Tasks build,test`.

## MOM members used (verify exact names during TDD — Task 2 Step 2)

These are the assumed `Microsoft.SqlServer.Management.IntegrationServices` members. The **first GREEN run of Task 2** (which loads the real assembly) is the checkpoint to confirm them; if a name differs, fix it in that task and the dependent tasks before proceeding.

- `CatalogFolder.Projects` — collection with `.Contains(string)` and `[string]` indexer (like `.Folders`).
- `CatalogFolder.DeployProject([string] projectName, [byte[]] projectStream)` — deploy; treated as synchronous.
- `ProjectInfo.GetProjectBytes()` → `byte[]`.
- `ProjectInfo.Drop()`.
- `ProjectInfo.Packages` — collection with `.Contains(string)` and `[string]` indexer.
- `ProjectInfo.Name`, `.Description`, `.LastDeployedTime`, `.VersionMajor`, `.VersionMinor`, `.Parent` (→ `CatalogFolder`).
- `PackageInfo.Name`, `.Description`, `.EntryPoint`, `.Parent` (→ `ProjectInfo`).

## File structure

```
source/IntegrationServicesTools.format.ps1xml          modify  append Ssis.Project + Ssis.Package views
source/Private/Get-SsisProjectObject.ps1               create  folder.Projects / [name] -> ProjectInfo|$null (interop)
source/Private/Get-SsisPackageObject.ps1               create  project.Packages / [name] -> PackageInfo|$null (interop)
source/Private/Publish-SsisProjectObject.ps1           create  folder.DeployProject(name, bytes) (interop)
source/Private/Export-SsisProjectObject.ps1            create  project.GetProjectBytes() -> byte[] (interop)
source/Private/Remove-SsisProjectObject.ps1            create  project.Drop() (interop)
source/Public/Get-SsisProject.ps1                      create
source/Public/Get-SsisPackage.ps1                      create
source/Public/Publish-SsisProject.ps1                  create
source/Public/Export-SsisProject.ps1                   create
source/Public/Remove-SsisProject.ps1                   create
tests/Unit/Private/Get-SsisProjectObject.tests.ps1     create
tests/Unit/Private/Get-SsisPackageObject.tests.ps1     create
tests/Unit/Private/Publish-SsisProjectObject.tests.ps1 create
tests/Unit/Private/Export-SsisProjectObject.tests.ps1  create
tests/Unit/Private/Remove-SsisProjectObject.tests.ps1  create
tests/Unit/Public/Get-SsisProject.tests.ps1            create
tests/Unit/Public/Get-SsisPackage.tests.ps1            create
tests/Unit/Public/Publish-SsisProject.tests.ps1        create
tests/Unit/Public/Export-SsisProject.tests.ps1         create
tests/Unit/Public/Remove-SsisProject.tests.ps1         create
tests/Integration/Ssis.Project.Integration.tests.ps1   create  (tagged Integration; skipped without instance OR fixture)
tests/Integration/fixtures/ISTools_TestProject.ispac   create  tiny prebuilt .ispac (binary test data)
CHANGELOG.md                                           modify  one Unreleased entry per command
CLAUDE.md                                              modify  note the sanctioned binary test fixture
```

---

## Task 1: Format views — `Ssis.Project` and `Ssis.Package`

**Files:**
- Modify: `source/IntegrationServicesTools.format.ps1xml`

- [ ] **Step 1: Append two views before `</ViewDefinitions>`**

In `source/IntegrationServicesTools.format.ps1xml`, insert these two `<View>` blocks immediately **after** the closing `</View>` of the `Ssis.Folder` view and **before** `</ViewDefinitions>`:

```xml
    <View>
      <Name>Ssis.Project</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Project</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Name</Label></TableColumnHeader>
          <TableColumnHeader><Label>Folder</Label></TableColumnHeader>
          <TableColumnHeader><Label>Version</Label></TableColumnHeader>
          <TableColumnHeader><Label>LastDeployedTime</Label></TableColumnHeader>
          <TableColumnHeader><Label>Description</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>$_.Parent.Name</ScriptBlock></TableColumnItem>
              <TableColumnItem><ScriptBlock>'{0}.{1}' -f $_.VersionMajor, $_.VersionMinor</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>LastDeployedTime</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Description</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
    <View>
      <Name>Ssis.Package</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Package</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Name</Label></TableColumnHeader>
          <TableColumnHeader><Label>Project</Label></TableColumnHeader>
          <TableColumnHeader><Label>EntryPoint</Label></TableColumnHeader>
          <TableColumnHeader><Label>Description</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>$_.Parent.Name</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>EntryPoint</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Description</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
```

- [ ] **Step 2: Build and verify both views load**

Run:
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
(Get-FormatData -TypeName 'Ssis.Project') | Should -Not -BeNullOrEmpty
(Get-FormatData -TypeName 'Ssis.Package') | Should -Not -BeNullOrEmpty
```
Expected: import succeeds; both `Get-FormatData` calls return a view (no error).

- [ ] **Step 3: Commit**

```powershell
git add -A
git commit -m "feat: add Ssis.Project and Ssis.Package format views"
```

---

## Task 2: Private interop — read wrappers (`Get-SsisProjectObject`, `Get-SsisPackageObject`)

**Files:**
- Create: `source/Private/Get-SsisProjectObject.ps1`
- Create: `source/Private/Get-SsisPackageObject.ps1`
- Test: `tests/Unit/Private/Get-SsisProjectObject.tests.ps1`
- Test: `tests/Unit/Private/Get-SsisPackageObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/Get-SsisProjectObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisProjectObject' {
    It 'Returns the named project when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Projects collection: it
            # supports both .Contains(name) and the [name] indexer.
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $folder = [PSCustomObject]@{ Projects = @{ 'Sales' = $project } }

            $result = Get-SsisProjectObject -Folder $folder -Name 'Sales'

            $result.Name | Should -Be 'Sales'
        }
    }

    It 'Returns $null when the named project does not exist' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{ Projects = @{} }

            $result = Get-SsisProjectObject -Folder $folder -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Projects collection when no name is given' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{
                Projects = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisProjectObject -Folder $folder

            $result.Count | Should -Be 2
        }
    }
}
```

`tests/Unit/Private/Get-SsisPackageObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisPackageObject' {
    It 'Returns the named package when it exists' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{ Name = 'Load.dtsx' }
            $project = [PSCustomObject]@{ Packages = @{ 'Load.dtsx' = $package } }

            $result = Get-SsisPackageObject -Project $project -Name 'Load.dtsx'

            $result.Name | Should -Be 'Load.dtsx'
        }
    }

    It 'Returns $null when the named package does not exist' {
        InModuleScope $script:moduleName {
            $project = [PSCustomObject]@{ Packages = @{} }

            $result = Get-SsisPackageObject -Project $project -Name 'Missing.dtsx'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Packages collection when no name is given' {
        InModuleScope $script:moduleName {
            $project = [PSCustomObject]@{
                Packages = @{
                    'A.dtsx' = [PSCustomObject]@{ Name = 'A.dtsx' }
                    'B.dtsx' = [PSCustomObject]@{ Name = 'B.dtsx' }
                }
            }

            $result = Get-SsisPackageObject -Project $project

            $result.Count | Should -Be 2
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Get-SsisPackageObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/Get-SsisProjectObject.ps1`**

```powershell
function Get-SsisProjectObject
{
    <#
        .SYNOPSIS
            Returns project object(s) from an SSISDB catalog folder.

        .DESCRIPTION
            Returns the named project from the folder's Projects collection, or all projects when no
            name is given. Returns $null when a named project does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $project = Get-SsisProjectObject -Folder $folder -Name 'Sales'

            Returns the Sales project, or $null when it does not exist.

        .PARAMETER Folder
            The SSISDB CatalogFolder object whose projects to read, as returned by Get-SsisFolderObject.

        .PARAMETER Name
            The project name to return. When omitted, every project in the folder is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Folder.Projects.Contains($Name))
            {
                return $Folder.Projects[$Name]
            }

            return $null
        }

        return $Folder.Projects
    }
}
```

- [ ] **Step 4: Write `source/Private/Get-SsisPackageObject.ps1`**

```powershell
function Get-SsisPackageObject
{
    <#
        .SYNOPSIS
            Returns package object(s) from an SSISDB project.

        .DESCRIPTION
            Returns the named package from the project's Packages collection, or all packages when no
            name is given. Returns $null when a named package does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $package = Get-SsisPackageObject -Project $project -Name 'Load.dtsx'

            Returns the Load.dtsx package, or $null when it does not exist.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose packages to read, as returned by Get-SsisProjectObject.

        .PARAMETER Name
            The package name to return. When omitted, every package in the project is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.PackageInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Project.Packages.Contains($Name))
            {
                return $Project.Packages[$Name]
            }

            return $null
        }

        return $Project.Packages
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Get-SsisPackageObject.tests.ps1 -Output Detailed`
Expected: PASS (3 + 3 tests).

- [ ] **Step 6: Confirm the assumed MOM member names**

With the module imported (rebuild first), verify the read members exist on the real types so the rest of the plan is sound:
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
[Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder].GetProperty('Projects') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder].GetMethod('DeployProject') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo].GetMethod('GetProjectBytes') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo].GetProperty('Packages') | Should -Not -BeNullOrEmpty
```
Expected: all return non-null. If any name differs, correct it here and in the affected later tasks (the interop wrappers and the format view) before continuing.

- [ ] **Step 7: Commit**

```powershell
git add -A
git commit -m "feat: add project and package read interop wrappers"
```

---

## Task 3: Private interop — action wrappers (`Publish-`, `Export-`, `Remove-SsisProjectObject`)

**Files:**
- Create: `source/Private/Publish-SsisProjectObject.ps1`
- Create: `source/Private/Export-SsisProjectObject.ps1`
- Create: `source/Private/Remove-SsisProjectObject.ps1`
- Test: `tests/Unit/Private/Publish-SsisProjectObject.tests.ps1`
- Test: `tests/Unit/Private/Export-SsisProjectObject.tests.ps1`
- Test: `tests/Unit/Private/Remove-SsisProjectObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/Publish-SsisProjectObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Publish-SsisProjectObject' {
    It 'Calls DeployProject with the name and bytes on the supplied folder' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a DeployProject() ScriptMethod is a faithful stand-in for the MOM
            # CatalogFolder: the wrapper only calls DeployProject(name, bytes).
            $folder = [PSCustomObject]@{ DeployedName = $null; DeployedBytes = $null }
            $folder | Add-Member -MemberType 'ScriptMethod' -Name 'DeployProject' -Value {
                param ($projectName, $projectStream)
                $this.DeployedName = $projectName
                $this.DeployedBytes = $projectStream
            }

            $bytes = [byte[]](1, 2, 3)
            Publish-SsisProjectObject -Folder $folder -Name 'Sales' -ProjectBytes $bytes

            $folder.DeployedName | Should -Be 'Sales'
            $folder.DeployedBytes | Should -Be $bytes
        }
    }
}
```

`tests/Unit/Private/Export-SsisProjectObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Export-SsisProjectObject' {
    It 'Returns the bytes from the project GetProjectBytes call' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a GetProjectBytes() ScriptMethod is a faithful stand-in for the
            # MOM ProjectInfo: the wrapper only calls GetProjectBytes() and returns its result.
            $project = [PSCustomObject]@{}
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'GetProjectBytes' -Value {
                return [byte[]](9, 8, 7)
            }

            $result = Export-SsisProjectObject -Project $project

            $result | Should -Be ([byte[]](9, 8, 7))
        }
    }
}
```

`tests/Unit/Private/Remove-SsisProjectObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisProjectObject' {
    It 'Calls Drop on the supplied project' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a Drop() ScriptMethod is a faithful stand-in for the MOM
            # ProjectInfo: the wrapper only calls Drop().
            $project = [PSCustomObject]@{ DropCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Drop' -Value { $this.DropCalled = $true }

            Remove-SsisProjectObject -Project $project

            $project.DropCalled | Should -BeTrue
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Publish-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Export-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Remove-SsisProjectObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/Publish-SsisProjectObject.ps1`**

```powershell
function Publish-SsisProjectObject
{
    <#
        .SYNOPSIS
            Deploys an .ispac project into an SSISDB catalog folder.

        .DESCRIPTION
            Calls DeployProject(name, bytes) on the supplied CatalogFolder object to deploy a project
            from its .ispac byte content. The deploy is synchronous. Internal interop helper, not
            exported from the module.

        .EXAMPLE
            Publish-SsisProjectObject -Folder $folder -Name 'Sales' -ProjectBytes $bytes

            Deploys the Sales project into the folder from the supplied .ispac bytes.

        .PARAMETER Folder
            The target SSISDB CatalogFolder object the project is deployed into.

        .PARAMETER Name
            The catalog project name to create or update with this deployment.

        .PARAMETER ProjectBytes
            The raw bytes of the .ispac project file to deploy into the catalog.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [byte[]]
        $ProjectBytes
    )

    process
    {
        $Folder.DeployProject($Name, $ProjectBytes)
    }
}
```

- [ ] **Step 4: Write `source/Private/Export-SsisProjectObject.ps1`**

```powershell
function Export-SsisProjectObject
{
    <#
        .SYNOPSIS
            Returns the .ispac byte content of an SSISDB project.

        .DESCRIPTION
            Calls GetProjectBytes() on the supplied ProjectInfo object and returns the resulting
            byte array, which is the project's .ispac content. Internal interop helper, not exported
            from the module.

        .EXAMPLE
            $bytes = Export-SsisProjectObject -Project $project

            Returns the project's .ispac content as a byte array.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose .ispac bytes to retrieve, from Get-SsisProjectObject.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        return $Project.GetProjectBytes()
    }
}
```

- [ ] **Step 5: Write `source/Private/Remove-SsisProjectObject.ps1`**

```powershell
function Remove-SsisProjectObject
{
    <#
        .SYNOPSIS
            Drops a project from an SSISDB catalog.

        .DESCRIPTION
            Calls Drop() on the supplied ProjectInfo object to remove it (and its packages) from the
            catalog on the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisProjectObject -Project $project

            Drops the project from the catalog.

        .PARAMETER Project
            The SSISDB ProjectInfo object to drop, as returned by Get-SsisProjectObject.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisProject) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        $Project.Drop()
    }
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Publish-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Export-SsisProjectObject.tests.ps1, ./tests/Unit/Private/Remove-SsisProjectObject.tests.ps1 -Output Detailed`
Expected: PASS (1 + 1 + 1 tests).

- [ ] **Step 7: Commit**

```powershell
git add -A
git commit -m "feat: add project deploy/export/drop interop wrappers"
```

---

## Task 4: Public — `Get-SsisProject`

**Files:**
- Create: `source/Public/Get-SsisProject.ps1`
- Test: `tests/Unit/Public/Get-SsisProject.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisProject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }, [PSCustomObject]@{ Name = 'F2' }) }
        }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'P1' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns folder-scoped projects tagged Ssis.Project' {
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
            Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Finance' }
        }

        It 'Enumerates every folder when -Folder is omitted' {
            $result = Get-SsisProject -SqlInstance 'TestInstance'
            ($result | Measure-Object).Count | Should -Be 2
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 2 -Scope It
        }

        It 'Returns a single project when -Folder and -Name are given' {
            $result = Get-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales'
            $result.Name | Should -Be 'Sales'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisProject -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists projects of a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisProject
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisProject.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisProject` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisProject.ps1`**

```powershell
function Get-SsisProject
{
    <#
        .SYNOPSIS
            Gets projects from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB catalog projects as
            Ssis.Project objects. Returns every project across all folders by default, the projects of
            one folder when -Folder is given, or a single project when -Name is also given. Accepts a
            piped Ssis.Folder object to list that folder's projects without reconnecting. Writes a
            warning and returns nothing when the catalog or named folder does not exist.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance'

            Returns the projects in the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' | Get-SsisProject

            Returns every project in every folder by piping folder objects in.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder whose projects to return. When omitted, projects from every folder
            in the catalog are returned.

        .PARAMETER InputObject
            A piped Ssis.Folder object whose projects to list. Used instead of -SqlInstance/-Folder to
            keep the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of a specific project to return. When omitted, all projects in scope are returned.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Project')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $projectParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $projectParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projects = Get-SsisProjectObject -Folder $InputObject @projectParameters

            foreach ($project in $projects)
            {
                if ($null -ne $project)
                {
                    $project | Add-SsisTypeName -TypeName 'Ssis.Project'
                }
            }

            return
        }

        $connectParameters = @{ SqlInstance = $SqlInstance }

        if ($PSBoundParameters.ContainsKey('SqlCredential'))
        {
            $connectParameters['SqlCredential'] = $SqlCredential
        }

        $integrationServices = Connect-SsisCatalog @connectParameters

        $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

        if ($null -eq $catalog)
        {
            Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
            return
        }

        if ($PSBoundParameters.ContainsKey('Folder'))
        {
            $folders = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folders)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }
        }
        else
        {
            $folders = Get-SsisFolderObject -Catalog $catalog
        }

        foreach ($catalogFolder in $folders)
        {
            $projects = Get-SsisProjectObject -Folder $catalogFolder @projectParameters

            foreach ($project in $projects)
            {
                if ($null -ne $project)
                {
                    $project | Add-SsisTypeName -TypeName 'Ssis.Project'
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisProject.tests.ps1 -Output Detailed`
Expected: PASS (5 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisProject command.` under `## [Unreleased]` → `### Added` in `CHANGELOG.md`.
```powershell
git add -A
git commit -m "feat: add Get-SsisProject command"
```

---

## Task 5: Public — `Get-SsisPackage`

**Files:**
- Create: `source/Public/Get-SsisPackage.ps1`
- Test: `tests/Unit/Public/Get-SsisPackage.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisPackage.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisPackage' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }) }
        }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'P1' }) }
        }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'Load.dtsx' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns packages tagged Ssis.Package for a folder and project' {
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Package'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisPackage -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists packages of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisPackage
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Package'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisPackage.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisPackage` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisPackage.ps1`**

```powershell
function Get-SsisPackage
{
    <#
        .SYNOPSIS
            Gets packages from projects in the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB project packages as
            Ssis.Package objects. Scope narrows as you supply -Folder, -Project and -Name; omitting
            them enumerates broadly across the catalog. Accepts a piped Ssis.Project object to list
            that project's packages without reconnecting. Writes a warning and returns nothing when the
            catalog or named folder does not exist.

        .EXAMPLE
            Get-SsisPackage -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the packages in the Sales project of the Finance folder.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' | Get-SsisPackage

            Returns the packages of every project piped in from Get-SsisProject.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder to scope to. When omitted, every folder in the catalog is searched.

        .PARAMETER Project
            The name of the project to scope to. When omitted, every project in scope is searched.

        .PARAMETER InputObject
            A piped Ssis.Project object whose packages to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject pipeline.

        .PARAMETER Name
            The name of a specific package to return. When omitted, all packages in scope are returned.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Package')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $packageParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $packageParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $packages = Get-SsisPackageObject -Project $InputObject @packageParameters

            foreach ($package in $packages)
            {
                if ($null -ne $package)
                {
                    $package | Add-SsisTypeName -TypeName 'Ssis.Package'
                }
            }

            return
        }

        $connectParameters = @{ SqlInstance = $SqlInstance }

        if ($PSBoundParameters.ContainsKey('SqlCredential'))
        {
            $connectParameters['SqlCredential'] = $SqlCredential
        }

        $integrationServices = Connect-SsisCatalog @connectParameters

        $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

        if ($null -eq $catalog)
        {
            Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
            return
        }

        if ($PSBoundParameters.ContainsKey('Folder'))
        {
            $folders = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folders)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }
        }
        else
        {
            $folders = Get-SsisFolderObject -Catalog $catalog
        }

        foreach ($catalogFolder in $folders)
        {
            if ($PSBoundParameters.ContainsKey('Project'))
            {
                $projects = Get-SsisProjectObject -Folder $catalogFolder -Name $Project
            }
            else
            {
                $projects = Get-SsisProjectObject -Folder $catalogFolder
            }

            foreach ($folderProject in $projects)
            {
                if ($null -eq $folderProject)
                {
                    continue
                }

                $packages = Get-SsisPackageObject -Project $folderProject @packageParameters

                foreach ($package in $packages)
                {
                    if ($null -ne $package)
                    {
                        $package | Add-SsisTypeName -TypeName 'Ssis.Package'
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisPackage.tests.ps1 -Output Detailed`
Expected: PASS (3 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisPackage command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Get-SsisPackage command"
```

---

## Task 6: Public — `Publish-SsisProject`

**Files:**
- Create: `source/Public/Publish-SsisProject.ps1`
- Test: `tests/Unit/Public/Publish-SsisProject.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Publish-SsisProject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Publish-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true }
        Mock -CommandName Get-Content -ModuleName $script:moduleName -MockWith { [byte[]](1, 2, 3) }
    }

    It 'Deploys with the name defaulted from the file and returns Ssis.Project' {
        $result = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Project'
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Name -eq 'Sales' -and $ProjectBytes.Count -eq 3
        }
    }

    It 'Uses -Name to override the project name' {
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -Name 'Renamed' -Confirm:$false
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Renamed' }
    }

    It 'Errors and does not deploy when the .ispac path is missing' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $false }
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Missing.ispac' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not deploy when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Nope' -Path 'C:\out\Sales.ispac' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not deploy' {
        $null = Publish-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Path 'C:\out\Sales.ispac' -WhatIf
        Should -Invoke -CommandName Publish-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Publish-SsisProject.tests.ps1 -Output Detailed`
Expected: FAIL — `Publish-SsisProject` not recognized.

- [ ] **Step 3: Write `source/Public/Publish-SsisProject.ps1`**

```powershell
function Publish-SsisProject
{
    <#
        .SYNOPSIS
            Deploys an .ispac project into a folder of the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance, reads the .ispac file at -Path, and deploys
            it into the target folder. The catalog project name defaults to the .ispac file name
            (without extension) and is overridden by -Name. Accepts a piped Ssis.Folder object as the
            deploy target. The deploy is synchronous; on success the project is re-read and returned as
            an Ssis.Project object. Writes an error and makes no change when the path, catalog, or
            folder does not exist.

        .EXAMPLE
            Publish-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Path 'C:\build\Sales.ispac'

            Deploys Sales.ispac into the Finance folder as the project named Sales.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the existing folder to deploy the project into.

        .PARAMETER InputObject
            A piped Ssis.Folder object to deploy into, instead of -SqlInstance/-Folder, keeping the
            existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Path
            The path to the .ispac project file to deploy into the catalog.

        .PARAMETER Name
            The catalog project name to create or update. Defaults to the .ispac file name without its
            extension when omitted.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Project')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Leaf))
        {
            Write-Error -Message ('The .ispac file ''{0}'' was not found.' -f $Path)
            return
        }

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $projectName = $Name
        }
        else
        {
            $projectName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $targetFolder = $InputObject
        }
        else
        {
            $connectParameters = @{ SqlInstance = $SqlInstance }

            if ($PSBoundParameters.ContainsKey('SqlCredential'))
            {
                $connectParameters['SqlCredential'] = $SqlCredential
            }

            $integrationServices = Connect-SsisCatalog @connectParameters

            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            if ($null -eq $catalog)
            {
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''. Create it with New-SsisCatalog.' -f $SqlInstance)
                return
            }

            $targetFolder = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $targetFolder)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($projectName, 'Deploy SSIS project'))
        {
            $projectBytes = Get-Content -Path $Path -Encoding Byte -Raw

            Publish-SsisProjectObject -Folder $targetFolder -Name $projectName -ProjectBytes $projectBytes

            $project = Get-SsisProjectObject -Folder $targetFolder -Name $projectName
            $project | Add-SsisTypeName -TypeName 'Ssis.Project'
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Publish-SsisProject.tests.ps1 -Output Detailed`
Expected: PASS (5 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Publish-SsisProject command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Publish-SsisProject command"
```

---

## Task 7: Public — `Export-SsisProject`

**Files:**
- Create: `source/Public/Export-SsisProject.ps1`
- Test: `tests/Unit/Public/Export-SsisProject.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Export-SsisProject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Export-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Export-SsisProjectObject -ModuleName $script:moduleName -MockWith { [byte[]](1, 2, 3) }
        Mock -CommandName Set-Content -ModuleName $script:moduleName -MockWith { }
        # Directory exists; target file does not (no overwrite needed) by default.
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Container' }
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $false } -ParameterFilter { $PathType -eq 'Leaf' }
    }

    It 'Writes <project>.ispac into the directory and returns its FileInfo' {
        $result = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Confirm:$false
        $result.Name | Should -Be 'Sales.ispac'
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Path -like '*Sales.ispac' }
    }

    It 'Errors and does not write when the file exists without -Force' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Overwrites an existing file when -Force is given' {
        Mock -CommandName Test-Path -ModuleName $script:moduleName -MockWith { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -Force -Confirm:$false
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not write' {
        $null = Export-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Path 'C:\out' -WhatIf
        Should -Invoke -CommandName Set-Content -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Exports a piped Ssis.Project without connecting' {
        $project = [PSCustomObject]@{ Name = 'Sales' }
        $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

        $null = $project | Export-SsisProject -Path 'C:\out' -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Export-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Export-SsisProject.tests.ps1 -Output Detailed`
Expected: FAIL — `Export-SsisProject` not recognized.

- [ ] **Step 3: Write `source/Public/Export-SsisProject.ps1`**

```powershell
function Export-SsisProject
{
    <#
        .SYNOPSIS
            Exports an SSISDB project to an .ispac file on disk.

        .DESCRIPTION
            Connects to the specified SQL Server instance, retrieves a project's .ispac content, and
            writes it into the -Path directory as <project>.ispac. Accepts a piped Ssis.Project object
            to export without reconnecting. Errors when the target file already exists unless -Force is
            given. Returns the written file as a System.IO.FileInfo object. Writes an error and makes no
            change when the directory, catalog, folder, or project does not exist.

        .EXAMPLE
            Export-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' -Path 'C:\backup'

            Writes C:\backup\Sales.ispac from the Sales project in the Finance folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder that contains the project to export.

        .PARAMETER Name
            The name of the project to export from the folder.

        .PARAMETER InputObject
            A piped Ssis.Project object to export, instead of -SqlInstance/-Folder/-Name, keeping the
            existing connection from a Get-SsisProject pipeline.

        .PARAMETER Path
            The existing directory to write the <project>.ispac file into.

        .PARAMETER Force
            Overwrite the target .ispac file if it already exists. Without this switch an existing file
            causes an error and no write.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [switch]
        $Force
    )

    process
    {
        if (-not (Test-Path -Path $Path -PathType Container))
        {
            Write-Error -Message ('The output directory ''{0}'' was not found.' -f $Path)
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $project = $InputObject
        }
        else
        {
            $connectParameters = @{ SqlInstance = $SqlInstance }

            if ($PSBoundParameters.ContainsKey('SqlCredential'))
            {
                $connectParameters['SqlCredential'] = $SqlCredential
            }

            $integrationServices = Connect-SsisCatalog @connectParameters

            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            if ($null -eq $catalog)
            {
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $catalogFolder = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $catalogFolder)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $project = Get-SsisProjectObject -Folder $catalogFolder -Name $Name

            if ($null -eq $project)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Name, $Folder)
                return
            }
        }

        $targetFile = Join-Path -Path $Path -ChildPath ($project.Name + '.ispac')

        if ((Test-Path -Path $targetFile -PathType Leaf) -and -not $Force)
        {
            Write-Error -Message ('The file ''{0}'' already exists. Use -Force to overwrite.' -f $targetFile)
            return
        }

        if ($PSCmdlet.ShouldProcess($targetFile, 'Export SSIS project'))
        {
            $projectBytes = Export-SsisProjectObject -Project $project

            Set-Content -Path $targetFile -Value $projectBytes -Encoding Byte

            [System.IO.FileInfo]::new($targetFile)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Export-SsisProject.tests.ps1 -Output Detailed`
Expected: PASS (5 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Export-SsisProject command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Export-SsisProject command"
```

---

## Task 8: Public — `Remove-SsisProject`

**Files:**
- Create: `source/Public/Remove-SsisProject.ps1`
- Test: `tests/Unit/Public/Remove-SsisProject.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Remove-SsisProject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisProject' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Drops the project when it exists (with -Confirm:$false)' {
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 1 -Scope It
    }

    It 'Errors when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Nope' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not drop' {
        Remove-SsisProject -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Sales' -WhatIf
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Drops a piped Ssis.Project without connecting' {
        $project = [PSCustomObject]@{ Name = 'Sales' }
        $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

        $project | Remove-SsisProject -Confirm:$false
        Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        Should -Invoke -CommandName Remove-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisProject.tests.ps1 -Output Detailed`
Expected: FAIL — `Remove-SsisProject` not recognized.

- [ ] **Step 3: Write `source/Public/Remove-SsisProject.ps1`**

```powershell
function Remove-SsisProject
{
    <#
        .SYNOPSIS
            Removes a project from a folder in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and drops a project (and its packages) from
            the SSISDB catalog. Accepts a piped Ssis.Project object to drop without reconnecting.
            Writes an error when the catalog, folder, or named project does not exist. This is a
            destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales'

            Removes the Sales project from the Finance folder on the named instance.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder that contains the project to remove.

        .PARAMETER Name
            The name of the project to remove from the folder.

        .PARAMETER InputObject
            A piped Ssis.Project object to drop, instead of -SqlInstance/-Folder/-Name, keeping the
            existing connection from a Get-SsisProject pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByInstance')]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByInstance')]
        [Alias('ServerInstance')]
        [object]
        $SqlInstance,

        [Parameter(ParameterSetName = 'ByInstance')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $project = $InputObject
        }
        else
        {
            $connectParameters = @{ SqlInstance = $SqlInstance }

            if ($PSBoundParameters.ContainsKey('SqlCredential'))
            {
                $connectParameters['SqlCredential'] = $SqlCredential
            }

            $integrationServices = Connect-SsisCatalog @connectParameters

            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            if ($null -eq $catalog)
            {
                Write-Error -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $catalogFolder = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $catalogFolder)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $project = Get-SsisProjectObject -Folder $catalogFolder -Name $Name

            if ($null -eq $project)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Name, $Folder)
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($project.Name, 'Remove SSIS project'))
        {
            Remove-SsisProjectObject -Project $project
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisProject.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Remove-SsisProject command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Remove-SsisProject command"
```

---

## Task 9: Integration test + `.ispac` fixture + CLAUDE.md note

**Files:**
- Create: `tests/Integration/fixtures/ISTools_TestProject.ispac` (binary test data — see Step 1)
- Create: `tests/Integration/Ssis.Project.Integration.tests.ps1`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Provide the `.ispac` fixture**

Place a tiny, real SSIS project build artifact at `tests/Integration/fixtures/ISTools_TestProject.ispac`. It must be a genuine `.ispac` (the MOM validates it on deploy) containing **one** trivial package (an empty/`Sequence`-only `.dtsx`). Produce it once with SSIS tooling (Visual Studio + the SSIS extension, or an existing build output renamed). The project name **inside** the `.ispac` is not required to match the file name — `Publish-SsisProject` sets the catalog project name from the file name (`ISTools_TestProject`).

> This file is sanctioned **binary test data**, an explicit exception to the repo's "never commit binaries" rule (which targets the MOM/assemblies). The integration test below **self-skips** when the fixture is absent, so the rest of the suite stays green even before the fixture is committed.

Create the fixtures directory if needed:
```powershell
New-Item -ItemType Directory -Path ./tests/Integration/fixtures -Force | Out-Null
```

- [ ] **Step 2: Write the integration test**

`tests/Integration/Ssis.Project.Integration.tests.ps1`:
```powershell
BeforeDiscovery {
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:skipIntegration = [string]::IsNullOrEmpty($env:SSIS_TEST_INSTANCE) -or -not (Test-Path -Path $script:fixturePath)
}

BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:fixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures\ISTools_TestProject.ispac'
    $script:folderName = 'ISTools_IntegrationTest'
    $script:projectName = 'ISTools_TestProject'
    $script:exportDir = Join-Path -Path $TestDrive -ChildPath 'export'
    New-Item -ItemType Directory -Path $script:exportDir -Force | Out-Null

    # Start from a known-clean state in case a previous run was interrupted.
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }

    New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Created by integration test' -Confirm:$false | Out-Null
}

AfterAll {
    $existingFolder = Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName -WarningAction SilentlyContinue

    if ($existingFolder)
    {
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
    }

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'SSIS project lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Publishes the .ispac and returns it tagged Ssis.Project' {
        $project = Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false

        $project.PSObject.TypeNames | Should -Contain 'Ssis.Project'
        $project.Name | Should -Be $script:projectName
    }

    It 'Gets the deployed project by folder and name' {
        $project = Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName

        $project.Name | Should -Be $script:projectName
    }

    It 'Lists the project by piping the folder in' {
        $names = (Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName | Get-SsisProject).Name

        $names | Should -Contain $script:projectName
    }

    It 'Gets at least one package tagged Ssis.Package' {
        $packages = Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName | Get-SsisPackage

        ($packages | Measure-Object).Count | Should -BeGreaterThan 0
        $packages[0].PSObject.TypeNames | Should -Contain 'Ssis.Package'
    }

    It 'Exports the project to an .ispac file' {
        $file = Export-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName -Path $script:exportDir -Force -Confirm:$false

        $file.FullName | Should -Exist
        $file.Name | Should -Be ($script:projectName + '.ispac')
    }

    It 'Removes the project' {
        Remove-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName -Confirm:$false

        Get-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Name $script:projectName | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 3: Note the sanctioned fixture in `CLAUDE.md`**

In `CLAUDE.md`, under the `## Testing` section (after the Integration bullet that begins "**Integration** (`tests/Integration/...`"), add this bullet:
```markdown
- **Binary test data exception.** `tests/Integration/fixtures/*.ispac` are committed `.ispac` build
  artifacts used to exercise project deploy/export. They are sanctioned **test data** — the
  "never commit binaries" rule targets the MOM/assemblies, not test fixtures. The project
  integration test self-skips when the fixture is absent.
```

- [ ] **Step 4: Run the integration test two ways**

Without an instance (must skip cleanly):
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path ./tests/Integration/Ssis.Project.Integration.tests.ps1 -Output Detailed
```
Expected: tests are skipped (not failed).

With a real SSISDB (only if available):
```powershell
$env:SSIS_TEST_INSTANCE = 'localhost'
Invoke-Pester -Path ./tests/Integration/Ssis.Project.Integration.tests.ps1 -Tag Integration -Output Detailed
```
Expected: 6 tests pass (requires the fixture committed in Step 1).

- [ ] **Step 5: Commit**

```powershell
git add -A
git commit -m "test: add SSIS project integration lifecycle and .ispac fixture"
```

---

## Task 10: Full QA gate

**Files:** none (verification only)

- [ ] **Step 1: Run the complete build and test suite**

Run: `./build.ps1 -Tasks build,test`
Expected: build succeeds; all Unit + QA Pester tests pass; QA `helpQuality`/`FunctionalQuality`/`TestQuality` green for the five new public **and** five new private functions. (Unit-only runs report a coverage shortfall by design — the new interop wrappers are integration-covered. Run the project integration test against a real SSISDB to confirm the 85% gate, as in Phase 1.)

- [ ] **Step 2: Fix any QA failures and re-run**

Common fixes:
- Missing `<Name>.tests.ps1` → ensure each new public **and** private function has its own unit test file with the exact name.
- Help failures → confirm `.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` whose text contains the function name, and every parameter described with > 25 chars (including `-InputObject`, `-Path`, `-Force`, `-Project`).
- Analyzer failures → resolve the reported rule (e.g. confirm the `SuppressMessageAttribute` on `Remove-SsisProjectObject`).

- [ ] **Step 3: Final commit**

```powershell
git add -A
git commit -m "test: green build and full QA for Phase 2 projects and packages"
```

---

## Done criteria

- `./build.ps1 -Tasks build,test` is green (Unit + QA).
- `Get-SsisProject`, `Publish-SsisProject`, `Export-SsisProject`, `Remove-SsisProject`, `Get-SsisPackage` are exported, unit-tested, and decorate output with `Ssis.Project` / `Ssis.Package`.
- The `folder → project → package` pipeline works: `Get-SsisFolder | Get-SsisProject | Get-SsisPackage`, and `Get-SsisProject | Export-SsisProject -Path <dir>`.
- `Publish-`/`Export-`/`Remove-SsisProject` honor `-WhatIf`/`-Confirm`; `Remove-SsisProject` is `ConfirmImpact High`.
- Integration tests run the full deploy→get→package→export→remove lifecycle against a real SSISDB when `$env:SSIS_TEST_INSTANCE` is set and the fixture is present, and skip cleanly otherwise.
- `Ssis.Project` and `Ssis.Package` format views render concise default tables.
```