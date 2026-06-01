# SSIS Validation Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Start-SsisValidation` (validate a deployed SSISDB project or package) plus a general `Wait-SsisOperation`, reusing the existing `Ssis.Operation` output type.

**Architecture:** Two public commands (`Start-SsisValidation`, `Wait-SsisOperation`) over two new private interop seams (`Start-SsisValidationObject` wrapping `ProjectInfo`/`PackageInfo`.`Validate()`, and `Update-SsisOperationObject` wrapping `Operation.Refresh()`). Validation returns a `ValidationOperation` (a subclass of `Operation`), so it decorates as `Ssis.Operation` and reuses the existing format view, `Get-SsisOperationObject`, the folder→project→package resolution helpers, and `Get-SsisEnvironmentReferenceObject`. `Start-SsisValidation -Synchronous` delegates to `Wait-SsisOperation`, mirroring the `Start`/`Wait-SsisExecution` split.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder, Pester v5, PSScriptAnalyzer, `Microsoft.SqlServer.Management.IntegrationServices` MOM.

**Spec:** `docs/superpowers/specs/2026-06-01-ssis-validation-design.md`

**MOM facts (pinned by reflection, do not re-assume):**
- `ProjectInfo.Validate(bool use32RuntimeOn64, ProjectInfo.ReferenceUsage referenceUsage, EnvironmentReference reference) → Int64` — identical signature on `PackageInfo`.
- Enum `Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo+ReferenceUsage` = `UseAllReferences`, `UseNoReference`, `SpecifyReference`.
- `ValidationOperation : Operation`; `Operation.Refresh()` exists; `Operation.Status` is `Operation+ServerOperationStatus` with terminal members `Success`, `Failed`, `Canceled`, `UnexpectTerminated`, `Completion`.

**Conventions (every task):** Allman braces; single quotes unless interpolating; `[Parameter(Mandatory = $true)]`; 4-space indent, no trailing whitespace; no backticks (splat for 3+ params, aligned `=`); `::new()` allowed; one blank line between param declarations; full comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE`/`.OUTPUTS`) on public AND private functions; Conventional Commits.

---

## File Structure

- Create `source/Private/Update-SsisOperationObject.ps1` — refresh seam (Refresh()).
- Create `source/Public/Wait-SsisOperation.ps1` — general operation waiter.
- Create `source/Private/Start-SsisValidationObject.ps1` — Validate() seam.
- Create `source/Public/Start-SsisValidation.ps1` — public validation command.
- Create `tests/Unit/Private/Update-SsisOperationObject.tests.ps1`
- Create `tests/Unit/Public/Wait-SsisOperation.tests.ps1`
- Create `tests/Unit/Private/Start-SsisValidationObject.tests.ps1`
- Create `tests/Unit/Public/Start-SsisValidation.tests.ps1`
- Create `tests/Integration/Ssis.Validation.Integration.tests.ps1`
- Modify `CHANGELOG.md` (Unreleased → Added)
- Regenerated: `README.md` (via the `Generate_Readme` build task)

No format.ps1xml change — `Ssis.Operation` view already exists.

## How to run tests

Single-file unit run (needs both module and required-modules paths because importing pulls in `dbatools.library`):

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Unit/Public/Wait-SsisOperation.tests.ps1 -Output Detailed
```

A code change is only picked up after a `build` (ModuleBuilder merges `source/` into `output/module/.../*.psm1`). So the cycle is: write test → `./build.ps1 -Tasks build` → run the test file. Full gate: `./build.ps1 -Tasks build,test` (set `$env:SSIS_TEST_INSTANCE='localhost'` to run Integration, otherwise it self-skips).

---

### Task 1: `Update-SsisOperationObject` (refresh seam)

**Files:**
- Create: `source/Private/Update-SsisOperationObject.ps1`
- Test: `tests/Unit/Private/Update-SsisOperationObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Private/Update-SsisOperationObject.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Update-SsisOperationObject' {
    It 'Calls Refresh on the operation and returns it' {
        InModuleScope $script:moduleName {
            $operation = [PSCustomObject]@{ RefreshCalled = $false }
            $operation | Add-Member -MemberType 'ScriptMethod' -Name 'Refresh' -Value { $this.RefreshCalled = $true }

            $result = Update-SsisOperationObject -Operation $operation

            $operation.RefreshCalled | Should -BeTrue
            $result | Should -Be $operation
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Unit/Private/Update-SsisOperationObject.tests.ps1 -Output Detailed
```

