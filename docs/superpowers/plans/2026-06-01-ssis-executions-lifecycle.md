# SSIS Execution Lifecycle (Phase 4a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Start-SsisExecution`, `Stop-SsisExecution`, `Get-SsisExecution`, and `Wait-SsisExecution` to the module, covering the SSISDB package-execution lifecycle.

**Architecture:** Four public commands over a thin private interop seam (`Start/Get/Stop/Update-SsisExecutionObject`), one per distinct MOM call. `Wait-SsisExecution` owns a logical-time poll loop; `Start -Synchronous` delegates to it via the ByObject path. Executions are returned as native `ExecutionOperation` objects decorated with the new `Ssis.Execution` PSTypeName and a `format.ps1xml` table view.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder, Pester v5, the `Microsoft.SqlServer.Management.IntegrationServices` MOM (loaded from `dbatools.library`).

**Spec:** `docs/superpowers/specs/2026-06-01-ssis-executions-lifecycle-design.md`

---

## Conventions for every task

- **Rebuild before testing.** ModuleBuilder merges `source/` into `output/module`, and the test
  files `Import-Module IntegrationServicesTools` by name. After any change under `source/`, run
  `./build.ps1 -Tasks build` before running tests, so the imported module reflects your edit.
- **Single-file test runs** need both built folders on the module path. Use this exact form:

  ```powershell
  $env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
  Invoke-Pester -Path <test-file> -Output Detailed
  ```

- **House style (enforced by QA):** Allman braces, single quotes, `Mandatory = $true`, 4-space
  indent, no backticks, splat (`$splat<Purpose>`, aligned) for 3+ params, `::new()` allowed.
  Full comment-based help (incl. `.OUTPUTS`) on every public **and** private function.
- **Shared status vocabulary** (used across several tasks):
  - ValidateSet for `-Status`: `'Created','Running','Cancelled','Failed','Pending','EndedUnexpectedly','Succeeded','Stopping','Completed'`.
  - Terminal states (waiting stops): `'Succeeded','Failed','Cancelled','EndedUnexpectedly','Completed'`.

---

## File structure

**Create (source):**
- `source/Private/Get-SsisExecutionObject.ps1` — enumerate `Catalog.Executions` or index by id.
- `source/Private/Update-SsisExecutionObject.ps1` — `ExecutionOperation.Refresh()` (poll primitive).
- `source/Private/Stop-SsisExecutionObject.ps1` — `ExecutionOperation.Stop()`.
- `source/Private/Start-SsisExecutionObject.ps1` — build value-parameter sets and call `PackageInfo.Execute(...)`.
- `source/Public/Get-SsisExecution.ps1`
- `source/Public/Wait-SsisExecution.ps1`
- `source/Public/Stop-SsisExecution.ps1`
- `source/Public/Start-SsisExecution.ps1`

**Create (tests):**
- `tests/Unit/Private/Get-SsisExecutionObject.tests.ps1`
- `tests/Unit/Private/Update-SsisExecutionObject.tests.ps1`
- `tests/Unit/Private/Stop-SsisExecutionObject.tests.ps1`
- `tests/Unit/Private/Start-SsisExecutionObject.tests.ps1`
- `tests/Unit/Public/Get-SsisExecution.tests.ps1`
- `tests/Unit/Public/Wait-SsisExecution.tests.ps1`
- `tests/Unit/Public/Stop-SsisExecution.tests.ps1`
- `tests/Unit/Public/Start-SsisExecution.tests.ps1`
- `tests/Integration/Ssis.Execution.Integration.tests.ps1`

**Modify:**
- `source/IntegrationServicesTools.format.ps1xml` — add the `Ssis.Execution` view.

---

## Task 1: Add the `Ssis.Execution` format view

**Files:**
- Modify: `source/IntegrationServicesTools.format.ps1xml` (add a `<View>` before the closing `</ViewDefinitions>`)

- [ ] **Step 1: Add the view**

Insert this `<View>` immediately before the `</ViewDefinitions>` line (after the `Ssis.Parameter` view):

```xml
    <View>
      <Name>Ssis.Execution</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Execution</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Id</Label></TableColumnHeader>
          <TableColumnHeader><Label>Folder</Label></TableColumnHeader>
          <TableColumnHeader><Label>Project</Label></TableColumnHeader>
          <TableColumnHeader><Label>Package</Label></TableColumnHeader>
          <TableColumnHeader><Label>Status</Label></TableColumnHeader>
          <TableColumnHeader><Label>StartTime</Label></TableColumnHeader>
          <TableColumnHeader><Label>EndTime</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Id</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>FolderName</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>ProjectName</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>PackageName</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Status</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>StartTime</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>EndTime</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
```

- [ ] **Step 2: Build to verify the format file is well-formed**

Run: `./build.ps1 -Tasks build`
Expected: build succeeds (a malformed `.ps1xml` fails the build/import).

- [ ] **Step 3: Commit**

```powershell
git add source/IntegrationServicesTools.format.ps1xml
git commit -m "feat: add Ssis.Execution format view"
```

---

## Task 2: `Get-SsisExecutionObject` (interop seam — enumerate / index)

