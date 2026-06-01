# SSIS Tools — Phase 3b (Environment References & Parameters) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the environment-reference and parameter command surface to `IntegrationServicesTools` — `Get-SsisEnvironmentReference`, `New-SsisEnvironmentReference`, `Remove-SsisEnvironmentReference`, `Get-SsisParameter`, `Set-SsisParameter` — completing Phase 3 so a project can be bound to an environment and its parameters set to literals or environment-variable references.

**Architecture:** Public `Verb-Ssis*` functions own parameter sets, validation, the `-Value`/`-ReferencedVariable` mutual-exclusion guard, `ShouldProcess`, and `Ssis.*` decoration; they delegate every real MOM call to thin private interop wrappers (`Get-/New-/Remove-SsisEnvironmentReferenceObject`, `Get-/Set-SsisParameterObject`) that each own their `Add`/`Remove`/`Set` + `Alter` persistence. They reuse the Phase 0–2 seam (`Connect-SsisCatalog`, `Get-SsisCatalogObject`, `Get-SsisFolderObject`, `Get-SsisProjectObject`, `Get-SsisPackageObject`, `Add-SsisTypeName`). Unit tests mock the seam (no SQL Server); integration tests (tagged `Integration`) exercise the real types and reuse the Phase 2 `.ispac` fixture, extended with a project parameter.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder build, Pester v5, PSScriptAnalyzer, `Microsoft.SqlServer.Management.IntegrationServices` MOM (loaded from `dbatools.library`), SMO.