Expected: FAIL — `Update-SsisOperationObject` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Private/Update-SsisOperationObject.ps1`:

```powershell
function Update-SsisOperationObject
{
    <#
        .SYNOPSIS
            Refreshes an SSISDB operation from the server and returns it.

        .DESCRIPTION
            Calls Refresh() on the Operation so its Status and timing properties reflect the current
            server state, then returns the same object. Used as the poll primitive by
            Wait-SsisOperation. Internal interop helper, not exported from the module.

        .EXAMPLE
            $operation = Update-SsisOperationObject -Operation $operation

            Refreshes the operation and returns it with up-to-date Status.

        .PARAMETER Operation
            The Operation object to refresh, as returned by Get-SsisOperationObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.Operation
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The Update verb triggers this rule, but Refresh() only re-reads server state and changes nothing, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Operation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Operation
    )

    process
    {
        $Operation.Refresh()
        return $Operation
    }
}
```

- [ ] **Step 4: Build, then run the test to verify it passes**

```powershell
./build.ps1 -Tasks build
Invoke-Pester -Path tests/Unit/Private/Update-SsisOperationObject.tests.ps1 -Output Detailed
```

Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Update-SsisOperationObject.ps1 tests/Unit/Private/Update-SsisOperationObject.tests.ps1
git commit -m "feat: add Update-SsisOperationObject refresh seam"
```

---

### Task 2: `Wait-SsisOperation` (general operation waiter)

**Files:**
- Create: `source/Public/Wait-SsisOperation.ps1`
- Test: `tests/Unit/Public/Wait-SsisOperation.tests.ps1`