**Files:**
- Create: `source/Private/Get-SsisExecutionObject.ps1`
- Test: `tests/Unit/Private/Get-SsisExecutionObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionObject' {
    It 'Returns the whole Executions collection when no id is given' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Executions = @('exec1', 'exec2') }
            $result = Get-SsisExecutionObject -Catalog $catalog
            $result | Should -Be @('exec1', 'exec2')
        }
    }

    It 'Indexes the collection by id when -ExecutionId is given' {
        InModuleScope $script:moduleName {
            $executions = [PSCustomObject]@{}
            $executions | Add-Member -MemberType 'ScriptMethod' -Name 'get_Item' -Value { param ($id) "exec-$id" }
            $catalog = [PSCustomObject]@{ Executions = $executions }

            $result = Get-SsisExecutionObject -Catalog $catalog -ExecutionId 42
            $result | Should -Be 'exec-42'
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisExecutionObject` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Get-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Returns SSISDB executions from a catalog, optionally a single one by id.

        .DESCRIPTION
            Returns the catalog's Executions collection, or a single ExecutionOperation when
            -ExecutionId is supplied (indexed from the collection). Internal interop helper, not
            exported from the module.

        .EXAMPLE
            $executions = Get-SsisExecutionObject -Catalog $catalog

            Returns every execution recorded in the catalog.

        .EXAMPLE
            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId 42

            Returns the execution with id 42.

        .PARAMETER Catalog
            The SSISDB Catalog object whose executions to read, as returned by Get-SsisCatalogObject.

        .PARAMETER ExecutionId
            The numeric id of a single execution to return. When omitted, the whole collection is
            returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter()]
        [long]
        $ExecutionId
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('ExecutionId'))
        {
            return $Catalog.Executions[$ExecutionId]
        }

        return $Catalog.Executions
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Get-SsisExecutionObject.ps1 tests/Unit/Private/Get-SsisExecutionObject.tests.ps1
git commit -m "feat: add Get-SsisExecutionObject interop wrapper"
```

---

## Task 3: `Update-SsisExecutionObject` (interop seam — refresh)

**Files:**
- Create: `source/Private/Update-SsisExecutionObject.ps1`
- Test: `tests/Unit/Private/Update-SsisExecutionObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Update-SsisExecutionObject' {
    It 'Calls Refresh on the execution and returns it' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ RefreshCalled = $false }
            $execution | Add-Member -MemberType 'ScriptMethod' -Name 'Refresh' -Value { $this.RefreshCalled = $true }

            $result = Update-SsisExecutionObject -Execution $execution

            $execution.RefreshCalled | Should -BeTrue
            $result | Should -Be $execution
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Update-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Update-SsisExecutionObject` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Update-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Refreshes an SSISDB execution from the server and returns it.

        .DESCRIPTION
            Calls Refresh() on the ExecutionOperation so its Status and timing properties reflect the
            current server state, then returns the same object. Used as the poll primitive by
            Wait-SsisExecution. Internal interop helper, not exported from the module.

        .EXAMPLE
            $execution = Update-SsisExecutionObject -Execution $execution

            Refreshes the execution and returns it with up-to-date Status.

        .PARAMETER Execution
            The ExecutionOperation object to refresh, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        $Execution.Refresh()
        return $Execution
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Update-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Update-SsisExecutionObject.ps1 tests/Unit/Private/Update-SsisExecutionObject.tests.ps1
git commit -m "feat: add Update-SsisExecutionObject interop wrapper"
```

---

## Task 4: `Stop-SsisExecutionObject` (interop seam — stop)