**Spec:** `docs/superpowers/specs/2026-06-01-ssis-environments-parameters-design.md` (this is plan 3b of two; plan 3a — environments & variables — should be implemented first, as 3b's integration test reuses `New-SsisEnvironment`/`Set-SsisEnvironmentVariable`).

---

## Read before starting (carried over from Phase 0–3a)

1. **Two real parameter sets.** `DefaultParameterSetName = 'ByInstance'` plus a `ByObject` set whose `-InputObject` binds a piped `Ssis.*` MOM object (`ValueFromPipeline`). `-SqlInstance` is positional/mandatory in `ByInstance` and carries **no** `ValueFrom*` attribute. `-InputObject` is the only pipeline-bound parameter.
2. **Sampler QA gates *private* functions too.** Every new private wrapper needs its own `tests/Unit/Private/<Name>.tests.ps1`, must pass PSScriptAnalyzer, and must have full comment-based help (`.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` whose text contains the function name, a > 25-char description for **every** parameter). Public functions additionally need `.OUTPUTS`.
3. **State-changing private wrappers** trip `PSUseShouldProcessForStateChangingFunctions` for verbs New/Set/Remove. `New-SsisEnvironmentReferenceObject`, `Remove-SsisEnvironmentReferenceObject`, and `Set-SsisParameterObject` carry the `[SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', …)]` justification. `Get-` wrappers do not.
4. **The persist wrinkle (as in 3a).** Reference and parameter mutations do not persist on their own: each action wrapper calls `project.Alter()` (or `.Remove`/`.Add` then `.Alter()`) itself. The public layer never calls `Add`/`Remove`/`Set`/`Alter`.
5. **Two-dimensional binding on `Set-SsisParameter`.** The connection set (`ByInstance`/`ByObject`) and the value-type (`-Value` literal vs `-ReferencedVariable`) are independent. Value-type is **not** a parameter set; it is enforced by a runtime guard: supplying both `-Value` and `-ReferencedVariable`, or neither, is a terminating error (`throw`). The value-type crosses to the seam as a **string** `'Literal'`/`'Referenced'`, so the public layer never references the MOM enum (kept in the wrapper, integration-covered).
6. **Coverage threshold stays 85%, met via Integration tests.** The new interop wrappers open real MOM connections and are integration-only. Do **not** add coverage-exclusion entries.
7. **Inner TDD loop** — rebuild before tests see a source change:
   ```powershell
   ./build.ps1 -Tasks build
   # once per shell — prepend BOTH the built module and resolved RequiredModules:
   $env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
   Invoke-Pester -Path ./tests/Unit/Public/<File>.tests.ps1 -Output Detailed
   ```
   Full QA/test run: `./build.ps1 -Tasks build,test`.

## MOM members used (verify exact names during TDD — Task 2 Step 6)

Assumed `Microsoft.SqlServer.Management.IntegrationServices` members. The **first GREEN run that loads the real assembly** (Task 2 Step 6) is the checkpoint to confirm them; fix any divergence in that task and dependents before continuing.

- `ProjectInfo.References` — `EnvironmentReferenceCollection`: enumerable of `EnvironmentReference`; `.Add(string environmentName)` (relative); `.Add(string environmentName, string environmentFolderName)` (absolute); `.Remove(EnvironmentReference)`.
- `EnvironmentReference.EnvironmentName`, `.EnvironmentFolderName` (null/empty for relative), `.ReferenceType`, `.Parent` (→ `ProjectInfo`).
- `ProjectInfo.Parameters` / `PackageInfo.Parameters` — `ParameterInfoCollection` with `.Contains(string)` and `[string]` indexer (like `.Packages`).
- `ParameterInfo.Set(ParameterInfo+ParameterValueType valueType, object value)`; nested enum `ParameterInfo+ParameterValueType` with members `Literal` and `Referenced`.
- `ParameterInfo.Name`, `.DataType`, `.Value`, `.Sensitive`, `.Required`, `.ReferencedVariableName`, `.Parent` (→ `ProjectInfo` or `PackageInfo`).
- `ProjectInfo.Alter()` persists reference and parameter changes (already verified to exist in Phase 2).

> If `References.Remove` takes a reference id rather than the object, change `Remove-SsisEnvironmentReferenceObject` to `$Project.References.Remove($Reference.Reference)` (or the correct id property) and update its test stand-in. If `ParameterInfo.Set` persists immediately (no `Alter` needed), drop the `$Project.Alter()` line from `Set-SsisParameterObject`.

## File structure

```
source/IntegrationServicesTools.format.ps1xml                          modify  append Ssis.EnvironmentReference + Ssis.Parameter views
source/Private/Get-SsisEnvironmentReferenceObject.ps1                  create  project.References -> EnvironmentReference[] (interop)
source/Private/New-SsisEnvironmentReferenceObject.ps1                  create  references.Add(...) + project.Alter() (interop)
source/Private/Remove-SsisEnvironmentReferenceObject.ps1              create  references.Remove(ref) + project.Alter() (interop)
source/Private/Get-SsisParameterObject.ps1                            create  container.Parameters / [name] -> ParameterInfo|$null (interop)
source/Private/Set-SsisParameterObject.ps1                            create  parameter.Set(type, value) + project.Alter() (interop)
source/Public/Get-SsisEnvironmentReference.ps1                        create
source/Public/New-SsisEnvironmentReference.ps1                        create
source/Public/Remove-SsisEnvironmentReference.ps1                     create
source/Public/Get-SsisParameter.ps1                                  create
source/Public/Set-SsisParameter.ps1                                  create
tests/Unit/Private/Get-SsisEnvironmentReferenceObject.tests.ps1      create
tests/Unit/Private/New-SsisEnvironmentReferenceObject.tests.ps1      create
tests/Unit/Private/Remove-SsisEnvironmentReferenceObject.tests.ps1   create
tests/Unit/Private/Get-SsisParameterObject.tests.ps1                 create
tests/Unit/Private/Set-SsisParameterObject.tests.ps1                 create
tests/Unit/Public/Get-SsisEnvironmentReference.tests.ps1             create
tests/Unit/Public/New-SsisEnvironmentReference.tests.ps1             create
tests/Unit/Public/Remove-SsisEnvironmentReference.tests.ps1          create
tests/Unit/Public/Get-SsisParameter.tests.ps1                        create
tests/Unit/Public/Set-SsisParameter.tests.ps1                        create
tests/Integration/fixtures/New-TestProjectIspac.ps1                  modify  add a project parameter to the generated fixture
tests/Integration/fixtures/ISTools_TestProject.ispac                 modify  regenerated binary (now has a project parameter)
tests/Integration/Ssis.Reference.Integration.tests.ps1              create  (tagged Integration; skipped without instance OR fixture)
CHANGELOG.md                                                          modify  one Unreleased entry per command
```

---

## Task 1: Format views — `Ssis.EnvironmentReference` and `Ssis.Parameter`

**Files:**
- Modify: `source/IntegrationServicesTools.format.ps1xml`

- [ ] **Step 1: Append two views before `</ViewDefinitions>`**

In `source/IntegrationServicesTools.format.ps1xml`, insert these two `<View>` blocks immediately **after** the closing `</View>` of the `Ssis.EnvironmentVariable` view (added in plan 3a) and **before** `</ViewDefinitions>`:

```xml
    <View>
      <Name>Ssis.EnvironmentReference</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.EnvironmentReference</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Project</Label></TableColumnHeader>
          <TableColumnHeader><Label>Environment</Label></TableColumnHeader>
          <TableColumnHeader><Label>EnvironmentFolder</Label></TableColumnHeader>
          <TableColumnHeader><Label>ReferenceType</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><ScriptBlock>$_.Parent.Name</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>EnvironmentName</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>EnvironmentFolderName</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>ReferenceType</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
    <View>
      <Name>Ssis.Parameter</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Parameter</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Name</Label></TableColumnHeader>
          <TableColumnHeader><Label>Scope</Label></TableColumnHeader>
          <TableColumnHeader><Label>DataType</Label></TableColumnHeader>
          <TableColumnHeader><Label>Sensitive</Label></TableColumnHeader>
          <TableColumnHeader><Label>Required</Label></TableColumnHeader>
          <TableColumnHeader><Label>Value</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>if ($_.Parent.GetType().Name -eq 'PackageInfo') { 'Package' } else { 'Project' }</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>DataType</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Sensitive</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Required</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>if ($_.ReferencedVariableName) { '@' + $_.ReferencedVariableName } else { $_.Value }</ScriptBlock></TableColumnItem>
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
(Get-FormatData -TypeName 'Ssis.EnvironmentReference') | Should -Not -BeNullOrEmpty
(Get-FormatData -TypeName 'Ssis.Parameter') | Should -Not -BeNullOrEmpty
```
Expected: import succeeds; both `Get-FormatData` calls return a view.

- [ ] **Step 3: Commit**

```powershell
git add -A
git commit -m "feat: add Ssis.EnvironmentReference and Ssis.Parameter format views"
```

---

## Task 2: Private interop — read wrappers (`Get-SsisEnvironmentReferenceObject`, `Get-SsisParameterObject`)

**Files:**
- Create: `source/Private/Get-SsisEnvironmentReferenceObject.ps1`
- Create: `source/Private/Get-SsisParameterObject.ps1`
- Test: `tests/Unit/Private/Get-SsisEnvironmentReferenceObject.tests.ps1`
- Test: `tests/Unit/Private/Get-SsisParameterObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/Get-SsisEnvironmentReferenceObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentReferenceObject' {
    It 'Returns the project References collection' {
        InModuleScope $script:moduleName {
            $references = @(
                [PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' }
                [PSCustomObject]@{ EnvironmentName = 'Dev'; EnvironmentFolderName = 'Shared' }
            )
            $project = [PSCustomObject]@{ References = $references }

            $result = Get-SsisEnvironmentReferenceObject -Project $project

            ($result | Measure-Object).Count | Should -Be 2
        }
    }
}
```

`tests/Unit/Private/Get-SsisParameterObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisParameterObject' {
    It 'Returns the named parameter when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Parameters collection: it supports both
            # .Contains(name) and the [name] indexer.
            $parameter = [PSCustomObject]@{ Name = 'TargetPort' }
            $container = [PSCustomObject]@{ Parameters = @{ 'TargetPort' = $parameter } }

            $result = Get-SsisParameterObject -Container $container -Name 'TargetPort'

            $result.Name | Should -Be 'TargetPort'
        }
    }

    It 'Returns $null when the named parameter does not exist' {
        InModuleScope $script:moduleName {
            $container = [PSCustomObject]@{ Parameters = @{} }

            $result = Get-SsisParameterObject -Container $container -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Parameters collection when no name is given' {
        InModuleScope $script:moduleName {
            $container = [PSCustomObject]@{
                Parameters = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisParameterObject -Container $container

            $result.Count | Should -Be 2
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Get-SsisParameterObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/Get-SsisEnvironmentReferenceObject.ps1`**

```powershell
function Get-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Returns the environment references defined on an SSISDB project.

        .DESCRIPTION
            Returns the project's References collection, where each item binds the project to an
            environment (relative when no folder is set, absolute otherwise). Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $references = Get-SsisEnvironmentReferenceObject -Project $project

            Returns every environment reference defined on the project.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose environment references to read, as returned by
            Get-SsisProjectObject.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentReference')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        return $Project.References
    }
}
```

- [ ] **Step 4: Write `source/Private/Get-SsisParameterObject.ps1`**

```powershell
function Get-SsisParameterObject
{
    <#
        .SYNOPSIS
            Returns parameter object(s) from an SSISDB project or package.

        .DESCRIPTION
            Returns the named parameter from the container's Parameters collection, or all parameters
            when no name is given. Returns $null when a named parameter does not exist. The container is
            an SSISDB ProjectInfo (project-level parameters) or PackageInfo (package-level parameters).
            Internal interop helper, not exported from the module.

        .EXAMPLE
            $parameter = Get-SsisParameterObject -Container $project -Name 'TargetPort'

            Returns the TargetPort project parameter, or $null when it does not exist.

        .PARAMETER Container
            The SSISDB ProjectInfo or PackageInfo whose parameters to read. Both expose a Parameters
            collection.

        .PARAMETER Name
            The parameter name to return. When omitted, every parameter on the container is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Container,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Container.Parameters.Contains($Name))
            {
                return $Container.Parameters[$Name]
            }

            return $null
        }

        return $Container.Parameters
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Get-SsisParameterObject.tests.ps1 -Output Detailed`
Expected: PASS (1 + 3 tests).

- [ ] **Step 6: Confirm the assumed MOM member names**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
[Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo].GetProperty('References') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo].GetProperty('Parameters') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.PackageInfo].GetProperty('Parameters') | Should -Not -BeNullOrEmpty
# Confirm the nested ParameterValueType enum name + members used by Task 3's Set wrapper:
[Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo+ParameterValueType] | Should -Not -BeNullOrEmpty
[System.Enum]::GetNames([Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo+ParameterValueType])
# Confirm the References collection Add/Remove overloads + the EnvironmentReference members:
[Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo].GetProperty('References').PropertyType.GetMethods().Name | Select-Object -Unique
```
Expected: the `Should` lines return non-null; the enum names include `Literal` and `Referenced`; the methods list shows `Add` and `Remove`. If any differ (enum nesting, `Remove` taking an id), correct Task 3 and the dependent public tasks here before continuing.

- [ ] **Step 7: Commit**

```powershell
git add -A
git commit -m "feat: add environment-reference and parameter read interop wrappers"
```

---

## Task 3: Private interop — action wrappers (`New-`/`Remove-SsisEnvironmentReferenceObject`, `Set-SsisParameterObject`)

**Files:**
- Create: `source/Private/New-SsisEnvironmentReferenceObject.ps1`
- Create: `source/Private/Remove-SsisEnvironmentReferenceObject.ps1`
- Create: `source/Private/Set-SsisParameterObject.ps1`
- Test: `tests/Unit/Private/New-SsisEnvironmentReferenceObject.tests.ps1`
- Test: `tests/Unit/Private/Remove-SsisEnvironmentReferenceObject.tests.ps1`
- Test: `tests/Unit/Private/Set-SsisParameterObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/New-SsisEnvironmentReferenceObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentReferenceObject' {
    It 'Adds a relative reference (no folder) and alters the project' {
        InModuleScope $script:moduleName {
            $references = [PSCustomObject]@{ AddedEnv = $null; AddedFolder = 'unset' }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($environmentName, $environmentFolderName)
                $this.AddedEnv = $environmentName
                $this.AddedFolder = $environmentFolderName
            }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod'

            $project.References.AddedEnv | Should -Be 'Prod'
            $project.References.AddedFolder | Should -BeNullOrEmpty
            $project.AlterCalled | Should -BeTrue
        }
    }

    It 'Adds an absolute reference with a folder and alters the project' {
        InModuleScope $script:moduleName {
            $references = [PSCustomObject]@{ AddedEnv = $null; AddedFolder = $null }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($environmentName, $environmentFolderName)
                $this.AddedEnv = $environmentName
                $this.AddedFolder = $environmentFolderName
            }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod' -EnvironmentFolder 'Shared'

            $project.References.AddedEnv | Should -Be 'Prod'
            $project.References.AddedFolder | Should -Be 'Shared'
            $project.AlterCalled | Should -BeTrue
        }
    }
}
```

`tests/Unit/Private/Remove-SsisEnvironmentReferenceObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentReferenceObject' {
    It 'Removes the supplied reference and alters the project' {
        InModuleScope $script:moduleName {
            $reference = [PSCustomObject]@{ EnvironmentName = 'Prod' }

            $references = [PSCustomObject]@{ Removed = $null }
            $references | Add-Member -MemberType 'ScriptMethod' -Name 'Remove' -Value { param ($item) $this.Removed = $item }

            $project = [PSCustomObject]@{ References = $references; AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Remove-SsisEnvironmentReferenceObject -Project $project -Reference $reference

            $project.References.Removed.EnvironmentName | Should -Be 'Prod'
            $project.AlterCalled | Should -BeTrue
        }
    }
}
```

`tests/Unit/Private/Set-SsisParameterObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisParameterObject' {
    It 'Sets a literal value on the parameter and alters the project' {
        InModuleScope $script:moduleName {
            $parameter = [PSCustomObject]@{ SetType = $null; SetValue = $null }
            $parameter | Add-Member -MemberType 'ScriptMethod' -Name 'Set' -Value {
                param ($valueType, $value)
                $this.SetType = $valueType
                $this.SetValue = $value
            }

            $project = [PSCustomObject]@{ AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisParameterObject -Parameter $parameter -ValueType 'Literal' -Value 1450 -Project $project

            $parameter.SetValue | Should -Be 1450
            $parameter.SetType.ToString() | Should -Be 'Literal'
            $project.AlterCalled | Should -BeTrue
        }
    }

    It 'Sets a referenced value on the parameter' {
        InModuleScope $script:moduleName {
            $parameter = [PSCustomObject]@{ SetType = $null; SetValue = $null }
            $parameter | Add-Member -MemberType 'ScriptMethod' -Name 'Set' -Value {
                param ($valueType, $value)
                $this.SetType = $valueType
                $this.SetValue = $value
            }

            $project = [PSCustomObject]@{ AlterCalled = $false }
            $project | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisParameterObject -Parameter $parameter -ValueType 'Referenced' -Value 'Port' -Project $project

            $parameter.SetValue | Should -Be 'Port'
            $parameter.SetType.ToString() | Should -Be 'Referenced'
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/New-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Set-SsisParameterObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/New-SsisEnvironmentReferenceObject.ps1`**

```powershell
function New-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Adds an environment reference to an SSISDB project and persists it.

        .DESCRIPTION
            Adds a reference binding the project to an environment and calls Alter() on the project to
            persist it. When EnvironmentFolder is supplied an absolute reference (to that folder's
            environment) is created; otherwise a relative reference (to an environment in the project's
            own folder) is created. Internal interop helper, not exported from the module.

        .EXAMPLE
            New-SsisEnvironmentReferenceObject -Project $project -Environment 'Prod'

            Adds a relative reference from the project to the Prod environment in its own folder.

        .PARAMETER Project
            The SSISDB ProjectInfo object to add the environment reference to.

        .PARAMETER Environment
            The name of the environment to reference from the project.

        .PARAMETER EnvironmentFolder
            The folder of the environment for an absolute reference. Omit for a relative reference to an
            environment in the project's own folder.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisEnvironmentReference) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter(Mandatory = $true)]
        [string]
        $Environment,

        [Parameter()]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('EnvironmentFolder'))
        {
            $null = $Project.References.Add($Environment, $EnvironmentFolder)
        }
        else
        {
            $null = $Project.References.Add($Environment)
        }

        $Project.Alter()
    }
}
```

- [ ] **Step 4: Write `source/Private/Remove-SsisEnvironmentReferenceObject.ps1`**

```powershell
function Remove-SsisEnvironmentReferenceObject
{
    <#
        .SYNOPSIS
            Removes an environment reference from an SSISDB project and persists the change.

        .DESCRIPTION
            Removes the supplied environment reference from the project's References collection and calls
            Alter() on the project to persist the removal. Internal interop helper, not exported from the
            module.

        .EXAMPLE
            Remove-SsisEnvironmentReferenceObject -Project $project -Reference $reference

            Removes the supplied reference from the project and alters it to persist the change.

        .PARAMETER Project
            The SSISDB ProjectInfo object the reference belongs to and is altered to persist the change.

        .PARAMETER Reference
            The EnvironmentReference object to remove, as returned by Get-SsisEnvironmentReferenceObject.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironmentReference) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter(Mandatory = $true)]
        [object]
        $Reference
    )

    process
    {
        $null = $Project.References.Remove($Reference)
        $Project.Alter()
    }
}
```

- [ ] **Step 5: Write `source/Private/Set-SsisParameterObject.ps1`**

```powershell
function Set-SsisParameterObject
{
    <#
        .SYNOPSIS
            Sets the value of an SSISDB parameter and persists the change.

        .DESCRIPTION
            Sets the parameter to a literal value or to a reference to an environment variable, then
            calls Alter() on the owning project to persist the change. The value type is supplied as the
            string 'Literal' or 'Referenced' and mapped to the object model's ParameterValueType here, so
            the rest of the module does not depend on the enum. Internal interop helper, not exported.

        .EXAMPLE
            Set-SsisParameterObject -Parameter $parameter -ValueType 'Literal' -Value 1450 -Project $project

            Sets the parameter to the literal value 1450 and alters the project to persist it.

        .PARAMETER Parameter
            The SSISDB ParameterInfo object whose value to set, as returned by Get-SsisParameterObject.

        .PARAMETER ValueType
            Either 'Literal' (use Value as the parameter value) or 'Referenced' (use Value as the name of
            an environment variable to bind the parameter to).

        .PARAMETER Value
            The literal value, or the environment variable name when ValueType is 'Referenced'.

        .PARAMETER Project
            The owning SSISDB ProjectInfo object, altered to persist the parameter change.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisParameter) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Parameter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Literal', 'Referenced')]
        [string]
        $ValueType,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Value,

        [Parameter(Mandatory = $true)]
        [object]
        $Project
    )

    process
    {
        $parameterValueType = [Microsoft.SqlServer.Management.IntegrationServices.ParameterInfo+ParameterValueType]::$ValueType
        $Parameter.Set($parameterValueType, $Value)
        $Project.Alter()
    }
}
```

- [ ] **Step 6: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/New-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentReferenceObject.tests.ps1, ./tests/Unit/Private/Set-SsisParameterObject.tests.ps1 -Output Detailed`
Expected: PASS (2 + 1 + 2 tests). The `Set-SsisParameterObject` tests load the real `ParameterInfo+ParameterValueType` enum (the module is imported), so a wrong enum name surfaces here — fix per Task 2 Step 6 if needed.

