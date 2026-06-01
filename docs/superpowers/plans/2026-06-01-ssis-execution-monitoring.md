# Phase 4b: Execution Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two read-only monitoring commands to the module — `Get-SsisExecutionMessage` (an execution's message log) and `Get-SsisOperation` (the catalog's operations) — closing out Phase 4.

**Architecture:** Each command follows the established ByInstance/ByObject parameter-set pattern, resolves the catalog via `Connect-SsisCatalog`/`Get-SsisCatalogObject`, reads the MOM through a thin private `*-Ssis*Object` wrapper (the unit-test seam), decorates results with `Add-SsisTypeName`, and emits immediately. Neither command changes state, so neither declares `SupportsShouldProcess`.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder, Pester v5, the `Microsoft.SqlServer.Management.IntegrationServices` MOM (loaded from `dbatools.library`).

---

## MOM member names — ALREADY VERIFIED BY REFLECTION (2026-06-01)

The spec's §5 reflection check is **done**; use these exact names. Do not re-guess.

- **`Catalog.Operations`** → `OperationCollection`, indexer `this[Int64] -> Operation` (identical shape to `Catalog.Executions`). `Catalog.Operations[$id]` returns the operation or `$null` when absent.
- **`Operation`** (base type of `ExecutionOperation`) members used here: `.Id` (Int64), `.OperationType` (**Int16 raw code — NOT an enum**, e.g. 300=execution, 101=deploy project, 200=validate; renders as a number), `.Status` (`ServerOperationStatus`, the same enum as Phase 4a), `.StartTime`/`.EndTime`/`.CreatedTime` (`Nullable<DateTime>`), `.CallerName` (String), `.ObjectName` (String), `.Messages` (`OperationMessageCollection`).
- **`ExecutionOperation.Messages`** is the inherited `.Messages` collection — read it directly.
- **`OperationMessageCollection`** has a `this[Int64] -> OperationMessage` indexer and is enumerable.
- **`OperationMessage`** members used here: `.Id` (Int64), `.Message` (String), `.MessageTime` (**`DateTimeOffset`**), `.MessageType` and `.MessageSourceType` (both **`Nullable<Int16>` raw codes — NOT enums**, e.g. MessageType 120=Error, 110=Warning, 70=Information).
- **`ServerOperationStatus` ValidateSet names** (reuse exactly, from Phase 4a): `Created`, `Running`, `Canceled` (one L), `Failed`, `Pending`, `UnexpectTerminated`, `Success`, `Stopping`, `Completion`.

## File structure

| File | Responsibility |
|------|----------------|
| `source/Private/Get-SsisExecutionMessageObject.ps1` (create) | Interop seam: returns `$Execution.Messages`. |
| `source/Private/Get-SsisOperationObject.ps1` (create) | Interop seam: returns `Catalog.Operations` or `Catalog.Operations[id]`. |
| `source/Public/Get-SsisExecutionMessage.ps1` (create) | Resolve execution (by id or piped `Ssis.Execution`), emit its messages as `Ssis.ExecutionMessage`. |
| `source/Public/Get-SsisOperation.ps1` (create) | List/query operations; `-OperationId`, `-Status`, `-Top`; emit as `Ssis.Operation`. |
| `source/IntegrationServicesTools.format.ps1xml` (modify) | Add `Ssis.ExecutionMessage` and `Ssis.Operation` table views. |
| `tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1` (create) | Unit test for the message wrapper. |
| `tests/Unit/Private/Get-SsisOperationObject.tests.ps1` (create) | Unit test for the operation wrapper. |
| `tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1` (create) | Unit tests: param sets, resolution, warnings, decoration. |
| `tests/Unit/Public/Get-SsisOperation.tests.ps1` (create) | Unit tests: id vs filter, `-Status`, `-Top`, warning, decoration. |
| `tests/Integration/Ssis.Monitoring.Integration.tests.ps1` (create) | Opt-in live test against `$env:SSIS_TEST_INSTANCE`. |

## How to build & run tests in this project

ModuleBuilder merges `source/` into a single built `.psm1`, so the **module must be rebuilt before tests can see new functions**. Standard cycle used throughout this plan:

```powershell
# Build (run after adding/changing any source file)
./build.ps1 -Tasks build

# Run a single test file (output/module + output/RequiredModules must be on PSModulePath)
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1 -Output Detailed
```