**Files:**
- Create: `source/Private/Stop-SsisExecutionObject.ps1`
- Test: `tests/Unit/Private/Stop-SsisExecutionObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Stop-SsisExecutionObject' {
    It 'Calls Stop on the execution' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ StopCalled = $false }
            $execution | Add-Member -MemberType 'ScriptMethod' -Name 'Stop' -Value { $this.StopCalled = $true }

            Stop-SsisExecutionObject -Execution $execution

            $execution.StopCalled | Should -BeTrue
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Stop-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Stop-SsisExecutionObject` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Stop-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Stops a running SSISDB execution.

        .DESCRIPTION
            Calls Stop() on the ExecutionOperation, requesting the server cancel the running package.
            Internal interop helper, not exported from the module.

        .EXAMPLE
            Stop-SsisExecutionObject -Execution $execution

            Requests cancellation of the running execution.

        .PARAMETER Execution
            The ExecutionOperation object to stop, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            None.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Stop-SsisExecution) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        $Execution.Stop()
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Stop-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Stop-SsisExecutionObject.ps1 tests/Unit/Private/Stop-SsisExecutionObject.tests.ps1
git commit -m "feat: add Stop-SsisExecutionObject interop wrapper"
```

---

## Task 5: `Start-SsisExecutionObject` (interop seam — execute)

**Files:**
- Create: `source/Private/Start-SsisExecutionObject.ps1`
- Test: `tests/Unit/Private/Start-SsisExecutionObject.tests.ps1`

This wrapper builds the `ExecutionValueParameterSet` collection (logging level → object type 50;
each `-Parameter` entry → object type 30 if it is a package parameter, else 20) and calls
`PackageInfo.Execute(use32Bit, reference, setValueParameters)`, returning the `[long]` id.

Because constructing the real generic `Collection[...]` and nested `ExecutionValueParameterSet`
types requires the loaded MOM assemblies, the implementation builds the value set from
`[PSCustomObject]` entries whose property names (`ObjectType`/`ParameterName`/`ParameterValue`)
match the real type's members. This keeps the seam unit-testable without the MOM loaded — the test
drives a fake `$Package` whose `Execute` method captures the arguments it receives and asserts on
them. The live `.NET` construction is exercised by the Task 10 integration test.

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisExecutionObject' {
    It 'Calls Execute with the 32-bit flag and the reference, and returns the id' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{ Use32 = $null; Ref = $null; SetCount = $null }
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{}
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $this.Use32 = $use32
                $this.Ref = $reference
                $this.SetCount = $setValues.Count
                return [long] 99
            }

            $result = Start-SsisExecutionObject -Package $package -Reference 'theRef' -Use32BitRuntime

            $result | Should -Be 99
            $package.Use32 | Should -BeTrue
            $package.Ref | Should -Be 'theRef'
            $package.SetCount | Should -Be 0
        }
    }

    It 'Adds a logging-level value set (object type 50) when -LoggingLevel is given' {
        InModuleScope $script:moduleName {
            $captured = $null
            $package = [PSCustomObject]@{}
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{}
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $script:captured = $setValues
                return [long] 1
            }

            $null = Start-SsisExecutionObject -Package $package -Reference $null -LoggingLevel 'Verbose'

            $script:captured.Count | Should -Be 1
            $script:captured[0].ObjectType | Should -Be 50
            $script:captured[0].ParameterName | Should -Be 'LOGGING_LEVEL'
            $script:captured[0].ParameterValue | Should -Be 3
        }
    }

    It 'Resolves parameter scope: package parameter is object type 30, project parameter 20' {
        InModuleScope $script:moduleName {
            $package = [PSCustomObject]@{}
            # Only 'PkgParam' is a package parameter; 'ProjParam' is not.
            $package | Add-Member -MemberType 'NoteProperty' -Name 'Parameters' -Value @{ 'PkgParam' = 'x' }
            $package | Add-Member -MemberType 'ScriptMethod' -Name 'Execute' -Value {
                param ($use32, $reference, $setValues)
                $script:captured = $setValues
                return [long] 1
            }

            $null = Start-SsisExecutionObject -Package $package -Reference $null -Parameter @{ 'PkgParam' = 1; 'ProjParam' = 2 }

            $pkg = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'PkgParam' }
            $proj = $script:captured | Where-Object -FilterScript { $_.ParameterName -eq 'ProjParam' }
            $pkg.ObjectType | Should -Be 30
            $proj.ObjectType | Should -Be 20
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Start-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Start-SsisExecutionObject` is not recognized.

- [ ] **Step 3: Write the implementation**

The value-set entries are created with `[PSCustomObject]` so the seam stays unit-testable without
the MOM type loaded; the property names (`ObjectType`/`ParameterName`/`ParameterValue`) match the
real `ExecutionValueParameterSet` members, so the same code path works against the live type when
the assemblies are loaded. `Execute` accepts the list positionally.

```powershell
function Start-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Starts an SSISDB package execution and returns its id.

        .DESCRIPTION
            Builds the execution value-parameter sets from the logging level (object type 50,
            LOGGING_LEVEL) and each supplied parameter (object type 30 for a package parameter, 20 for
            a project parameter), then calls Execute() on the package with the 32-bit runtime flag and
            the optional environment reference. Returns the numeric execution id. Internal interop
            helper, not exported from the module.

        .EXAMPLE
            $id = Start-SsisExecutionObject -Package $package -Reference $reference -LoggingLevel 'Basic'

            Starts the package with Basic logging bound to the given environment reference.

        .PARAMETER Package
            The SSISDB PackageInfo object to execute, as returned by Get-SsisPackageObject.

        .PARAMETER Reference
            The EnvironmentReference to bind the execution to, or $null for none.

        .PARAMETER Parameter
            A hashtable of parameter name/value overrides to set for this run.

        .PARAMETER LoggingLevel
            One of None, Basic, Performance or Verbose; applied as the LOGGING_LEVEL system value.

        .PARAMETER Use32BitRuntime
            When set, runs the package in the 32-bit runtime.

        .OUTPUTS
            System.Int64
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Start-SsisExecution) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Package,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Reference,

        [Parameter()]
        [hashtable]
        $Parameter,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Performance', 'Verbose')]
        [string]
        $LoggingLevel,

        [Parameter()]
        [switch]
        $Use32BitRuntime
    )

    process
    {
        $loggingValues = @{
            None        = 0
            Basic       = 1
            Performance = 2
            Verbose     = 3
        }

        $setValues = [System.Collections.Generic.List[object]]::new()

        if ($PSBoundParameters.ContainsKey('LoggingLevel'))
        {
            $setValues.Add([PSCustomObject]@{
                ObjectType     = 50
                ParameterName  = 'LOGGING_LEVEL'
                ParameterValue = $loggingValues[$LoggingLevel]
            })
        }

        if ($PSBoundParameters.ContainsKey('Parameter'))
        {
            foreach ($parameterName in $Parameter.Keys)
            {
                if ($Package.Parameters.ContainsKey($parameterName))
                {
                    $objectType = 30
                }
                else
                {
                    $objectType = 20
                }

                $setValues.Add([PSCustomObject]@{
                    ObjectType     = $objectType
                    ParameterName  = $parameterName
                    ParameterValue = $Parameter[$parameterName]
                })
            }
        }

        return $Package.Execute($Use32BitRuntime.IsPresent, $Reference, $setValues)
    }
}
```