Depends on Task 1 (`Update-SsisOperationObject`) and the existing `Get-SsisOperationObject`, `Connect-SsisCatalog`, `Get-SsisCatalogObject`, `Add-SsisTypeName`.

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Public/Wait-SsisOperation.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Wait-SsisOperation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Start-Sleep -ModuleName $script:moduleName -MockWith { }
    }

    It 'Polls until a terminal status, then returns the completed operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        $script:statuses = @('Running', 'Running', 'Success')
        $script:callIndex = 0
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            $status = $script:statuses[$script:callIndex]
            $script:callIndex++
            [PSCustomObject]@{ Id = 9; Status = $status }
        }

        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 1
        $result.Status | Should -Be 'Success'
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        Should -Invoke -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -Times 3 -Scope It
        Should -Invoke -CommandName Start-Sleep -ModuleName $script:moduleName -Times 2 -Scope It
    }

    It 'On timeout, writes a non-terminating error and returns the still-running operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }

        $errors = @()
        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 5 -Timeout 10 -ErrorVariable errors -ErrorAction SilentlyContinue
        $result.Status | Should -Be 'Running'
        $errors.Count | Should -BeGreaterThan 0
    }

    It 'Honours -ErrorAction Stop on timeout' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }
        Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; Status = 'Running' }
        }

        { Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 5 -Timeout 5 -ErrorAction Stop } |
            Should -Throw
    }

    It 'Warns and returns nothing when the operation is absent' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 404 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Rejects a PollInterval below 1' {
        { Wait-SsisOperation -SqlInstance 'TestInstance' -OperationId 9 -PollInterval 0 } |
            Should -Throw
    }

    Context 'ByObject' {
        It 'Waits on a piped operation without reconnecting' {
            Mock -CommandName Update-SsisOperationObject -ModuleName $script:moduleName -MockWith {
                [PSCustomObject]@{ Id = 9; Status = 'Success' }
            }

            $operation = [PSCustomObject]@{ Id = 9; Status = 'Running' }
            $operation.PSObject.TypeNames.Insert(0, 'Ssis.Operation')

            $result = $operation | Wait-SsisOperation -PollInterval 1
            $result.Status | Should -Be 'Success'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Unit/Public/Wait-SsisOperation.tests.ps1 -Output Detailed
```

Expected: FAIL — `Wait-SsisOperation` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Public/Wait-SsisOperation.ps1`:

```powershell
function Wait-SsisOperation
{
    <#
        .SYNOPSIS
            Waits for an SSISDB operation to reach a terminal state.

        .DESCRIPTION
            Polls an operation, refreshing it every -PollInterval seconds, until its status becomes
            terminal (Success, Failed, Canceled, UnexpectTerminated or Completion), then returns the
            completed Ssis.Operation. When -Timeout is greater than zero and the wait exceeds it, a
            non-terminating error is written and the still-running operation is returned, so callers
            can escalate with -ErrorAction Stop or inspect the returned Status. Accepts an operation by
            id (connecting to the instance) or a piped Ssis.Operation. It is general: any operation
            (validation, execution or deployment) can be waited on.

        .EXAMPLE
            Wait-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 42

            Waits for operation 42 to finish and returns the completed operation.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Confirm:$false | Wait-SsisOperation -Timeout 120

            Starts a project validation and waits up to two minutes for it to finish.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER OperationId
            The numeric id of the operation to wait for.

        .PARAMETER InputObject
            A piped Ssis.Operation object to wait for, used instead of -SqlInstance/-OperationId to
            keep the existing connection.

        .PARAMETER PollInterval
            Seconds to wait between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            Maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Operation
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Operation')]
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
        $OperationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $Timeout = 0
    )

    process
    {
        $terminalStates = @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $operation = $InputObject
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

            $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $OperationId

            if ($null -eq $operation)
            {
                Write-Warning -Message ('Operation ''{0}'' was not found in the SSISDB catalog.' -f $OperationId)
                return
            }
        }

        $elapsed = 0

        while ($true)
        {
            $operation = Update-SsisOperationObject -Operation $operation

            if ($terminalStates -contains $operation.Status.ToString())
            {
                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }

            if ($Timeout -gt 0 -and $elapsed -ge $Timeout)
            {
                Write-Error -Message ('Timed out after about {0} seconds (limit {1}) waiting for operation ''{2}''; current status is ''{3}''.' -f $elapsed, $Timeout, $operation.Id, $operation.Status)
                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }

            Start-Sleep -Seconds $PollInterval
            $elapsed += $PollInterval
        }
    }
}
```

- [ ] **Step 4: Build, then run the test to verify it passes**

```powershell
./build.ps1 -Tasks build
Invoke-Pester -Path tests/Unit/Public/Wait-SsisOperation.tests.ps1 -Output Detailed
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Wait-SsisOperation.ps1 tests/Unit/Public/Wait-SsisOperation.tests.ps1
git commit -m "feat: add Wait-SsisOperation command"
```

---

### Task 3: `Start-SsisValidationObject` (Validate seam)

**Files:**
- Create: `source/Private/Start-SsisValidationObject.ps1`
- Test: `tests/Unit/Private/Start-SsisValidationObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Private/Start-SsisValidationObject.tests.ps1`. Note the fake `Validate` **returns a `[long]`** (mirrors the real return type — a fake that returns nothing would hide an output leak, the Phase 2 lesson):

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisValidationObject' {
    It 'Calls Validate with the 32-bit flag, SpecifyReference and the reference, and returns the id' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Use32 = $null; Usage = $null; Ref = $null }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Use32 = $use32
                $this.Usage = $usage
                $this.Ref = $reference
                return [long] 77
            }

            $result = Start-SsisValidationObject -Target $target -Reference 'theRef' -ReferenceUsage 'SpecifyReference' -Use32BitRuntime

            $result | Should -Be 77
            $target.Use32 | Should -BeTrue
            $target.Usage.ToString() | Should -Be 'SpecifyReference'
            $target.Ref | Should -Be 'theRef'
        }
    }

    It 'Passes UseNoReference and a null reference through' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Usage = $null; Ref = 'preset' }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Usage = $usage
                $this.Ref = $reference
                return [long] 1
            }

            $null = Start-SsisValidationObject -Target $target -Reference $null -ReferenceUsage 'UseNoReference'

            $target.Usage.ToString() | Should -Be 'UseNoReference'
            $target.Ref | Should -Be $null
        }
    }

    It 'Defaults the 32-bit flag to off (use32RuntimeOn64 = false) when not supplied' {
        InModuleScope $script:moduleName {
            $target = [PSCustomObject]@{ Use32 = $null }
            $target | Add-Member -MemberType 'ScriptMethod' -Name 'Validate' -Value {
                param ($use32, $usage, $reference)
                $this.Use32 = $use32
                return [long] 1
            }

            $null = Start-SsisValidationObject -Target $target -Reference $null -ReferenceUsage 'UseAllReferences'

            $target.Use32 | Should -BeFalse
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Unit/Private/Start-SsisValidationObject.tests.ps1 -Output Detailed
```

Expected: FAIL — `Start-SsisValidationObject` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Private/Start-SsisValidationObject.ps1`:

```powershell
function Start-SsisValidationObject
{
    <#
        .SYNOPSIS
            Validates an SSISDB project or package and returns the validation operation id.

        .DESCRIPTION
            Calls Validate() on the supplied ProjectInfo or PackageInfo with the 32-bit runtime flag
            (passed as use32RuntimeOn64), the requested ReferenceUsage, and the optional environment
            reference, then returns the numeric validation operation id. Internal interop helper, not
            exported from the module.

        .EXAMPLE
            $id = Start-SsisValidationObject -Target $project -Reference $null -ReferenceUsage 'UseAllReferences'

            Validates the project against all its environment references and returns the operation id.

        .PARAMETER Target
            The SSISDB ProjectInfo or PackageInfo object to validate, as returned by
            Get-SsisProjectObject or Get-SsisPackageObject.

        .PARAMETER Reference
            The EnvironmentReference to validate against when -ReferenceUsage is SpecifyReference, or
            $null otherwise.

        .PARAMETER ReferenceUsage
            How environment references are applied: UseAllReferences, UseNoReference or SpecifyReference.

        .PARAMETER Use32BitRuntime
            When set, validates in the 32-bit runtime (passed as use32RuntimeOn64).

        .OUTPUTS
            System.Int64
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Start-SsisValidation) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([long])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Target,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Reference,

        [Parameter(Mandatory = $true)]
        [ValidateSet('UseAllReferences', 'UseNoReference', 'SpecifyReference')]
        [string]
        $ReferenceUsage,

        [Parameter()]
        [switch]
        $Use32BitRuntime
    )

    process
    {
        $referenceUsageValue = [Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo+ReferenceUsage]$ReferenceUsage

        return $Target.Validate($Use32BitRuntime.IsPresent, $referenceUsageValue, $Reference)
    }
}
```

- [ ] **Step 4: Build, then run the test to verify it passes**

```powershell
./build.ps1 -Tasks build
Invoke-Pester -Path tests/Unit/Private/Start-SsisValidationObject.tests.ps1 -Output Detailed
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Start-SsisValidationObject.ps1 tests/Unit/Private/Start-SsisValidationObject.tests.ps1
git commit -m "feat: add Start-SsisValidationObject validate seam"
```

---

### Task 4: `Start-SsisValidation` (public command)

**Files:**
- Create: `source/Public/Start-SsisValidation.ps1`
- Test: `tests/Unit/Public/Start-SsisValidation.tests.ps1`

Depends on Tasks 2 and 3 plus existing `Connect-SsisCatalog`, `Get-SsisCatalogObject`, `Get-SsisFolderObject`, `Get-SsisProjectObject`, `Get-SsisPackageObject`, `Get-SsisEnvironmentReferenceObject`, `Get-SsisOperationObject`, `Add-SsisTypeName`.

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Public/Start-SsisValidation.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Start-SsisValidation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisProjectObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Sales' } }
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Load.dtsx' } }
        Mock -CommandName Get-SsisEnvironmentReferenceObject -ModuleName $script:moduleName -MockWith {
            @([PSCustomObject]@{ Name = 'Prod'; EnvironmentFolderName = 'Finance' })
        }
        Mock -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -MockWith { [long] 88 }
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 88; Status = 'Running' }
        } -ParameterFilter { $OperationId -eq 88 }
        Mock -CommandName Wait-SsisOperation -ModuleName $script:moduleName -MockWith {
            $obj = [PSCustomObject]@{ Id = 88; Status = 'Success' }
            $obj.PSObject.TypeNames.Insert(0, 'Ssis.Operation')
            $obj
        }
    }

    It 'Validates the project (no -Package) and returns the new Ssis.Operation' {
        $result = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Confirm:$false
        $result.Id | Should -Be 88
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Target.Name -eq 'Sales' -and $ReferenceUsage -eq 'UseAllReferences'
        }
    }

    It 'Validates a single package when -Package is supplied' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Target.Name -eq 'Load.dtsx'
        }
    }

    It 'Uses UseNoReference when -NoReference is given' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -NoReference -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ReferenceUsage -eq 'UseNoReference'
        }
    }

    It 'Resolves a named reference and uses SpecifyReference' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Prod' -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $ReferenceUsage -eq 'SpecifyReference' -and $Reference.Name -eq 'Prod'
        }
    }

    It 'Throws when both -EnvironmentName and -NoReference are given' {
        { Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Prod' -NoReference -Confirm:$false } |
            Should -Throw
    }

    It 'Warns and does not validate when the named reference is absent' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -EnvironmentName 'Missing' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Passes the 32-bit flag through to the seam' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Use32BitRuntime -Confirm:$false
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Use32BitRuntime.IsPresent
        }
    }

    It 'With -Synchronous, delegates to Wait-SsisOperation and returns the completed operation' {
        $result = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Synchronous -Confirm:$false
        $result.Status | Should -Be 'Success'
        Should -Invoke -CommandName Wait-SsisOperation -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Supports -WhatIf and does not validate' {
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -WhatIf
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Warns and does not validate when the package does not exist' {
        Mock -CommandName Get-SsisPackageObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Start-SsisValidation -SqlInstance 'TestInstance' -Folder 'Finance' -Project 'Sales' -Package 'Missing.dtsx' -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Validates a piped project without reconnecting (target is the project)' {
            $project = [PSCustomObject]@{
                Name   = 'Sales'
                Parent = [PSCustomObject]@{
                    Name   = 'Finance'
                    Parent = [PSCustomObject]@{ Name = 'SSISDB' }
                }
            }
            $project.PSObject.TypeNames.Insert(0, 'Ssis.Project')

            $null = $project | Start-SsisValidation -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Target.Name -eq 'Sales'
            }
        }

        It 'Validates a piped package without reconnecting (target is the package)' {
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

            $null = $package | Start-SsisValidation -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Start-SsisValidationObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Target.Name -eq 'Load.dtsx'
            }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Unit/Public/Start-SsisValidation.tests.ps1 -Output Detailed