For a TDD RED step, run the test against the **current** built module (the new function is absent, so it fails). For GREEN, rebuild first, then run.

---

## Task 1: `Get-SsisExecutionMessageObject` (private interop seam)

**Files:**
- Create: `source/Private/Get-SsisExecutionMessageObject.ps1`
- Test: `tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionMessageObject' {
    It 'Returns the execution Messages collection' {
        InModuleScope $script:moduleName {
            $execution = [PSCustomObject]@{ Messages = @('msg1', 'msg2') }
            $result = Get-SsisExecutionMessageObject -Execution $execution
            $result | Should -Be @('msg1', 'msg2')
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisExecutionMessageObject` is not recognized.

- [ ] **Step 3: Write minimal implementation**

Create `source/Private/Get-SsisExecutionMessageObject.ps1`:

```powershell
function Get-SsisExecutionMessageObject
{
    <#
        .SYNOPSIS
            Returns the message log recorded for an SSISDB execution.

        .DESCRIPTION
            Returns the execution's Messages collection (OperationMessage objects). Reading the
            collection re-reads the messages from the server. Internal interop helper, not exported
            from the module.

        .EXAMPLE
            $messages = Get-SsisExecutionMessageObject -Execution $execution

            Returns every message logged for the execution.

        .PARAMETER Execution
            The ExecutionOperation whose messages to read, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.OperationMessage
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.OperationMessage')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        return $Execution.Messages
    }
}
```

- [ ] **Step 4: Rebuild and run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1 -Output Detailed
```
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Get-SsisExecutionMessageObject.ps1 tests/Unit/Private/Get-SsisExecutionMessageObject.tests.ps1
git commit -m "feat: add Get-SsisExecutionMessageObject interop wrapper"
```

---

## Task 2: `Get-SsisOperationObject` (private interop seam)

**Files:**
- Create: `source/Private/Get-SsisOperationObject.ps1`
- Test: `tests/Unit/Private/Get-SsisOperationObject.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Private/Get-SsisOperationObject.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisOperationObject' {
    It 'Returns the whole Operations collection when no id is given' {
        InModuleScope $script:moduleName {
            $catalog = [PSCustomObject]@{ Operations = @('op1', 'op2') }
            $result = Get-SsisOperationObject -Catalog $catalog
            $result | Should -Be @('op1', 'op2')
        }
    }

    It 'Indexes the collection by id when -OperationId is given' {
        InModuleScope $script:moduleName {
            # A hashtable exposes the same [] indexer semantics as the real MOM collection.
            $operations = @{ [long]7 = 'op-7' }
            $catalog = [PSCustomObject]@{ Operations = $operations }

            $result = Get-SsisOperationObject -Catalog $catalog -OperationId 7
            $result | Should -Be 'op-7'
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisOperationObject.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisOperationObject` is not recognized.

- [ ] **Step 3: Write minimal implementation**

Create `source/Private/Get-SsisOperationObject.ps1`:

```powershell
function Get-SsisOperationObject
{
    <#
        .SYNOPSIS
            Returns SSISDB operations from a catalog, optionally a single one by id.

        .DESCRIPTION
            Returns the catalog's Operations collection, or a single Operation when -OperationId is
            supplied (indexed from the collection). Operations include executions, deployments, and
            validations. Internal interop helper, not exported from the module.

        .EXAMPLE
            $operations = Get-SsisOperationObject -Catalog $catalog

            Returns every operation recorded in the catalog.

        .EXAMPLE
            $operation = Get-SsisOperationObject -Catalog $catalog -OperationId 7

            Returns the operation with id 7.

        .PARAMETER Catalog
            The SSISDB Catalog object whose operations to read, as returned by Get-SsisCatalogObject.

        .PARAMETER OperationId
            The numeric id of a single operation to return. When omitted, the whole collection is
            returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.Operation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Operation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter()]
        [long]
        $OperationId
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('OperationId'))
        {
            return $Catalog.Operations[$OperationId]
        }

        return $Catalog.Operations
    }
}
```