> **Integration note for the executor:** against the live MOM, `$Package.Parameters` is a
> `ParameterInfoCollection` (use `$Package.Parameters.Contains($name)` if `ContainsKey` is absent)
> and `Execute` expects a `Collection[PackageInfo+ExecutionValueParameterSet]`. If the live call
> rejects the `[PSCustomObject]` list, convert each entry to the real nested type inside this wrapper
> (the only place that touches the MOM type). Keep the public surface and unit tests unchanged.

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Start-SsisExecutionObject.tests.ps1 -Output Detailed
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Start-SsisExecutionObject.ps1 tests/Unit/Private/Start-SsisExecutionObject.tests.ps1
git commit -m "feat: add Start-SsisExecutionObject interop wrapper"
```

---

## Task 6: `Get-SsisExecution` (public — query)

**Files:**
- Create: `source/Public/Get-SsisExecution.ps1`
- Test: `tests/Unit/Public/Get-SsisExecution.tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        # Three executions spanning two packages and two statuses.
        $script:allExecutions = @(
            [PSCustomObject]@{ Id = 1; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
            [PSCustomObject]@{ Id = 2; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Succeeded' }
            [PSCustomObject]@{ Id = 3; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Other.dtsx'; Status = 'Running' }
        )
    }

    It 'Returns a single execution by id, decorated as Ssis.Execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42; FolderName = 'Finance'; ProjectName = 'Sales'; PackageName = 'Load.dtsx'; Status = 'Running' }
        } -ParameterFilter { $ExecutionId -eq 42 }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 42
        $result.Id | Should -Be 42
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
    }

    It 'Filters by package name when -Package is given' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx'
        ($result | Measure-Object).Count | Should -Be 2
        $result.PackageName | Should -Not -Contain 'Other.dtsx'
    }

    It 'Filters by -Status' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

        $result = Get-SsisExecution -SqlInstance 'TestInstance' -Status 'Running'
        ($result | Measure-Object).Count | Should -Be 2
        $result.Status | Should -Not -Contain 'Succeeded'
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecution -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Lists the executions of a piped package without reconnecting' {
            Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $script:allExecutions }

            $package = [PSCustomObject]@{
                Name   = 'Load.dtsx'
                Parent = [PSCustomObject]@{
                    Name   = 'Sales'
                    Parent = [PSCustomObject]@{
                        Name   = 'Finance'
                        Parent = [PSCustomObject]@{ Name = 'SSISDB' }
                    }
                }
            }
            $package.PSObject.TypeNames.Insert(0, 'Ssis.Package')

            $result = $package | Get-SsisExecution
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 2
            $result.PackageName | Should -Not -Contain 'Other.dtsx'
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisExecution.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisExecution` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Get-SsisExecution
{
    <#
        .SYNOPSIS
            Gets package executions from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB executions as
            Ssis.Execution objects. Returns a single execution when -ExecutionId is given; otherwise
            lists executions, narrowed by -Folder, -Project, -Package and/or -Status. Accepts a piped
            Ssis.Package to list that package's executions without reconnecting. Writes a warning and
            returns nothing when the catalog does not exist.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Returns the execution with id 42.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Running'

            Returns every currently running execution in the catalog.

        .EXAMPLE
            Get-SsisPackage -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Name 'Load.dtsx' | Get-SsisExecution

            Returns the executions of the piped package.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of a single execution to return. When given, the folder/project/package
            filters are ignored.

        .PARAMETER Folder
            The name of the folder to scope to. When omitted, executions across all folders are returned.

        .PARAMETER Project
            The name of the project to scope to. When omitted, executions across all projects are returned.

        .PARAMETER Package
            The name of the package to scope to. When omitted, executions across all packages are returned.

        .PARAMETER InputObject
            A piped Ssis.Package object whose executions to list, used instead of
            -SqlInstance/-Folder/-Project/-Package to keep the existing connection.

        .PARAMETER Status
            Returns only executions in the given status (for example Running, Succeeded, Failed).

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
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
        [long]
        $ExecutionId,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Folder,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Project,

        [Parameter(ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateSet('Created', 'Running', 'Cancelled', 'Failed', 'Pending', 'EndedUnexpectedly', 'Succeeded', 'Stopping', 'Completed')]
        [string]
        $Status
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $package = $InputObject
            $catalog = $package.Parent.Parent.Parent
            $folderFilter = $package.Parent.Parent.Name
            $projectFilter = $package.Parent.Name
            $packageFilter = $package.Name
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

            if ($PSBoundParameters.ContainsKey('ExecutionId'))
            {
                $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

                if ($null -eq $execution)
                {
                    Write-Warning -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                    return
                }

                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            $folderFilter = $Folder
            $projectFilter = $Project
            $packageFilter = $Package
        }

        $executions = Get-SsisExecutionObject -Catalog $catalog

        foreach ($execution in $executions)
        {
            if ($null -eq $execution)
            {
                continue
            }

            if ($folderFilter -and $execution.FolderName -ne $folderFilter)
            {
                continue
            }

            if ($projectFilter -and $execution.ProjectName -ne $projectFilter)
            {
                continue
            }

            if ($packageFilter -and $execution.PackageName -ne $packageFilter)
            {
                continue
            }

            if ($PSBoundParameters.ContainsKey('Status') -and $execution.Status.ToString() -ne $Status)
            {
                continue
            }

            $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
        }
    }
}
```