```

Expected: FAIL — `Start-SsisValidation` is not recognized.

- [ ] **Step 3: Write the implementation**

Create `source/Public/Start-SsisValidation.ps1`:

```powershell
function Start-SsisValidation
{
    <#
        .SYNOPSIS
            Validates an SSISDB project or package.

        .DESCRIPTION
            Connects to the specified SQL Server instance (or uses a piped Ssis.Project or Ssis.Package)
            and validates the target, returning the validation Ssis.Operation. Omit -Package to validate
            the whole project; supply it to validate one package. Environment references are applied by
            inference: -EnvironmentName validates against that single reference (SpecifyReference),
            -NoReference validates ignoring references (UseNoReference), and supplying neither validates
            against all references (UseAllReferences). With -Synchronous, waits for the validation to
            finish (honouring -PollInterval and -Timeout) via Wait-SsisOperation and returns the
            completed operation. Writes a warning and makes no change when the catalog, folder, project,
            package, or named environment reference does not exist.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Confirm:$false

            Validates the whole Sales project against all its environment references.

        .EXAMPLE
            Start-SsisValidation -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Project 'Sales' -Package 'Load.dtsx' -EnvironmentName 'Prod' -Synchronous -Confirm:$false

            Validates one package against the Prod environment reference and waits for the result.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the project to validate.

        .PARAMETER Project
            The name of the project to validate (or whose package is validated).

        .PARAMETER Package
            The name of a single package to validate. When omitted, the whole project is validated.

        .PARAMETER InputObject
            A piped Ssis.Project or Ssis.Package object to validate, used instead of
            -SqlInstance/-Folder/-Project/-Package to keep the existing connection.

        .PARAMETER EnvironmentName
            The name of an environment reference on the project to validate against (SpecifyReference).
            Mutually exclusive with -NoReference.

        .PARAMETER EnvironmentFolder
            The folder of the environment when the reference is to an environment in a different folder
            than the project. When omitted, a reference named -EnvironmentName is matched regardless of
            folder.

        .PARAMETER NoReference
            Validates ignoring all environment references (UseNoReference). Mutually exclusive with
            -EnvironmentName.

        .PARAMETER Use32BitRuntime
            Validates in the 32-bit runtime (for packages needing a 32-bit provider or driver).

        .PARAMETER Synchronous
            Waits for the validation operation to reach a terminal state before returning it.

        .PARAMETER PollInterval
            With -Synchronous, seconds between status refreshes. Defaults to 5.

        .PARAMETER Timeout
            With -Synchronous, maximum seconds to wait. 0 (the default) waits indefinitely.

        .OUTPUTS
            Ssis.Operation
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Operation')]
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
        $EnvironmentName,

        [Parameter()]
        [string]
        $EnvironmentFolder,

        [Parameter()]
        [switch]
        $NoReference,

        [Parameter()]
        [switch]
        $Use32BitRuntime,

        [Parameter()]
        [switch]
        $Synchronous,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $PollInterval = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $Timeout = 0
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('EnvironmentName') -and $NoReference)
        {
            throw 'Specify either -EnvironmentName or -NoReference, not both.'
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $target = $InputObject

            if ($InputObject.PSObject.TypeNames -contains 'Ssis.Package')
            {
                $projectObject = $InputObject.Parent
            }
            else
            {
                $projectObject = $InputObject
            }

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

            if ($PSBoundParameters.ContainsKey('Package'))
            {
                $packageObject = Get-SsisPackageObject -Project $projectObject -Name $Package

                if ($null -eq $packageObject)
                {
                    Write-Warning -Message ('Package ''{0}'' was not found in project ''{1}''.' -f $Package, $Project)
                    return
                }

                $target = $packageObject
            }
            else
            {
                $target = $projectObject
            }
        }

        $reference = $null
        $referenceUsage = 'UseAllReferences'

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

            $referenceUsage = 'SpecifyReference'
        }
        elseif ($NoReference)
        {
            $referenceUsage = 'UseNoReference'
        }

        if (-not $PSCmdlet.ShouldProcess($target.Name, 'Start SSIS validation'))
        {
            return
        }

        $splatValidate = @{
            Target         = $target
            Reference      = $reference
            ReferenceUsage = $referenceUsage
        }

        if ($Use32BitRuntime)
        {
            $splatValidate['Use32BitRuntime'] = $true
        }

        $operationId = Start-SsisValidationObject @splatValidate

        if ($null -eq $catalog)
        {
            $catalog = $projectObject.Parent.Parent
        }

        $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $operationId

        if ($Synchronous)
        {
            $operation | Wait-SsisOperation -PollInterval $PollInterval -Timeout $Timeout
        }
        else
        {
            $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
        }
    }
}
```

- [ ] **Step 4: Build, then run the test to verify it passes**

```powershell
./build.ps1 -Tasks build
Invoke-Pester -Path tests/Unit/Public/Start-SsisValidation.tests.ps1 -Output Detailed
```

Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Start-SsisValidation.ps1 tests/Unit/Public/Start-SsisValidation.tests.ps1
git commit -m "feat: add Start-SsisValidation command"
```