- [ ] **Step 4: Rebuild and run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Private/Get-SsisOperationObject.tests.ps1 -Output Detailed
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Private/Get-SsisOperationObject.ps1 tests/Unit/Private/Get-SsisOperationObject.tests.ps1
git commit -m "feat: add Get-SsisOperationObject interop wrapper"
```

---

## Task 3: `Get-SsisExecutionMessage` (public command)

**Files:**
- Create: `source/Public/Get-SsisExecutionMessage.ps1`
- Test: `tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisExecutionMessage' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        $script:messages = @(
            [PSCustomObject]@{ Id = 1; Message = 'Start'; MessageType = 70 }
            [PSCustomObject]@{ Id = 2; Message = 'Boom'; MessageType = 120 }
        )
    }

    It 'Returns messages for an execution by id, decorated as Ssis.ExecutionMessage' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 42 }
        } -ParameterFilter { $ExecutionId -eq 42 }
        Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 42
        ($result | Measure-Object).Count | Should -Be 2
        $result[0].PSObject.TypeNames | Should -Contain 'Ssis.ExecutionMessage'
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 1 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    It 'Warns and returns nothing when the execution is not found' {
        Mock -CommandName Get-SsisExecutionObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisExecutionMessage -SqlInstance 'TestInstance' -ExecutionId 999 -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Reads messages off a piped Ssis.Execution without reconnecting' {
            Mock -CommandName Get-SsisExecutionMessageObject -ModuleName $script:moduleName -MockWith { $script:messages }

            $execution = [PSCustomObject]@{ Id = 5 }
            $execution.PSObject.TypeNames.Insert(0, 'Ssis.Execution')

            $result = $execution | Get-SsisExecutionMessage
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 2
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisExecutionMessage` is not recognized.

- [ ] **Step 3: Write minimal implementation**

Create `source/Public/Get-SsisExecutionMessage.ps1`:

```powershell
function Get-SsisExecutionMessage
{
    <#
        .SYNOPSIS
            Gets the message log of an SSISDB execution.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the messages recorded for a
            single execution as Ssis.ExecutionMessage objects, or reads the messages of a piped
            Ssis.Execution without reconnecting. Every message is returned; narrow the results with
            Where-Object (for example on MessageType). Writes a warning and returns nothing when the
            catalog or the execution does not exist.

        .EXAMPLE
            Get-SsisExecutionMessage -SqlInstance 'SQL01\PROD' -ExecutionId 42

            Returns every message logged for execution 42.

        .EXAMPLE
            Get-SsisExecution -SqlInstance 'SQL01\PROD' -Status 'Failed' | Get-SsisExecutionMessage

            Returns the messages of each failed execution.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER ExecutionId
            The numeric id of the execution whose messages to return.

        .PARAMETER InputObject
            A piped Ssis.Execution object whose messages to read, used instead of
            -SqlInstance/-ExecutionId to keep the existing connection.

        .OUTPUTS
            Ssis.ExecutionMessage
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.ExecutionMessage')]
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
        $InputObject
    )

    process
    {
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

        $messages = Get-SsisExecutionMessageObject -Execution $execution

        foreach ($message in $messages)
        {
            if ($null -eq $message)
            {
                continue
            }

            $message | Add-SsisTypeName -TypeName 'Ssis.ExecutionMessage'
        }
    }
}
```

- [ ] **Step 4: Rebuild and run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1 -Output Detailed
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Get-SsisExecutionMessage.ps1 tests/Unit/Public/Get-SsisExecutionMessage.tests.ps1
git commit -m "feat: add Get-SsisExecutionMessage command"
```

---

## Task 4: `Get-SsisOperation` (public command)

**Files:**
- Create: `source/Public/Get-SsisOperation.ps1`
- Test: `tests/Unit/Public/Get-SsisOperation.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Unit/Public/Get-SsisOperation.tests.ps1`:

```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisOperation' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }

        # Three operations spanning two types and two statuses.
        $script:allOps = @(
            [PSCustomObject]@{ Id = 1; OperationType = 300; Status = 'Success' }
            [PSCustomObject]@{ Id = 2; OperationType = 300; Status = 'Failed' }
            [PSCustomObject]@{ Id = 3; OperationType = 101; Status = 'Success' }
        )
    }

    It 'Returns a single operation by id, decorated as Ssis.Operation' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith {
            [PSCustomObject]@{ Id = 9; OperationType = 300; Status = 'Success' }
        } -ParameterFilter { $OperationId -eq 9 }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -OperationId 9
        $result.Id | Should -Be 9
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
    }

    It 'Filters by -Status' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -Status 'Success'
        ($result | Measure-Object).Count | Should -Be 2
        $result.Status | Should -Not -Contain 'Failed'
    }

    It 'Caps to the most recent N with -Top, highest Id first' {
        Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

        $result = Get-SsisOperation -SqlInstance 'TestInstance' -Top 2
        ($result | Measure-Object).Count | Should -Be 2
        $result[0].Id | Should -Be 3
        $result[1].Id | Should -Be 2
    }

    It 'Warns and returns nothing when the catalog does not exist' {
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
        $result = Get-SsisOperation -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
    }

    Context 'ByObject' {
        It 'Lists operations of a piped Ssis.Catalog without reconnecting' {
            Mock -CommandName Get-SsisOperationObject -ModuleName $script:moduleName -MockWith { $script:allOps }

            $catalog = [PSCustomObject]@{ Name = 'SSISDB' }
            $catalog.PSObject.TypeNames.Insert(0, 'Ssis.Catalog')

            $result = $catalog | Get-SsisOperation
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            ($result | Measure-Object).Count | Should -Be 3
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisOperation.tests.ps1 -Output Detailed
```
Expected: FAIL — `Get-SsisOperation` is not recognized.

- [ ] **Step 3: Write minimal implementation**

Create `source/Public/Get-SsisOperation.ps1`:

```powershell
function Get-SsisOperation
{
    <#
        .SYNOPSIS
            Gets operations (executions, deployments, validations) from the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB operations as
            Ssis.Operation objects. Returns a single operation when -OperationId is given; otherwise
            lists operations, narrowed by -Status and/or capped to the most recent N by -Top. Accepts
            a piped Ssis.Catalog to list its operations without reconnecting. Writes a warning and
            returns nothing when the catalog does not exist.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -OperationId 7

            Returns the operation with id 7.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -Top 20

            Returns the 20 most recent operations, newest first.

        .EXAMPLE
            Get-SsisOperation -SqlInstance 'SQL01\PROD' -Status 'Failed'

            Returns every failed operation in the catalog.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER OperationId
            The numeric id of a single operation to return. When given, the -Status and -Top
            parameters are ignored.

        .PARAMETER InputObject
            A piped Ssis.Catalog object whose operations to list, used instead of -SqlInstance to
            keep the existing connection.

        .PARAMETER Status
            Returns only operations in the given status (for example Running, Success, Failed).

        .PARAMETER Top
            Caps the output to the most recent N operations (highest id first). Applies when listing;
            ignored when -OperationId is given.

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

        [Parameter(ParameterSetName = 'ByInstance')]
        [long]
        $OperationId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [ValidateSet('Created', 'Running', 'Canceled', 'Failed', 'Pending', 'UnexpectTerminated', 'Success', 'Stopping', 'Completion')]
        [string]
        $Status,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]
        $Top
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $catalog = $InputObject
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

            if ($PSBoundParameters.ContainsKey('OperationId'))
            {
                $operation = Get-SsisOperationObject -Catalog $catalog -OperationId $OperationId

                if ($null -eq $operation)
                {
                    Write-Warning -Message ('Operation ''{0}'' was not found in the SSISDB catalog.' -f $OperationId)
                    return
                }

                $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
                return
            }
        }

        $operations = Get-SsisOperationObject -Catalog $catalog

        if ($PSBoundParameters.ContainsKey('Top'))
        {
            $hasStatus = $PSBoundParameters.ContainsKey('Status')

            $operations |
                Where-Object -FilterScript { $null -ne $_ -and (-not $hasStatus -or $_.Status.ToString() -eq $Status) } |
                Sort-Object -Property Id -Descending |
                Select-Object -First $Top |
                ForEach-Object -Process { $_ | Add-SsisTypeName -TypeName 'Ssis.Operation' }

            return
        }

        foreach ($operation in $operations)
        {
            if ($null -eq $operation)
            {
                continue
            }

            if ($PSBoundParameters.ContainsKey('Status') -and $operation.Status.ToString() -ne $Status)
            {
                continue
            }

            $operation | Add-SsisTypeName -TypeName 'Ssis.Operation'
        }
    }
}
```