> **Note on `$execution.Status.ToString()`:** in the unit test the mock `Status` is already a
> string, and `'Running'.ToString()` is `'Running'`, so the comparison holds for both the live enum
> and the test double.

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisExecution.tests.ps1 -Output Detailed
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Get-SsisExecution.ps1 tests/Unit/Public/Get-SsisExecution.tests.ps1
git commit -m "feat: add Get-SsisExecution command"
```

---

## Task 7: `Wait-SsisExecution` (public — poll loop)

**Files:**
- Create: `source/Public/Wait-SsisExecution.ps1`
- Test: `tests/Unit/Public/Wait-SsisExecution.tests.ps1`

The loop tracks **logical** elapsed time (`$elapsed += $PollInterval` each iteration), so mocking
`Start-Sleep` drives the timeout path deterministically without real waiting.

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Wait-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Start-Sleep -ModuleName $script:moduleName -MockWith { }
    }

    It 'Polls until a terminal status, then returns the completed execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        $script:statuses = @('Running', 'Running', 'Succeeded')
        $script:callIndex = 0
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            $status = $script:statuses[$script:callIndex]
            $script:callIndex++
            [PSCustomObject]@{ Id = 7; Status = $status }
        }

        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 1
        $result.Status | Should -Be 'Succeeded'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        Should -Invoke -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -Times 3 -Scope It
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Times 2 -Scope It
    }

    It 'On timeout, writes a non-terminating error and returns the still-running execution' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }

        $errors = @()
        $result = Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 5 -Timeout 10 -ErrorVariable errors -ErrorAction SilentlyContinue
        $result.Status | Should -Be 'Running'
        $errors.Count | Should -BeGreaterThan 0
    }

    It 'Honours -ErrorAction Stop on timeout' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }

        { Wait-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PollInterval 5 -Timeout 5 -ErrorAction Stop } |
            Should -Throw
    }

    Context 'ByObject' {
        It 'Waits on a piped execution without reconnecting' {
            Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
                [PSCustomObject]@{ Id = 7; Status = 'Succeeded' }
            }

            $execution = [PSCustomObject]@{ Id = 7; Status = 'Running' }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $result = $execution | Wait-SsisExecution -PollInterval 1
            $result.Status | Should -Be 'Succeeded'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Wait-SsisExecution.tests.ps1 -Output Detailed
```
Expected: FAIL — `Wait-SsisExecution` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Wait-SsisExecution
{
    <#
        .SYNOPSIS
            Waits for an SSISDB execution to reach a terminal state.

        .DESCRIPTION
            Polls an execution, refreshing it every -PollInterval seconds, until its status becomes
            terminal (Succeeded, Failed, Cancelled, EndedUnexpectedly or Completed), then returns the
            completed Ssis.Execution. When -Timeout is greater than zero and the wait exceeds it, a
            non-terminating error is written and the still-running execution is returned, so callers
            can escalate with -ErrorAction Stop or inspect the returned Status. Accepts an execution by
            id (connecting to the instance) or a piped Ssis.Execution.

        .EXAMPLE
            Wait-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Waits for execution 42 to finish and returns the completed execution.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' | Wait-SsisExecution -Timeout 600

            Starts a package and waits up to ten minutes for it to finish.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution to wait for.

        .PARAMETER InputObject
            A piped Ssis.Execution object to wait for, used instead of -SqlInstance/-ExecutionId to
            keep the existing connection.

        .PARAMETER PollInterval
            Seconds to wait between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            Maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
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
        [long]
        $ExecutionId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [int]
        $Timeout = 0
    )

    process
    {
        $terminalStates = @('Succeeded', 'Failed', 'Cancelled', 'EndedUnexpectedly', 'Completed')

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $execution = $InputObject
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

            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

            if ($null -eq $execution)
            {
                Write-Warning -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                return
            }
        }

        $elapsed = 0

        while ($true)
        {
            $execution = Update-SsisExecutionObject -Execution $execution

            if ($terminalStates -contains $execution.Status.ToString())
            {
                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            if ($Timeout -gt 0 -and $elapsed -ge $Timeout)
            {
                Write-Error -Message ('Timed out after {0} seconds waiting for execution ''{1}''; current status is ''{2}''.' -f $Timeout, $execution.Id, $execution.Status)
                $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
                return
            }

            Start-Sleep -Seconds $PollInterval
            $elapsed += $PollInterval
        }
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Wait-SsisExecution.tests.ps1 -Output Detailed
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Wait-SsisExecution.ps1 tests/Unit/Public/Wait-SsisExecution.tests.ps1
git commit -m "feat: add Wait-SsisExecution command"
```

---

## Task 8: `Stop-SsisExecution` (public — cancel)

**Files:**
- Create: `source/Public/Stop-SsisExecution.ps1`
- Test: `tests/Unit/Public/Stop-SsisExecution.tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Stop-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Running' }
        }
        Mock -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Update-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 7; Status = 'Cancelled' }
        }
    }

    It 'Stops the execution and emits nothing by default' {
        $result = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -Confirm:$false
        $result | Should -BeNullOrEmpty
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Returns the refreshed execution with -PassThru' {
        $result = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -PassThru -Confirm:$false
        $result.Status | Should -Be 'Cancelled'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
    }

    It 'Supports -WhatIf and does not stop' {
        $null = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 7 -WhatIf
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not stop when the execution does not exist' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Stop-SsisExecution -SqlInstance 'TestInstance' -ExecutionId 999 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Stops a piped execution without reconnecting' {
            $execution = [PSCustomObject]@{ Id = 7; Status = 'Running' }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $null = $execution | Stop-SsisExecution -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Stop-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Stop-SsisExecution.tests.ps1 -Output Detailed
```
Expected: FAIL — `Stop-SsisExecution` is not recognized.

- [ ] **Step 3: Write the implementation**

```powershell
function Stop-SsisExecution
{
    <#
        .SYNOPSIS
            Stops a running SSISDB execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Execution) and requests
            cancellation of the execution. Silent by default; with -PassThru it refreshes and returns
            the Ssis.Execution (now Stopping or Cancelled). Writes a warning and makes no change when
            the catalog or execution does not exist. Because cancelling an in-flight run is
            irreversible, the command prompts by default (ConfirmImpact High); suppress with
            -Confirm:$false.

        .EXAMPLE
            Stop-SsisExecution -SqlInstance 'SQL01\PROD' -ExecutionId 42 -Confirm:$false

            Cancels execution 42 without prompting.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Running' | Stop-SsisExecution -PassThru -Confirm:$false | Wait-SsisExecution

            Cancels every running execution and waits for each to settle.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution to stop.

        .PARAMETER InputObject
            A piped Ssis.Execution object to stop, used instead of -SqlInstance/-ExecutionId to keep
            the existing connection.

        .PARAMETER PassThru
            Returns the refreshed Ssis.Execution after stopping. By default the command emits nothing.

        .OUTPUTS
            None, or Ssis.Execution when -PassThru is specified.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
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
        [long]
        $ExecutionId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [switch]
        $PassThru
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $execution = $InputObject
            $executionId = $InputObject.Id
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

            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $ExecutionId

            if ($null -eq $execution)
            {
                Write-Warning -Message ('Execution ''{0}'' was not found in the SSISDB catalog.' -f $ExecutionId)
                return
            }

            $executionId = $ExecutionId
        }

        if ($PSCmdlet.ShouldProcess($executionId, 'Stop SSIS execution'))
        {
            Stop-SsisExecutionObject -Execution $execution

            if ($PassThru)
            {
                $refreshed = Update-SsisExecutionObject -Execution $execution
                $refreshed | Add-SsisTypeName -TypeName 'Ssis.Execution'
            }
        }
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Stop-SsisExecution.tests.ps1 -Output Detailed
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Stop-SsisExecution.ps1 tests/Unit/Public/Stop-SsisExecution.tests.ps1
git commit -m "feat: add Stop-SsisExecution command"
```

---

## Task 9: `Start-SsisExecution` (public — start, the rich entry point)

**Files:**
- Create: `source/Public/Start-SsisExecution.ps1`
- Test: `tests/Unit/Public/Start-SsisExecution.tests.ps1`

Resolves the package, optionally resolves an environment reference by name (reusing
`Get-SsisEnvironmentReferenceObject`), gates `Execute()` behind `ShouldProcess`, fetches the new
execution by its returned id, and — with `-Synchronous` — delegates to `Wait-SsisExecution` via the
ByObject path.

- [ ] **Step 1: Write the failing test**

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisExecution' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Name = 'Sales' }
        }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' })
        }
        Mock -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -MockWith { [long] 55 }
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 55; Status = 'Running' }
        } -ParameterFilter { $ExecutionId -eq 55 }
        Mock -CommandName Wait-SsisExecution -ModuleName $script:moduleName -MockWith {
            $obj = [PSCustomObject]@{ Id = 55; Status = 'Succeeded' }
            $obj.PSObject.TypeNames.Insert(0, 'Ssis.Execution')
            $obj
        }
    }

    It 'Starts the package and returns the new Ssis.Execution' {
        $result = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false
        $result.Id | Should -Be 55
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Passes parameter overrides, logging level and the 32-bit flag through to the seam' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Parameter @{ TargetPort = 1450 } -LoggingLevel 'Verbose' -Use32BitRuntime -Confirm:$false
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Parameter.TargetPort -eq 1450 -and $LoggingLevel -eq 'Verbose' -and $Use32BitRuntime.IsPresent
        }
    }

    It 'Resolves the named environment reference and passes it to the seam' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Confirm:$false
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Reference.Name -eq 'Prod'
        }
    }

    It 'Warns and does not start when the named environment reference is absent' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Missing' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'With -Synchronous, delegates to Wait-SsisExecution and returns the completed execution' {
        $result = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Synchronous -Confirm:$false
        $result.Status | Should -Be 'Succeeded'
        Should -Invoke -CommandName Wait-SsisExecution -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not start' {
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -WhatIf
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not start when the package does not exist' {
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisExecution -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Missing.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Starts a piped package without reconnecting' {
            $package = [PSCustomObject]@{
                Name   = 'Load.dtsx'
                Parent = [PSCustomObject]@{ Name = 'Sales' }
            }
            $package.PSObject.TypeNames.Insert(0, 'Ssis.Package')

            $null = $package | Start-SsisExecution -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisExecutionObject -ModuleName $script:moduleName -Times 1 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Start-SsisExecution.tests.ps1 -Output Detailed
```
Expected: FAIL — `Start-SsisExecution` is not recognized.

- [ ] **Step 3: Write the implementation**

For the ByObject set, the package's owning project is `$InputObject.Parent`; the reference is
resolved from it. For the ByInstance set, the project comes from `Get-SsisProjectObject`. The
execution is re-fetched by id using the same catalog the package came from
(`$package.Parent.Parent.Parent` for ByObject; the connected `$catalog` for ByInstance).

```powershell
function Start-SsisExecution
{
    <#
        .SYNOPSIS
            Starts an SSISDB package execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Package) and starts the
            package, optionally binding an environment reference by name, applying parameter overrides,
            selecting the 32-bit runtime, and setting the logging level. Returns the started
            Ssis.Execution. With -Synchronous, waits for the run to finish (honouring -PollInterval and
            -Timeout) and returns the completed execution. Writes a warning and makes no change when the
            catalog, folder, project, package, or named environment reference does not exist.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false

            Starts the package and returns the running execution.

        .EXAMPLE
            Start-SsisExecution -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Parameter @{ TargetPort = 1450 } -LoggingLevel 'Basic' -Synchronous -Confirm:$false

            Starts the package bound to the Prod environment with a parameter override and Basic logging,
            then waits for it to finish.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to run.

        .PARAMETER Project
            The name of the project containing the package to run.

        .PARAMETER Package
            The name of the package to execute.

        .PARAMETER InputObject
            A piped Ssis.Package object to execute, used instead of -SqlInstance/-Folder/-Project/-Package
            to keep the existing connection.

        .PARAMETER EnvironmentName
            The name of an environment reference on the project to bind the execution to, so referenced
            parameters resolve.

        .PARAMETER EnvironmentFolder
            The folder of the environment when the reference is to an environment in a different folder
            than the project. When omitted, a reference named -EnvironmentName is matched regardless of
            folder.

        .PARAMETER Parameter
            A hashtable of parameter name/value overrides applied to this run only.

        .PARAMETER Use32BitRuntime
            Runs the package in the 32-bit runtime (for packages needing a 32-bit provider or driver).

        .PARAMETER LoggingLevel
            The logging level for this run: None, Basic, Performance or Verbose.

        .PARAMETER Synchronous
            Waits for the execution to reach a terminal state before returning the completed execution.

        .PARAMETER PollInterval
            With -Synchronous, seconds between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            With -Synchronous, maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Execution
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Execution')]
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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Package,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $EnvironmentName,

        [Parameter()]
        [string]
        $EnvironmentFolder,

        [Parameter()]
        [hashtable]
        $Parameter,

        [Parameter()]
        [switch]
        $Use32BitRuntime,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Performance', 'Verbose')]
        [string]
        $LoggingLevel,

        [Parameter()]
        [switch]
        $Synchronous,

        [Parameter()]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [int]
        $Timeout = 0
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $packageObject = $InputObject
            $projectObject = $InputObject.Parent
            $catalog = $null
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

            $packageObject = Get-SsisPackageObject -Project $projectObject -Name $Package

            if ($null -eq $packageObject)
            {
                Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                return
            }
        }

        $reference = $null

        if ($PSBoundParameters.ContainsKey('EnvironmentName'))
        {
            $references = Get-SsisEnvironmentReferenceObject -Project $projectObject

            # Capture the folder-filter flag here; $PSBoundParameters inside a Where-Object filter
            # script refers to Where-Object's own bound parameters, not this function's.
            $hasEnvironmentFolder = $PSBoundParameters.ContainsKey('EnvironmentFolder')

            $reference = $references |
                Where-Object -FilterScript {
                    $_.Name -eq $EnvironmentName -and
                    (-not $hasEnvironmentFolder -or $_.EnvironmentFolderName -eq $EnvironmentFolder)
                } |
                Select-Object -First 1

            if ($null -eq $reference)
            {
                Write-Warning -Message ('Environment reference ''{0}'' was not found on project ''{1}''.' -f $EnvironmentName, $projectObject.Name)
                return
            }
        }

        if (-not $PSCmdlet.ShouldProcess($packageObject.Name, 'Start SSIS execution'))
        {
            return
        }

        $splatStart = @{
            Package   = $packageObject
            Reference = $reference
        }

        if ($PSBoundParameters.ContainsKey('Parameter'))
        {
            $splatStart['Parameter'] = $Parameter
        }

        if ($PSBoundParameters.ContainsKey('LoggingLevel'))
        {
            $splatStart['LoggingLevel'] = $LoggingLevel
        }

        if ($Use32BitRuntime)
        {
            $splatStart['Use32BitRuntime'] = $true
        }

        $executionId = Start-SsisExecutionObject @splatStart

        if ($null -eq $catalog)
        {
            $catalog = $packageObject.Parent.Parent.Parent
        }

        $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId $executionId

        if ($Synchronous)
        {
            $execution | Add-SsisTypeName -TypeName 'Ssis.Execution' |
                Wait-SsisExecution -PollInterval $PollInterval -Timeout $Timeout
        }
        else
        {
            $execution | Add-SsisTypeName -TypeName 'Ssis.Execution'
        }
    }
}
```

- [ ] **Step 4: Build, then run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Start-SsisExecution.tests.ps1 -Output Detailed
```
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Start-SsisExecution.ps1 tests/Unit/Public/Start-SsisExecution.tests.ps1
git commit -m "feat: add Start-SsisExecution command"
```

---

## Task 10: Integration test (real SSISDB, opt-in)

**Files:**
- Create: `tests/Integration/Ssis.Execution.Integration.tests.ps1`

Mirrors the existing `Ssis.Reference.Integration.tests.ps1`: deploys the fixture `.ispac`, runs the
lifecycle against a real instance, and self-skips when `$env:SSIS_TEST_INSTANCE` is unset or the
fixture is absent.

- [ ] **Step 1: Write the integration test**

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
    $script:folderName = 'ISTools_ExecTest'
    $script:projectName = 'ISTools_TestProject'
    $script:packageName = 'Package.dtsx'

    $script:removeFolderIfPresent = {
        param ($instance, $folderName)

        if (Get-SsisFolder -SqlInstance $instance -Name $folderName -WarningAction SilentlyContinue)
        {
            Get-SsisProject -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisProject -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

            Get-SsisEnvironment -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisEnvironment -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

            Remove-SsisFolder -SqlInstance $instance -Name $folderName -Confirm:$false
        }
    }

    & $script:removeFolderIfPresent $script:instance $script:folderName

    New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Description 'Created by integration test' -Confirm:$false | Out-Null
    Publish-SsisProject -SqlInstance $script:instance -Folder $script:folderName -Path $script:fixturePath -Confirm:$false | Out-Null
}