---

### Task 5: Integration test

**Files:**
- Create: `tests/Integration/Ssis.Validation.Integration.tests.ps1`

This test self-skips when `$env:SSIS_TEST_INSTANCE` is unset or the fixture `.ispac` is absent. It mirrors the structure of `tests/Integration/Ssis.Execution.Integration.tests.ps1` (publish into its own folder; drain + drop in setup and teardown because SSISDB only drops empty folders).

- [ ] **Step 1: Write the integration test**

Create `tests/Integration/Ssis.Validation.Integration.tests.ps1`:

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
    $script:folderName = 'ISTools_ValidationTest'
    $script:projectName = 'ISTools_TestProject'
    # Package name confirmed from New-TestProjectIspac.ps1: PackageItems.Add($package, 'Package.dtsx')
    $script:packageName = 'Package.dtsx'

    $script:removeFolderIfPresent = {
        param ($instance, $folderName)

        if (Get-SsisFolder -SqlInstance $instance -Name $folderName -WarningAction SilentlyContinue)
        {
            Get-SsisProject -SqlInstance $instance -Folder $folderName -WarningAction SilentlyContinue |
                ForEach-Object -Process { Remove-SsisProject -SqlInstance $instance -Folder $folderName -Name $_.Name -Confirm:$false }

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

Describe 'Validation (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Validates a project synchronously and reports a terminal status' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Synchronous = $true
            Timeout     = 120
            Confirm     = $false
        }
        $operation = Start-SsisValidation @splatValidate
        $operation.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
        $operation.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }

    It 'Validates a single package synchronously' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Package     = $script:packageName
            Synchronous = $true
            Timeout     = 120
            Confirm     = $false
        }
        $operation = Start-SsisValidation @splatValidate
        $operation.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }

    It 'Waits on a started validation operation via Wait-SsisOperation' {
        $splatValidate = @{
            SqlInstance = $script:instance
            Folder      = $script:folderName
            Project     = $script:projectName
            Confirm     = $false
        }
        $started = Start-SsisValidation @splatValidate
        $completed = $started | Wait-SsisOperation -Timeout 120
        $completed.Id | Should -Be $started.Id
        $completed.Status.ToString() | Should -BeIn @('Success', 'Failed', 'Canceled', 'UnexpectTerminated', 'Completion')
    }
}
```

- [ ] **Step 2: Run it both ways**

Without an instance (must self-skip cleanly):

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path tests/Integration/Ssis.Validation.Integration.tests.ps1 -Output Detailed
```