- [ ] **Step 4: Rebuild and run test to verify it passes**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Unit/Public/Get-SsisOperation.tests.ps1 -Output Detailed
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```powershell
git add source/Public/Get-SsisOperation.ps1 tests/Unit/Public/Get-SsisOperation.tests.ps1
git commit -m "feat: add Get-SsisOperation command"
```

---

## Task 5: Format views for `Ssis.ExecutionMessage` and `Ssis.Operation`

**Files:**
- Modify: `source/IntegrationServicesTools.format.ps1xml` (add two `<View>` blocks before the closing `</ViewDefinitions>`)

There is no unit test for format files (Sampler QA validates manifest/help, not view XML); verification is the build + a `Format-Table` smoke check.

- [ ] **Step 1: Add the two views**

In `source/IntegrationServicesTools.format.ps1xml`, immediately before the `</ViewDefinitions>` line, insert:

```xml
    <View>
      <Name>Ssis.ExecutionMessage</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.ExecutionMessage</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>MessageTime</Label></TableColumnHeader>
          <TableColumnHeader><Label>MessageSourceType</Label></TableColumnHeader>
          <TableColumnHeader><Label>MessageType</Label></TableColumnHeader>
          <TableColumnHeader><Label>Message</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>MessageTime</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>MessageSourceType</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>MessageType</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Message</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
    <View>
      <Name>Ssis.Operation</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Operation</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Id</Label></TableColumnHeader>
          <TableColumnHeader><Label>OperationType</Label></TableColumnHeader>
          <TableColumnHeader><Label>Status</Label></TableColumnHeader>
          <TableColumnHeader><Label>StartTime</Label></TableColumnHeader>
          <TableColumnHeader><Label>EndTime</Label></TableColumnHeader>
          <TableColumnHeader><Label>CallerName</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Id</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>OperationType</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Status</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>StartTime</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>EndTime</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>CallerName</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
```

- [ ] **Step 2: Rebuild and confirm the views load without error**

```powershell
./build.ps1 -Tasks build
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
# A decorated object should render with the new view, not an error.
$m = [PSCustomObject]@{ MessageTime = (Get-Date); MessageSourceType = 10; MessageType = 120; Message = 'x' }
$m.PSObject.TypeNames.Insert(0, 'Ssis.ExecutionMessage')
$m | Format-Table | Out-String
$o = [PSCustomObject]@{ Id = 1; OperationType = 300; Status = 'Success'; StartTime = (Get-Date); EndTime = (Get-Date); CallerName = 'me' }
$o.PSObject.TypeNames.Insert(0, 'Ssis.Operation')
$o | Format-Table | Out-String
```
Expected: both render as tables with the defined columns; no XML/parse errors at import.

- [ ] **Step 3: Commit**

```powershell
git add source/IntegrationServicesTools.format.ps1xml
git commit -m "feat: add Ssis.ExecutionMessage and Ssis.Operation format views"
```

---

## Task 6: Integration test

**Files:**
- Create: `tests/Integration/Ssis.Monitoring.Integration.tests.ps1`

This test self-skips when `$env:SSIS_TEST_INSTANCE` is unset or the fixture `.ispac` is absent (mirrors `Ssis.Execution.Integration.tests.ps1`).

- [ ] **Step 1: Create the integration test**

Create `tests/Integration/Ssis.Monitoring.Integration.tests.ps1`:

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
    $script:folderName = 'ISTools_MonitorTest'
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

    $splatStart = @{
        SqlInstance  = $script:instance
        Folder       = $script:folderName
        Project      = $script:projectName
        Package      = $script:packageName
        LoggingLevel = 'Basic'
        Synchronous  = $true
        Timeout      = 300
        Confirm      = $false
    }
    $script:execution = Start-SsisExecution @splatStart
}