AfterAll {
    & $script:removeFolderIfPresent $script:instance $script:folderName

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Execution lifecycle (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Starts a package synchronously and reports a terminal status' {
        $execution = Start-SsisExecution -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Package $script:packageName -LoggingLevel 'Basic' -Synchronous -Timeout 300 -Confirm:$false
        $execution.PSObject.TypeNames | Should -Contain 'Ssis.Execution'
        $execution.Status.ToString() | Should -BeIn @('Succeeded', 'Failed', 'Completed')
    }

    It 'Finds the execution by id and by status' {
        $started = Start-SsisExecution -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Package $script:packageName -Synchronous -Timeout 300 -Confirm:$false

        $byId = Get-SsisExecution -SqlInstance $script:instance -ExecutionId $started.Id
        $byId.Id | Should -Be $started.Id

        $byPackage = Get-SsisExecution -SqlInstance $script:instance -Folder $script:folderName -Project $script:projectName -Package $script:packageName
        ($byPackage | Measure-Object).Count | Should -BeGreaterThan 0
    }
}
```

> **Executor note:** confirm the fixture's real package name (open the `.ispac` or run
> `Get-SsisPackage` after publishing). If it is not `Package.dtsx`, update `$script:packageName`.
> The synchronous start may end as `Failed` if the test package needs configuration it lacks — the
> assertion accepts any terminal status, since the goal is exercising the lifecycle, not the
> package's own success.

- [ ] **Step 2: Run the integration test locally (skips cleanly without an instance)**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Integration/Ssis.Execution.Integration.tests.ps1 -Output Detailed
```
Expected: the `Describe` block is **Skipped** when `$env:SSIS_TEST_INSTANCE` is unset (no failures).