- [ ] **Step 7: Commit**

```powershell
git add -A
git commit -m "feat: add environment-reference add/remove and parameter set interop wrappers"
```

---

## Task 4: Public — `Get-SsisEnvironmentReference`

**Files:**
- Create: `source/Public/Get-SsisEnvironmentReference.ps1`
- Test: `tests/Unit/Public/Get-SsisEnvironmentReference.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisEnvironmentReference.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' })
        }
    }

    Context 'ByInstance' {
        It 'Returns references tagged Ssis.EnvironmentReference for a folder and project' {
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
            Should -Invoke -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Sales' }
        }

        It 'Warns and returns nothing when the project does not exist' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists references of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisEnvironmentReference
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisEnvironmentReference` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisEnvironmentReference.ps1`**

```powershell
function Get-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Gets the environment references defined on an SSISDB project.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the environment references of an
            SSISDB project as Ssis.EnvironmentReference objects. Each reference binds the project to an
            environment (relative to the project's folder, or absolute to a named folder). Accepts a
            piped Ssis.Project object to list its references without reconnecting. Writes a warning and
            returns nothing when the catalog, folder, or named project does not exist.

        .EXAMPLE
            Get-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the environment references defined on the Sales project.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | Get-SsisEnvironmentReference

            Returns the environment references of the piped Sales project.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose references to return.

        .PARAMETER Project
            The name of the project whose environment references to return.

        .PARAMETER InputObject
            A piped Ssis.Project object whose references to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject pipeline.

        .OUTPUTS
            Ssis.EnvironmentReference
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentReference')]
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
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projectObject = $InputObject
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
                Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Warning -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }
        }

        $references = Get-SsisEnvironmentReferenceObject -Project $projectObject

        foreach ($reference in $references)
        {
            if ($null -ne $reference)
            {
                $reference | Add-SsisTypeName -TypeName 'Ssis.EnvironmentReference'
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: PASS (3 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisEnvironmentReference command.` under `## [Unreleased]` → `### Added` in `CHANGELOG.md`.
```powershell
git add -A
git commit -m "feat: add Get-SsisEnvironmentReference command"
```

---

## Task 5: Public — `New-SsisEnvironmentReference`

**Files:**
- Create: `source/Public/New-SsisEnvironmentReference.ps1`
- Test: `tests/Unit/Public/New-SsisEnvironmentReference.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/New-SsisEnvironmentReference.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { }
        # Empty before create; the created reference after create. Counter makes the second call return it.
        $script:refCalls = 0
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            $script:refCalls++
            if ($script:refCalls -ge 2) { @([PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' }) }
            else { @() }
        }
    }

    It 'Creates a relative reference and returns it tagged Ssis.EnvironmentReference' {
        $script:refCalls = 0
        $result = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Environment -eq 'Prod' -and [string]::IsNullOrEmpty($EnvironmentFolder)
        }
    }

    It 'Passes -EnvironmentFolder through for an absolute reference' {
        $script:refCalls = 0
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -EnvironmentFolder 'Shared' -Confirm:$false
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $EnvironmentFolder -eq 'Shared' }
    }

    It 'Errors and does not create when the reference already exists' {
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { @([PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' }) }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the project does not exist' {
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -Environment 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not create' {
        $script:refCalls = 0
        $null = New-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -WhatIf
        Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Creates on a piped project without connecting' {
            $script:refCalls = 0
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $null = $project | New-SsisEnvironmentReference -Environment 'Prod' -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Project.Name -eq 'Sales' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/New-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: FAIL — `New-SsisEnvironmentReference` not recognized.

- [ ] **Step 3: Write `source/Public/New-SsisEnvironmentReference.ps1`**

```powershell
function New-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Creates an environment reference from an SSISDB project to an environment.

        .DESCRIPTION
            Connects to the specified SQL Server instance and adds an environment reference to a project.
            When -EnvironmentFolder is omitted a relative reference (to an environment in the project's
            own folder) is created; when supplied an absolute reference to that folder's environment is
            created. Accepts a piped Ssis.Project object as the target. Writes an error and makes no
            change when a matching reference already exists, or when the catalog, folder, or project does
            not exist. Returns the new reference as an Ssis.EnvironmentReference object.

        .EXAMPLE
            New-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Environment 'Prod'

            Creates a relative reference from the Sales project to the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | New-SsisEnvironmentReference -Environment 'Prod' -EnvironmentFolder 'Shared'

            Creates an absolute reference from the piped project to the Prod environment in the Shared folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to add the reference to.

        .PARAMETER Project
            The name of the project to add the environment reference to.

        .PARAMETER InputObject
            A piped Ssis.Project object to add the reference to, instead of -SqlInstance/-Folder/-Project,
            keeping the existing connection from a Get-SsisProject pipeline.

        .PARAMETER Environment
            The name of the environment to reference from the project.

        .PARAMETER EnvironmentFolder
            The folder of the environment for an absolute reference. Omit for a relative reference to an
            environment in the project's own folder.

        .OUTPUTS
            Ssis.EnvironmentReference
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentReference')]
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
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Environment,

        [Parameter()]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projectObject = $InputObject
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

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }
        }

        $folderBound = $PSBoundParameters.ContainsKey('EnvironmentFolder')

        $existing = Get-SsisEnvironmentReferenceObject -Project $projectObject |
            Where-Object -FilterScript {
                $_.EnvironmentName -eq $Environment -and
                (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                 (-not $folderBound -and [string]::IsNullOrEmpty($_.EnvironmentFolderName)))
            }

        if ($null -ne $existing)
        {
            Write-Error -Message ('An environment reference to ''{0}'' already exists on project ''{1}''.' -f $Environment, $projectObject.Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Environment, 'Create SSIS environment reference'))
        {
            $referenceParameters = @{
                Project     = $projectObject
                Environment = $Environment
            }

            if ($folderBound)
            {
                $referenceParameters['EnvironmentFolder'] = $EnvironmentFolder
            }

            New-SsisEnvironmentReferenceObject @referenceParameters

            $new = Get-SsisEnvironmentReferenceObject -Project $projectObject |
                Where-Object -FilterScript {
                    $_.EnvironmentName -eq $Environment -and
                    (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                     (-not $folderBound -and [string]::IsNullOrEmpty($_.EnvironmentFolderName)))
                }

            $new | Add-SsisTypeName -TypeName 'Ssis.EnvironmentReference'
        }
    }
}
```

> Persistence note (spec §10.5): if the integration test shows the in-memory `$projectObject.References` does not include the new reference after `Alter()`, re-resolve the project before the second `Get-SsisEnvironmentReferenceObject` — in the `ByInstance` path call `Get-SsisProjectObject -Folder $folderObject -Name $Project` again and pass that; in `ByObject`, accept that the returned object may need a `Get-SsisEnvironmentReference` round-trip. Confirm during Task 10.

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/New-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: PASS (6 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- New-SsisEnvironmentReference command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add New-SsisEnvironmentReference command"
```