Expected: all tests SKIPPED (no failures).

With a live instance (tests RUN — required before PR):

```powershell
$env:SSIS_TEST_INSTANCE = 'localhost'
Invoke-Pester -Path tests/Integration/Ssis.Validation.Integration.tests.ps1 -Output Detailed
```

Expected: 3 tests PASS, terminal status `Success`.

- [ ] **Step 3: Commit**

```powershell
git add tests/Integration/Ssis.Validation.Integration.tests.ps1
git commit -m "test: add SSIS validation integration test"
```

---

### Task 6: Changelog, README regeneration, and full verification

**Files:**
- Modify: `CHANGELOG.md`
- Regenerated: `README.md`

- [ ] **Step 1: Add the changelog entries**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add these two lines at the **top** of the list (newest first, matching the existing ordering):

```markdown
- Wait-SsisOperation command.
- Start-SsisValidation command.
```

- [ ] **Step 2: Regenerate the README**

The `Generate_Readme` build task rewrites the command index from `source/Public` synopses; the `Assert_Readme_Clean` gate then fails if `README.md` is out of date. Run the build so the two new public commands appear:

```powershell
./build.ps1 -Tasks build
```

Expected: build succeeds; `README.md` now lists `Start-SsisValidation` and `Wait-SsisOperation`. Confirm with `git status` that `README.md` changed.