- [ ] **Step 3: Commit**

```powershell
git add tests/Integration/Ssis.Execution.Integration.tests.ps1
git commit -m "test: add execution lifecycle integration tests"
```

---

## Task 11: Full build + QA verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full build and test task**

```powershell
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```
Expected: QA tests pass (help present on all eight new functions, PSScriptAnalyzer clean, manifest
correct); unit tests pass; integration tests skip cleanly without `$env:SSIS_TEST_INSTANCE`. A
unit-only coverage shortfall is expected by design (interop wrappers are covered only by
integration), consistent with prior phases — confirm the failure, if any, is solely the coverage
threshold and not a test failure.

- [ ] **Step 2: Confirm the eight new commands are exported and formatted**

```powershell
Import-Module ./output/module/IntegrationServicesTools -Force
Get-Command -Module IntegrationServicesTools -Name '*SsisExecution*' | Select-Object -ExpandProperty Name
```
Expected: lists `Get-SsisExecution`, `Start-SsisExecution`, `Stop-SsisExecution`,
`Wait-SsisExecution` (the four public commands; the `*Object` wrappers stay private).

- [ ] **Step 3: Final commit if anything was adjusted during verification**

```powershell
git add -A
git commit -m "chore: finalize Phase 4a execution lifecycle"
```

---

## Self-review notes (resolved during planning)

- **Spec coverage:** Start (env ref / params / 32-bit / logging / synchronous) → Tasks 5 + 9; Stop
  (High + PassThru) → Tasks 4 + 8; Get (id / filters / status / pipe) → Tasks 2 + 6; Wait
  (poll / timeout-returns-with-Write-Error) → Tasks 3 + 7; `Ssis.Execution` type + view → Task 1;
  interop seam → Tasks 2–5; integration → Task 10; QA/coverage → Task 11. No gaps.
- **Type consistency:** wrapper names (`Get`/`Update`/`Stop`/`Start-SsisExecutionObject`), the
  `Ssis.Execution` PSTypeName, and the shared status/terminal vocabularies are used identically
  across tasks.
- **Decision captured:** the wait loop uses logical elapsed time (`$elapsed += $PollInterval`) so
  the timeout path is unit-testable with `Start-Sleep` mocked.
```