AfterAll {
    & $script:removeFolderIfPresent $script:instance $script:folderName

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Execution monitoring (integration)' -Tag 'Integration' -Skip:$script:skipIntegration {
    It 'Returns the execution message log by id' {
        $messages = Get-SsisExecutionMessage -SqlInstance $script:instance -ExecutionId $script:execution.Id
        ($messages | Measure-Object).Count | Should -BeGreaterThan 0
        $messages[0].PSObject.TypeNames | Should -Contain 'Ssis.ExecutionMessage'
    }

    It 'Returns the message log of a piped execution' {
        $messages = $script:execution | Get-SsisExecutionMessage
        ($messages | Measure-Object).Count | Should -BeGreaterThan 0
    }

    It 'Returns the matching operation by id' {
        # An execution is itself an operation sharing the same id.
        $operation = Get-SsisOperation -SqlInstance $script:instance -OperationId $script:execution.Id
        $operation.Id | Should -Be $script:execution.Id
        $operation.PSObject.TypeNames | Should -Contain 'Ssis.Operation'
    }

    It 'Caps a listing to the most recent N with -Top, newest first' {
        $operations = Get-SsisOperation -SqlInstance $script:instance -Top 5
        ($operations | Measure-Object).Count | Should -BeLessOrEqual 5
        if (($operations | Measure-Object).Count -gt 1)
        {
            $operations[0].Id | Should -BeGreaterThan $operations[-1].Id
        }
    }
}
```

- [ ] **Step 2: Confirm it skips cleanly with no instance configured**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
$env:SSIS_TEST_INSTANCE = $null
Invoke-Pester -Path tests/Integration/Ssis.Monitoring.Integration.tests.ps1 -Output Detailed
```
Expected: tests reported as Skipped (not Failed).

- [ ] **Step 3: Commit**

```powershell
git add tests/Integration/Ssis.Monitoring.Integration.tests.ps1
git commit -m "test: add Phase 4b monitoring integration tests"
```

---

## Task 7: Full verification (QA + unit, then integration)

**Files:** none (verification only)

- [ ] **Step 1: Full build + test (QA + unit) green**

```powershell
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```
Expected: QA tests (help, PSScriptAnalyzer, manifest) and all unit tests pass. The new functions appear in the built manifest automatically (no manual export). A unit-only run reports a coverage shortfall *by design* (interop wrappers are integration-only) — that is expected, not a failure of this work.

- [ ] **Step 2: Confirm the new commands are exported**

```powershell
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
Get-Command -Module IntegrationServicesTools -Name Get-SsisExecutionMessage, Get-SsisOperation
```
Expected: both commands listed.

- [ ] **Step 3: Run the comprehensive suite against a live instance (REQUIRED before any PR)**

Per project policy, the integration tests must actually RUN (not skip) and be green before opening a PR.

```powershell
$env:SSIS_TEST_INSTANCE = 'localhost'
$env:PSModulePath = "$PWD/output/module;$PWD/output/RequiredModules;$env:PSModulePath"
Invoke-Pester -Path tests/Integration/Ssis.Monitoring.Integration.tests.ps1 -Output Detailed
Invoke-Pester -Path tests/Integration/Ssis.Execution.Integration.tests.ps1 -Output Detailed
```
Expected: monitoring integration tests run and pass; the existing execution integration tests still pass (no regression). If the message-type/source columns or any property surfaced differently than the verified names predict, fix the column/property and re-run.

- [ ] **Step 4: Final verification before claiming done**

Use the superpowers:verification-before-completion skill. Confirm:
- No backticks; splats for 3+ params, aligned; Allman braces; single quotes; `Mandatory = $true`; 4-space indent.
- Every new public and private function has its own `.tests.ps1` and full comment-based help incl. `.OUTPUTS`.
- Both commands return `Ssis.*`-decorated objects with clean default views and emit immediately (the `-Top` cap is the documented exception).
- `./build.ps1 -Tasks test` green; integration tests pass live and skip cleanly when `$env:SSIS_TEST_INSTANCE` is unset.

---

## Self-review notes (already reconciled)

- **Spec coverage:** §3.1 → Task 3; §3.2 (incl. `-Top` sort/cap and `-OperationId`/`-Status`) → Task 4; §4 wrappers → Tasks 1–2; §6 types/views → Tasks 3/4 (decoration) + Task 5 (views); §8 testing → unit tests in Tasks 1–4, private-wrapper tests in Tasks 1–2, integration in Task 6; §9 acceptance → Task 7.
- **MOM names:** all property names (`Messages`, `Operations`, `Id`, `OperationType`, `Status`, `MessageTime`, `MessageType`, `MessageSourceType`, `Message`, `StartTime`, `EndTime`, `CallerName`) and the `ServerOperationStatus` ValidateSet are the reflection-verified names — consistent across tasks, tests, and the format file.
- **No `-OperationType` filter, no message filters** — matches the locked decisions.