- [ ] **Step 3: Run the full suite WITH a live instance (required before PR)**

Per the project rule, the comprehensive suite must RUN (not skip) integration and be green before a PR:

```powershell
$env:SSIS_TEST_INSTANCE = 'localhost'
./build.ps1 -Tasks build,test
```

Expected: 0 failures, 0 build errors, coverage ≥ 85%. All four new functions export; help quality / PSScriptAnalyzer / manifest / README-drift QA tests pass. Note the test count and coverage from the output.

- [ ] **Step 4: Commit**

```powershell
git add CHANGELOG.md README.md
git commit -m "docs: changelog and README for SSIS validation commands"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- §4.1 `Start-SsisValidation` → Task 4 (param sets, project/package target, reference-usage inference, mutually-exclusive throw, guards, ShouldProcess, `-Synchronous` delegation, decoration).
- §4.2 `Wait-SsisOperation` → Task 2 (ByInstance/ByObject, terminal detection, timeout `Write-Error` + return, absent-operation warn).
- §4.3 `Start-SsisValidationObject` → Task 3 (enum cast, `use32RuntimeOn64`, returns id; fake returns the real type).
- §4.4 `Update-SsisOperationObject` → Task 1 (Refresh + return, PSSA suppression).
- §5 reference-usage resolution → Task 4 impl + the three usage tests + the throw test.
- §6 output `Ssis.Operation` reuse → no format change; decoration asserted in Tasks 2 & 4.
- §8 testing (unit + integration) → Tasks 1–5; QA/help/README-drift → Task 6.
- §10 out-of-scope items have no tasks (correct — not built).

**Placeholder scan:** none — every code and command step is concrete.

**Type/name consistency:** `Start-SsisValidationObject` parameters `-Target`/`-Reference`/`-ReferenceUsage`/`-Use32BitRuntime` are identical in its definition (Task 3), its tests (Task 3), and its caller's splat (Task 4). `-OperationId`/`-InputObject` consistent across `Wait-SsisOperation` definition and tests (Task 2). `ReferenceUsage` values `UseAllReferences`/`UseNoReference`/`SpecifyReference` match the reflected enum and the `ValidateSet`. Terminal-state list identical in `Wait-SsisOperation` and both integration assertions.