---

## Task 6: Public — `Remove-SsisEnvironmentReference`

**Files:**
- Create: `source/Public/Remove-SsisEnvironmentReference.ps1`
- Test: `tests/Unit/Public/Remove-SsisEnvironmentReference.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Remove-SsisEnvironmentReference.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentReference' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = '' })
        }
        Mock -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { }
    }

    Context 'ByInstance' {
        It 'Removes the matching reference' {
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -Confirm:$false
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Reference.EnvironmentName -eq 'Prod' }
        }

        It 'Errors and does not remove when no matching reference exists' {
            Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith { @() }
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
            $err | Should -Not -BeNullOrEmpty
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Supports -WhatIf and does not remove' {
            Remove-SsisEnvironmentReference -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Environment 'Prod' -WhatIf
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }

    Context 'ByObject' {
        It 'Removes a piped reference via its parent project without connecting' {
            $reference = [PSCustomObject]@{ EnvironmentName = 'Prod'; EnvironmentFolderName = ''; Parent = [PSCustomObject]@{ Name = 'Sales' } }
            $reference.PSObject.TypeNames.Insert(0, 'Ssis.EnvironmentReference')

            $reference | Remove-SsisEnvironmentReference -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Reference.EnvironmentName -eq 'Prod' -and $Project.Name -eq 'Sales'
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: FAIL — `Remove-SsisEnvironmentReference` not recognized.

- [ ] **Step 3: Write `source/Public/Remove-SsisEnvironmentReference.ps1`**

```powershell
function Remove-SsisEnvironmentReference
{
    <#
        .SYNOPSIS
            Removes an environment reference from an SSISDB project.

        .DESCRIPTION
            Connects to the specified SQL Server instance and removes the environment reference matching
            -Environment (and -EnvironmentFolder, when given) from a project. Accepts a piped
            Ssis.EnvironmentReference object, reaching its project via its Parent. Writes an error when no
            matching reference exists, or when the catalog, folder, or project does not exist. This is a
            destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Environment 'Prod'

            Removes the relative reference to the Prod environment from the Sales project.

        .EXAMPLE
            Get-SsisEnvironmentReference -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' | Remove-SsisEnvironmentReference

            Removes each piped environment reference from its project.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose reference to remove.

        .PARAMETER Project
            The name of the project whose environment reference to remove.

        .PARAMETER InputObject
            A piped Ssis.EnvironmentReference object to remove, instead of
            -SqlInstance/-Folder/-Project/-Environment, keeping the existing connection from a
            Get-SsisEnvironmentReference pipeline.

        .PARAMETER Environment
            The name of the referenced environment identifying which reference to remove.

        .PARAMETER EnvironmentFolder
            The environment's folder, identifying an absolute reference. Omit to match the relative
            reference to that environment.

        .OUTPUTS
            None
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
        $Project,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Environment,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $EnvironmentFolder
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $projectObject = $InputObject.Parent
            $reference = $InputObject
            $environmentName = $InputObject.EnvironmentName
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

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Error -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Error -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }

            $folderBound = $PSBoundParameters.ContainsKey('EnvironmentFolder')

            $reference = Get-SsisEnvironmentReferenceObject -Project $projectObject |
                Where-Object -FilterScript {
                    $_.EnvironmentName -eq $Environment -and
                    (($folderBound -and $_.EnvironmentFolderName -eq $EnvironmentFolder) -or
                     (-not $folderBound -and [string]::IsNullOrEmpty($_.EnvironmentFolderName)))
                }

            if ($null -eq $reference)
            {
                Write-Error -Message ('No environment reference to ''{0}'' was found on project ''{1}''.' -f $Environment, $Project)
                return
            }

            $environmentName = $Environment
        }

        if ($PSCmdlet.ShouldProcess($environmentName, 'Remove SSIS environment reference'))
        {
            Remove-SsisEnvironmentReferenceObject -Project $projectObject -Reference $reference
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironmentReference.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Remove-SsisEnvironmentReference command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Remove-SsisEnvironmentReference command"
```

---

## Task 7: Public — `Get-SsisParameter`

**Files:**
- Create: `source/Public/Get-SsisParameter.ps1`
- Test: `tests/Unit/Public/Get-SsisParameter.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisParameter.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisParameter' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'TargetPort' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns project-level parameters tagged Ssis.Parameter' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Scopes to a package when -Package is given' {
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Load.dtsx' }
        }

        It 'Warns and returns nothing when the project does not exist' {
            Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists parameters of a piped project without connecting' {
            $project = [PSCustomObject]@{ Name = 'Sales' }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $result = $project | Get-SsisParameter
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Container.Name -eq 'Sales' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisParameter.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisParameter` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisParameter.ps1`**

```powershell
function Get-SsisParameter
{
    <#
        .SYNOPSIS
            Gets parameters from a project or package in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB parameters as Ssis.Parameter
            objects. Returns the project's parameters by default, or a package's parameters when -Package
            is given, narrowing to a single parameter with -Name. Accepts a piped Ssis.Project or
            Ssis.Package object to list its parameters without reconnecting. Writes a warning and returns
            nothing when the catalog, folder, project, or named package does not exist.

        .EXAMPLE
            Get-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales'

            Returns the project-level parameters of the Sales project.

        .EXAMPLE
            Get-SsisProject -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Sales' | Get-SsisParameter

            Returns the project-level parameters of the piped Sales project.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose parameters to return.

        .PARAMETER Project
            The name of the project whose parameters to return.

        .PARAMETER Package
            The name of a package within the project whose parameters to return. When omitted,
            project-level parameters are returned.

        .PARAMETER InputObject
            A piped Ssis.Project or Ssis.Package object whose parameters to list. Used instead of
            -SqlInstance/-Folder/-Project to keep the existing connection from a Get-SsisProject or
            Get-SsisPackage pipeline.

        .PARAMETER Name
            The name of a specific parameter to return. When omitted, all parameters in scope are returned.

        .OUTPUTS
            Ssis.Parameter
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Parameter')]
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
        $Project,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $parameterParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $parameterParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $container = $InputObject
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
                Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Warning -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }

            if ($PSBoundParameters.ContainsKey('Package'))
            {
                $container = Get-SsisPackageObject -Project $projectObject -Name $Package

                if ($null -eq $container)
                {
                    Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                    return
                }
            }
            else
            {
                $container = $projectObject
            }
        }

        $parameters = Get-SsisParameterObject -Container $container @parameterParameters

        foreach ($parameter in $parameters)
        {
            if ($null -ne $parameter)
            {
                $parameter | Add-SsisTypeName -TypeName 'Ssis.Parameter'
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisParameter.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisParameter command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Get-SsisParameter command"
```

---

## Task 8: Public — `Set-SsisParameter`

**Files:**
- Create: `source/Public/Set-SsisParameter.ps1`
- Test: `tests/Unit/Public/Set-SsisParameter.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Set-SsisParameter.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisParameter' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'TargetPort'; Value = 1450 } }
        Mock -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Sets a literal value and returns Ssis.Parameter' {
        $result = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1450 -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Literal' -and $Value -eq 1450
        }
    }

    It 'Sets a referenced value with the variable name' {
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -ReferencedVariable 'Port' -Confirm:$false
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ValueType -eq 'Referenced' -and $Value -eq 'Port'
        }
    }

    It 'Throws when both -Value and -ReferencedVariable are supplied' {
        { Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1 -ReferencedVariable 'Port' -Confirm:$false } |
            Should -Throw
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Throws when neither -Value nor -ReferencedVariable is supplied' {
        { Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Confirm:$false } |
            Should -Throw
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not set when the parameter does not exist' {
        Mock -CommandName Get-SsisParameterObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'Missing' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not set' {
        $null = Set-SsisParameter -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1 -WhatIf
        Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Sets a piped parameter via its owning project without connecting' {
            $parameter = [PSCustomObject]@{ Name = 'TargetPort'; Parent = [PSCustomObject]@{ Name = 'Sales' } }
            $parameter.PSObject.TypeNames.Insert(0, 'Ssis.Parameter')

            $null = $parameter | Set-SsisParameter -Value 1450 -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Set-SsisParameterObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Parameter.Name -eq 'TargetPort' -and $Project.Name -eq 'Sales'
            }
        }
    }
}
```

> The `Parent` of the piped parameter is a plain object whose `GetType().Name` is `PSCustomObject` (not `PackageInfo`), so the public function treats it as the owning project — exactly what the ByObject test asserts.

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Set-SsisParameter.tests.ps1 -Output Detailed`
Expected: FAIL — `Set-SsisParameter` not recognized.

- [ ] **Step 3: Write `source/Public/Set-SsisParameter.ps1`**

```powershell
function Set-SsisParameter
{
    <#
        .SYNOPSIS
            Sets the value of a project or package parameter in the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and sets an SSISDB parameter's value, either to
            a literal (-Value) or to a reference to an environment variable (-ReferencedVariable). The two
            are mutually exclusive; supplying both, or neither, is an error. Targets a project-level
            parameter by default, or a package-level parameter when -Package is given. Accepts a piped
            Ssis.Parameter object. Writes a warning and makes no change when the catalog, folder, project,
            package, or named parameter does not exist. Returns the resulting Ssis.Parameter.

        .EXAMPLE
            Set-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -Value 1450

            Sets the TargetPort project parameter to the literal value 1450.

        .EXAMPLE
            Set-SsisParameter -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'TargetPort' -ReferencedVariable 'Port'

            Binds the TargetPort parameter to the Port environment variable.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project whose parameter to set.

        .PARAMETER Project
            The name of the project whose parameter to set.

        .PARAMETER Package
            The name of a package within the project whose parameter to set. When omitted, a project-level
            parameter is set.

        .PARAMETER InputObject
            A piped Ssis.Parameter object to set, instead of -SqlInstance/-Folder/-Project/-Name, keeping
            the existing connection from a Get-SsisParameter pipeline.

        .PARAMETER Name
            The name of the parameter to set.

        .PARAMETER Value
            The literal value to assign to the parameter. Mutually exclusive with -ReferencedVariable.

        .PARAMETER ReferencedVariable
            The name of an environment variable to bind the parameter to. Mutually exclusive with -Value.

        .OUTPUTS
            Ssis.Parameter
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Parameter')]
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
        $Project,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name,

        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [string]
        $ReferencedVariable
    )

    process
    {
        $hasValue = $PSBoundParameters.ContainsKey('Value')
        $hasReference = $PSBoundParameters.ContainsKey('ReferencedVariable')

        if ($hasValue -eq $hasReference)
        {
            throw 'Specify exactly one of -Value or -ReferencedVariable.'
        }

        if ($hasValue)
        {
            $valueType = 'Literal'
            $effectiveValue = $Value
        }
        else
        {
            $valueType = 'Referenced'
            $effectiveValue = $ReferencedVariable
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $parameter = $InputObject
            $container = $InputObject.Parent

            if ($container.GetType().Name -eq 'PackageInfo')
            {
                $projectObject = $container.Parent
            }
            else
            {
                $projectObject = $container
            }

            $parameterName = $InputObject.Name
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
                Write-Warning -Message ('The SSISDB catalog does not exist on ''{0}''.' -f $SqlInstance)
                return
            }

            $folderObject = Get-SsisFolderObject -Catalog $catalog -Name $Folder

            if ($null -eq $folderObject)
            {
                Write-Warning -Message ('Folder ''{0}'' was not found in the SSISDB catalog.' -f $Folder)
                return
            }

            $projectObject = Get-SsisProjectObject -Folder $folderObject -Name $Project

            if ($null -eq $projectObject)
            {
                Write-Warning -Message ('Project ''{0}'' was not found in folder ''{1}''.' -f $Project, $Folder)
                return
            }

            if ($PSBoundParameters.ContainsKey('Package'))
            {
                $container = Get-SsisPackageObject -Project $projectObject -Name $Package

                if ($null -eq $container)
                {
                    Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                    return
                }
            }
            else
            {
                $container = $projectObject
            }

            $parameter = Get-SsisParameterObject -Container $container -Name $Name

            if ($null -eq $parameter)
            {
                Write-Warning -Message ('Parameter ''{0}'' was not found.' -f $Name)
                return
            }

            $parameterName = $Name
        }

        if ($PSCmdlet.ShouldProcess($parameterName, 'Set SSIS parameter value'))
        {
            $splatSetParameter = @{
                Parameter = $parameter
                ValueType = $valueType
                Value     = $effectiveValue
                Project   = $projectObject
            }

            Set-SsisParameterObject @splatSetParameter

            $updated = Get-SsisParameterObject -Container $container -Name $parameterName
            $updated | Add-SsisTypeName -TypeName 'Ssis.Parameter'
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Set-SsisParameter.tests.ps1 -Output Detailed`
Expected: PASS (7 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Set-SsisParameter command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Set-SsisParameter command"
```

---

## Task 9: Extend the test fixture with a project parameter

The Phase 2 `.ispac` fixture contains a single empty package and **no parameters**, so it cannot
exercise `Set-SsisParameter` end to end (and `Set-SsisParameterObject` would stay uncovered). Add a
project parameter to the fixture generator and regenerate the committed `.ispac`.

**Files:**
- Modify: `tests/Integration/fixtures/New-TestProjectIspac.ps1`
- Modify (regenerate): `tests/Integration/fixtures/ISTools_TestProject.ispac`

- [ ] **Step 1: Add a project parameter to the generator**

In `tests/Integration/fixtures/New-TestProjectIspac.ps1`, inside the `try { … }` block, **after** the
`$null = $project.PackageItems.Add($package, 'Package.dtsx')` line and **before** `$project.Save()`,
insert:

```powershell
    # A single project parameter so the references/parameters integration test can set its value.
    $parameter = $project.Parameters.Add('TargetPort', [System.TypeCode]::Int32)
    $parameter.Value = 0
```

- [ ] **Step 2: Regenerate the fixture**

Run from the repo root:
```powershell
./build.ps1 -Tasks build
./tests/Integration/fixtures/New-TestProjectIspac.ps1
```
Expected: writes `tests/Integration/fixtures/ISTools_TestProject.ispac` (returns its `FileInfo`). If `Parameters.Add` has a different signature against the real `Microsoft.SqlServer.Dts.Runtime.Project`, adjust the call here (it is the only consumer) — confirm with:
```powershell
[Microsoft.SqlServer.Dts.Runtime.Project].GetMethod('CreateProject') | Should -Not -BeNullOrEmpty
# inspect the Parameters collection Add overloads:
([Microsoft.SqlServer.Dts.Runtime.Project]::CreateProject([System.IO.Path]::GetTempFileName())).Parameters.GetType().GetMethods().Name | Select-Object -Unique
```

- [ ] **Step 3: Verify the Phase 2 project test still passes with the new fixture**

If `$env:SSIS_TEST_INSTANCE` is configured, run the existing Phase 2 lifecycle to confirm the extra
parameter did not break deploy/export/remove:
```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path ./tests/Integration/Ssis.Project.Integration.tests.ps1 -Output Detailed
```
Expected: passes (or skips cleanly if no instance). The new parameter is harmless to deploy/export/remove.

- [ ] **Step 4: Commit**

```powershell
git add -A
git commit -m "test: add a project parameter to the .ispac fixture for parameter tests"
```

---

## Task 10: Integration test — references & parameters lifecycle

**Files:**
- Create: `tests/Integration/Ssis.Reference.Integration.tests.ps1`

- [ ] **Step 1: Write the integration test**

`tests/Integration/Ssis.Reference.Integration.tests.ps1`:
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
    $script:folderName = 'ISTools_RefTest'
    $script:projectName = 'ISTools_TestProject'
    $script:environmentName = 'RefEnv'

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

Describe 'Environment reference and parameter lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Binds a project to an environment and sets a parameter to a referenced variable' {
        # Deploy the project and create an environment with a matching variable in the same folder.
        Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false | Out-Null
        New-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Confirm:$false | Out-Null
        Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1433 -Confirm:$false | Out-Null

        # Create a relative environment reference (environment is in the project's own folder).
        $reference = New-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Environment $script:environmentName -Confirm:$false
        $reference.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentReference'

        # List references.
        $references = Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName
        ($references | Where-Object -FilterScript { $_.EnvironmentName -eq $script:environmentName } | Measure-Object).Count | Should -Be 1

        # Set the project parameter to a literal, then bind it to the environment variable.
        $literal = Set-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort' -Value 1450 -Confirm:$false
        $literal.PSObject.TypeNames | Should -Contain 'Ssis.Parameter'

        Set-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort' -ReferencedVariable 'Port' -Confirm:$false | Out-Null

        $parameter = Get-SsisParameter -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Name 'TargetPort'
        $parameter.ReferencedVariableName | Should -Be 'Port'

        # Remove the reference via the pipeline.
        Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName |
            Where-Object -FilterScript { $_.EnvironmentName -eq $script:environmentName } |
            Remove-SsisEnvironmentReference -Confirm:$false
        $after = Get-SsisEnvironmentReference -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName
        ($after | Where-Object -FilterScript { $_.EnvironmentName -eq $script:environmentName } | Measure-Object).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Verify it skips cleanly without an instance**

Run (with `$env:SSIS_TEST_INSTANCE` unset):
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path ./tests/Integration/Ssis.Reference.Integration.tests.ps1 -Output Detailed
```
Expected: the test is **skipped** (not failed). With a real `$env:SSIS_TEST_INSTANCE` it runs the full lifecycle and passes.

> If the parameter assertions fail because the in-memory project does not reflect the change after `Alter()`, apply the re-resolve note from Task 5 Step 3 to `New-SsisEnvironmentReference` and `Set-SsisParameter` (re-fetch the project before reading back), then re-run.

- [ ] **Step 3: Commit**

```powershell
git add -A
git commit -m "test: add environment reference and parameter integration lifecycle test"
```

---

## Task 11: Full QA gate and finalize

**Files:** none (verification only)

- [ ] **Step 1: Run the full build + test (QA + unit)**

Run: `./build.ps1 -Tasks build,test`
Expected: QA tests (help quality, PSScriptAnalyzer, manifest) pass for all new public and private functions; all new unit tests pass; integration tests skip cleanly without `$env:SSIS_TEST_INSTANCE`. The code-coverage gate (85%) is met only when Integration tests run against a real SSISDB — confirm no PSScriptAnalyzer or help failures.

- [ ] **Step 2: Verify the five commands are exported**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
'Get-SsisEnvironmentReference', 'New-SsisEnvironmentReference', 'Remove-SsisEnvironmentReference', 'Get-SsisParameter', 'Set-SsisParameter' |
    ForEach-Object -Process { Get-Command -Module IntegrationServicesTools -Name $_ -ErrorAction Stop }
```
Expected: all five commands resolve.

- [ ] **Step 3: Full green run against a real instance (if available)**

If `$env:SSIS_TEST_INSTANCE` is configured, run the complete suite incl. integration + coverage:
```powershell
$env:SSIS_TEST_INSTANCE = 'localhost'   # or your test instance
./build.ps1 -Tasks build,test
```
Expected: all unit + QA + integration tests pass; code coverage ≥ 85%.

- [ ] **Step 4: Final commit if anything changed**

```powershell
git add -A
git commit -m "chore: finalize Phase 3b environment references & parameters" --allow-empty
```

---

## Self-review checklist (for the implementer before opening the PR)

- [ ] No backticks anywhere; splats used for 3+ params (`$splatSetParameter`, `$referenceParameters`), hashtables aligned.
- [ ] Allman braces, single quotes for non-interpolated strings, `Mandatory = $true`, 4-space indent, no trailing whitespace.
- [ ] PS5.1-compatible (Desktop); the MOM enum is referenced only inside `Set-SsisParameterObject`.
- [ ] Every new function (public + private) has its own `<Name>.tests.ps1`, full comment-based help; public functions have `.OUTPUTS`.
- [ ] State-changers (`New`/`Set`/`Remove`) declare `SupportsShouldProcess`; `Remove-*` is `ConfirmImpact High`; interop wrappers carry the `SuppressMessage` justification.
- [ ] `Set-SsisParameter` mutual-exclusion guard (`-Value` vs `-ReferencedVariable`) errors on both/neither.
- [ ] Returns `Ssis.EnvironmentReference` / `Ssis.Parameter`-decorated objects; pipeline output emitted immediately.
- [ ] Each interop call behind a `*-Ssis*Object` wrapper; unit tests mock the seam and pass.
- [ ] `./build.ps1 -Tasks test` green for QA + unit; integration tests skip cleanly without `$env:SSIS_TEST_INSTANCE`.
- [ ] Commit messages use Conventional Commits.
```
