# SSIS Tools — Phase 3a (Environments & Variables) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the environments and environment-variables command surface to `IntegrationServicesTools` — `Get-SsisEnvironment`, `New-SsisEnvironment`, `Remove-SsisEnvironment`, `Get-SsisEnvironmentVariable`, `Set-SsisEnvironmentVariable`, `Remove-SsisEnvironmentVariable` — enabling `Get-SsisFolder | Get-SsisEnvironment | Get-SsisEnvironmentVariable` and a typed, upserting variable workflow.

**Architecture:** Public `Verb-Ssis*` functions own parameter sets, validation, `ShouldProcess`, and `Ssis.*` decoration; they delegate every real MOM call to thin private interop wrappers (`Get-/New-/Remove-SsisEnvironmentObject`, `Get-/Set-/Remove-SsisEnvironmentVariableObject`) and one pure, fully-unit-testable helper (`ConvertTo-SsisTypeCode`). Each mutating wrapper owns its MOM persist call (`Create`/`Alter`/`Drop`) — the one new wrinkle versus Phase 2, whose MOM calls persisted immediately. Unit tests mock the seam (no SQL Server); integration tests (tagged `Integration`) exercise the real types.

**Tech Stack:** Windows PowerShell 5.1 (Desktop), Sampler/ModuleBuilder build, Pester v5, PSScriptAnalyzer, `Microsoft.SqlServer.Management.IntegrationServices` MOM (loaded from `dbatools.library`), SMO.

**Spec:** `docs/superpowers/specs/2026-06-01-ssis-environments-parameters-design.md` (this is plan 3a of two; plan 3b covers references & parameters).

---

## Read before starting (carried over from Phase 0–2)

1. **Two real parameter sets.** Like Phase 2, these commands declare `DefaultParameterSetName = 'ByInstance'` plus a `ByObject` set whose `-InputObject` binds a piped `Ssis.*` MOM object (`ValueFromPipeline`). `-SqlInstance` is positional/mandatory in `ByInstance` and carries **no** `ValueFrom*` attribute (so a piped object routes to `ByObject` cleanly). Keep `-InputObject` the only pipeline-bound parameter.
2. **Sampler QA gates *private* functions too.** Every new private wrapper/helper needs its own `tests/Unit/Private/<Name>.tests.ps1`, must pass PSScriptAnalyzer, and must have full comment-based help (`.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` whose text contains the function name, and a > 25-char description for **every** parameter). Public functions additionally need `.OUTPUTS`.
3. **State-changing private wrappers** trip `PSUseShouldProcessForStateChangingFunctions` for verbs New/Set/Remove. Each such wrapper (`New-SsisEnvironmentObject`, `Remove-SsisEnvironmentObject`, `Set-SsisEnvironmentVariableObject`, `Remove-SsisEnvironmentVariableObject`) carries the `[SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', …)]` justification used by the Phase 1/2 seam. `Get-` and `ConvertTo-` wrappers do not trigger the rule.
4. **The persist wrinkle.** Unlike Phase 2, the environment objects do not persist on mutation. The wrappers own the persist call: `New-SsisEnvironmentObject` calls `.Create()`; `Set-`/`Remove-SsisEnvironmentVariableObject` call `environment.Alter()`; `Remove-SsisEnvironmentObject` calls `.Drop()`. The public layer never calls `Create`/`Alter`/`Drop`.
5. **Coverage threshold stays 85%, met via Integration tests.** The new interop wrappers open real MOM connections, so the gate is only reached when the run includes Integration tests against a real SSISDB (`$env:SSIS_TEST_INSTANCE`). `ConvertTo-SsisTypeCode` is the one new fully-unit-testable helper. Do **not** add coverage-exclusion entries.
6. **Inner TDD loop** — rebuild before tests see a source change:
   ```powershell
   ./build.ps1 -Tasks build
   # once per shell — prepend BOTH the built module and resolved RequiredModules:
   $env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
   Invoke-Pester -Path ./tests/Unit/Public/<File>.tests.ps1 -Output Detailed
   ```
   Full QA/test run: `./build.ps1 -Tasks build,test`.

## MOM members used (verify exact names during TDD — Task 3 Step 6)

These are the assumed `Microsoft.SqlServer.Management.IntegrationServices` members. The **first GREEN run that loads the real assembly** (Task 3 Step 6) is the checkpoint to confirm them; if a name differs, fix it in that task and the dependent tasks before proceeding.

- `CatalogFolder.Environments` — collection with `.Contains(string)` and `[string]` indexer (like `.Folders`).
- `EnvironmentInfo(CatalogFolder parent, string name, string description)` constructor + `.Create()`, `.Alter()`, `.Drop()`.
- `EnvironmentInfo.Name`, `.Description`, `.Parent` (→ `CatalogFolder`), `.Variables`.
- `EnvironmentInfo.Variables` — `EnvironmentVariableInfoCollection` with `.Contains(string)`, `[string]` indexer, `.Add(string name, System.TypeCode type, object value, bool sensitive, string description)`, and `.Remove(string name)`.
- `EnvironmentVariableInfo.Name`, `.Type` (`System.TypeCode`), `.Value`, `.Sensitive`, `.Description`, `.Parent` (→ `EnvironmentInfo`).

> If `Variables.Add` / `Variables.Remove` signatures differ (e.g. `Remove` takes the variable object, or `Add` returns the new variable), adjust `Set-`/`Remove-SsisEnvironmentVariableObject` accordingly — they are the only places these are called.

## File structure

```
source/IntegrationServicesTools.format.ps1xml                       modify  append Ssis.Environment + Ssis.EnvironmentVariable views
source/Private/ConvertTo-SsisTypeCode.ps1                           create  value/-DataType -> System.TypeCode (pure, unit-tested)
source/Private/Get-SsisEnvironmentObject.ps1                        create  folder.Environments / [name] -> EnvironmentInfo|$null (interop)
source/Private/New-SsisEnvironmentObject.ps1                        create  new EnvironmentInfo(...).Create() (interop)
source/Private/Remove-SsisEnvironmentObject.ps1                     create  environment.Drop() (interop)
source/Private/Get-SsisEnvironmentVariableObject.ps1                create  environment.Variables / [name] -> EnvironmentVariableInfo|$null (interop)
source/Private/Set-SsisEnvironmentVariableObject.ps1                create  add/update variable + environment.Alter() (interop)
source/Private/Remove-SsisEnvironmentVariableObject.ps1             create  variables.Remove(name) + environment.Alter() (interop)
source/Public/Get-SsisEnvironment.ps1                               create
source/Public/New-SsisEnvironment.ps1                               create
source/Public/Remove-SsisEnvironment.ps1                            create
source/Public/Get-SsisEnvironmentVariable.ps1                       create
source/Public/Set-SsisEnvironmentVariable.ps1                       create
source/Public/Remove-SsisEnvironmentVariable.ps1                    create
tests/Unit/Private/ConvertTo-SsisTypeCode.tests.ps1                 create
tests/Unit/Private/Get-SsisEnvironmentObject.tests.ps1             create
tests/Unit/Private/New-SsisEnvironmentObject.tests.ps1            create
tests/Unit/Private/Remove-SsisEnvironmentObject.tests.ps1         create
tests/Unit/Private/Get-SsisEnvironmentVariableObject.tests.ps1    create
tests/Unit/Private/Set-SsisEnvironmentVariableObject.tests.ps1    create
tests/Unit/Private/Remove-SsisEnvironmentVariableObject.tests.ps1 create
tests/Unit/Public/Get-SsisEnvironment.tests.ps1                    create
tests/Unit/Public/New-SsisEnvironment.tests.ps1                    create
tests/Unit/Public/Remove-SsisEnvironment.tests.ps1                 create
tests/Unit/Public/Get-SsisEnvironmentVariable.tests.ps1           create
tests/Unit/Public/Set-SsisEnvironmentVariable.tests.ps1           create
tests/Unit/Public/Remove-SsisEnvironmentVariable.tests.ps1        create
tests/Integration/Ssis.Environment.Integration.tests.ps1          create  (tagged Integration; skipped without instance)
CHANGELOG.md                                                       modify  one Unreleased entry per command
```

---

## Task 1: Format views — `Ssis.Environment` and `Ssis.EnvironmentVariable`

**Files:**
- Modify: `source/IntegrationServicesTools.format.ps1xml`

- [ ] **Step 1: Append two views before `</ViewDefinitions>`**

In `source/IntegrationServicesTools.format.ps1xml`, insert these two `<View>` blocks immediately **after** the closing `</View>` of the `Ssis.Package` view and **before** `</ViewDefinitions>`:

```xml
    <View>
      <Name>Ssis.Environment</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.Environment</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Name</Label></TableColumnHeader>
          <TableColumnHeader><Label>Folder</Label></TableColumnHeader>
          <TableColumnHeader><Label>Variables</Label></TableColumnHeader>
          <TableColumnHeader><Label>Description</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>$_.Parent.Name</ScriptBlock></TableColumnItem>
              <TableColumnItem><ScriptBlock>$_.Variables.Count</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>Description</PropertyName></TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
    <View>
      <Name>Ssis.EnvironmentVariable</Name>
      <ViewSelectedBy>
        <TypeName>Ssis.EnvironmentVariable</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader><Label>Name</Label></TableColumnHeader>
          <TableColumnHeader><Label>Environment</Label></TableColumnHeader>
          <TableColumnHeader><Label>DataType</Label></TableColumnHeader>
          <TableColumnHeader><Label>Value</Label></TableColumnHeader>
          <TableColumnHeader><Label>Sensitive</Label></TableColumnHeader>
          <TableColumnHeader><Label>Description</Label></TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem><PropertyName>Name</PropertyName></TableColumnItem>
              <TableColumnItem><ScriptBlock>$_.Parent.Name</ScriptBlock></TableColumnItem>
              <TableColumnItem><PropertyName>Type</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Value</PropertyName></TableColumnItem>
              <TableColumnItem><PropertyName>Sensitive</PropertyName></TableColumnItem>
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
(Get-FormatData -TypeName 'Ssis.Environment') | Should -Not -BeNullOrEmpty
(Get-FormatData -TypeName 'Ssis.EnvironmentVariable') | Should -Not -BeNullOrEmpty
```
Expected: import succeeds; both `Get-FormatData` calls return a view (no error).

- [ ] **Step 3: Commit**

```powershell
git add -A
git commit -m "feat: add Ssis.Environment and Ssis.EnvironmentVariable format views"
```

---

## Task 2: Pure helper — `ConvertTo-SsisTypeCode`

**Files:**
- Create: `source/Private/ConvertTo-SsisTypeCode.ps1`
- Test: `tests/Unit/Private/ConvertTo-SsisTypeCode.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/ConvertTo-SsisTypeCode.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-SsisTypeCode' {
    Context 'Inference from the value .NET type' {
        It 'Maps <Label> to <Expected>' -ForEach @(
            @{ Label = 'Int32';    Value = [int]42;            Expected = 'Int32' }
            @{ Label = 'Int64';    Value = [long]42;           Expected = 'Int64' }
            @{ Label = 'String';   Value = 'hello';            Expected = 'String' }
            @{ Label = 'Boolean';  Value = $true;              Expected = 'Boolean' }
            @{ Label = 'Decimal';  Value = [decimal]1.5;       Expected = 'Decimal' }
            @{ Label = 'Double';   Value = [double]1.5;        Expected = 'Double' }
            @{ Label = 'DateTime'; Value = [datetime]'2026-01-01'; Expected = 'DateTime' }
        ) {
            InModuleScope $script:moduleName -Parameters $PSItem {
                param ($Value, $Expected)
                (ConvertTo-SsisTypeCode -Value $Value).ToString() | Should -Be $Expected
            }
        }

        It 'Defaults a null value to String' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value $null).ToString() | Should -Be 'String'
            }
        }
    }

    Context 'Explicit -DataType override' {
        It 'Returns the named type code regardless of the value type' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value 'hello' -DataType 'Int32').ToString() | Should -Be 'Int32'
            }
        }

        It 'Is case-insensitive' {
            InModuleScope $script:moduleName {
                (ConvertTo-SsisTypeCode -Value 1 -DataType 'int64').ToString() | Should -Be 'Int64'
            }
        }

        It 'Throws on an unsupported data type name' {
            InModuleScope $script:moduleName {
                { ConvertTo-SsisTypeCode -Value 1 -DataType 'Guid' } | Should -Throw -ExpectedMessage '*Guid*'
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/ConvertTo-SsisTypeCode.tests.ps1 -Output Detailed`
Expected: FAIL — `ConvertTo-SsisTypeCode` not recognized.

- [ ] **Step 3: Write `source/Private/ConvertTo-SsisTypeCode.ps1`**

```powershell
function ConvertTo-SsisTypeCode
{
    <#
        .SYNOPSIS
            Resolves a System.TypeCode for an SSISDB environment variable from a value or a name.

        .DESCRIPTION
            Returns the System.TypeCode the SSIS object model needs when adding an environment variable.
            When -DataType is supplied it is looked up (case-insensitively) against the SSIS-supported
            type names. Otherwise the type code is inferred from the supplied value's .NET type, falling
            back to String for a null value. Pure helper with no object-model calls; not exported.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value 42

            Returns [System.TypeCode]::Int32, inferred from the integer value.

        .EXAMPLE
            $typeCode = ConvertTo-SsisTypeCode -Value '5' -DataType 'Int32'

            Returns [System.TypeCode]::Int32, forced by the explicit data type name.

        .PARAMETER Value
            The value whose .NET type is used to infer the type code when -DataType is not supplied.
            A null value infers String. Ignored when -DataType is given.

        .PARAMETER DataType
            An explicit SSIS data type name (Boolean, Byte, Int16, Int32, Int64, Single, Double,
            Decimal, DateTime, String) that overrides inference. Matched case-insensitively.
    #>
    [CmdletBinding()]
    [OutputType([System.TypeCode])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [string]
        $DataType
    )

    process
    {
        $supported = @{
            'Boolean'  = [System.TypeCode]::Boolean
            'Byte'     = [System.TypeCode]::Byte
            'Int16'    = [System.TypeCode]::Int16
            'Int32'    = [System.TypeCode]::Int32
            'Int64'    = [System.TypeCode]::Int64
            'Single'   = [System.TypeCode]::Single
            'Double'   = [System.TypeCode]::Double
            'Decimal'  = [System.TypeCode]::Decimal
            'DateTime' = [System.TypeCode]::DateTime
            'String'   = [System.TypeCode]::String
        }

        if (-not [string]::IsNullOrEmpty($DataType))
        {
            $match = $supported.Keys | Where-Object -FilterScript { $_ -eq $DataType }

            if ($null -eq $match)
            {
                throw ('Unsupported data type ''{0}''. Valid values: {1}.' -f $DataType, (($supported.Keys | Sort-Object) -join ', '))
            }

            return $supported[$match]
        }

        if ($null -eq $Value)
        {
            return [System.TypeCode]::String
        }

        return [System.Type]::GetTypeCode($Value.GetType())
    }
}
```

> Note: `$supported.Keys | Where-Object { $_ -eq $DataType }` uses PowerShell's case-insensitive `-eq` to do the case-insensitive match, returning the canonically-cased key.

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/ConvertTo-SsisTypeCode.tests.ps1 -Output Detailed`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```powershell
git add -A
git commit -m "feat: add ConvertTo-SsisTypeCode environment-variable type helper"
```

---

## Task 3: Private interop — read wrappers (`Get-SsisEnvironmentObject`, `Get-SsisEnvironmentVariableObject`)

**Files:**
- Create: `source/Private/Get-SsisEnvironmentObject.ps1`
- Create: `source/Private/Get-SsisEnvironmentVariableObject.ps1`
- Test: `tests/Unit/Private/Get-SsisEnvironmentObject.tests.ps1`
- Test: `tests/Unit/Private/Get-SsisEnvironmentVariableObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/Get-SsisEnvironmentObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentObject' {
    It 'Returns the named environment when it exists' {
        InModuleScope $script:moduleName {
            # A hashtable is a faithful stand-in for the MOM Environments collection: it supports
            # both .Contains(name) and the [name] indexer.
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $folder = [PSCustomObject]@{ Environments = @{ 'Prod' = $environment } }

            $result = Get-SsisEnvironmentObject -Folder $folder -Name 'Prod'

            $result.Name | Should -Be 'Prod'
        }
    }

    It 'Returns $null when the named environment does not exist' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{ Environments = @{} }

            $result = Get-SsisEnvironmentObject -Folder $folder -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Environments collection when no name is given' {
        InModuleScope $script:moduleName {
            $folder = [PSCustomObject]@{
                Environments = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisEnvironmentObject -Folder $folder

            $result.Count | Should -Be 2
        }
    }
}
```

`tests/Unit/Private/Get-SsisEnvironmentVariableObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentVariableObject' {
    It 'Returns the named variable when it exists' {
        InModuleScope $script:moduleName {
            $variable = [PSCustomObject]@{ Name = 'ConnString' }
            $environment = [PSCustomObject]@{ Variables = @{ 'ConnString' = $variable } }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'ConnString'

            $result.Name | Should -Be 'ConnString'
        }
    }

    It 'Returns $null when the named variable does not exist' {
        InModuleScope $script:moduleName {
            $environment = [PSCustomObject]@{ Variables = @{} }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }
    }

    It 'Returns the whole Variables collection when no name is given' {
        InModuleScope $script:moduleName {
            $environment = [PSCustomObject]@{
                Variables = @{
                    'A' = [PSCustomObject]@{ Name = 'A' }
                    'B' = [PSCustomObject]@{ Name = 'B' }
                }
            }

            $result = Get-SsisEnvironmentVariableObject -Environment $environment

            $result.Count | Should -Be 2
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Get-SsisEnvironmentVariableObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/Get-SsisEnvironmentObject.ps1`**

```powershell
function Get-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Returns environment object(s) from an SSISDB catalog folder.

        .DESCRIPTION
            Returns the named environment from the folder's Environments collection, or all environments
            when no name is given. Returns $null when a named environment does not exist. Internal
            interop helper, not exported from the module.

        .EXAMPLE
            $environment = Get-SsisEnvironmentObject -Folder $folder -Name 'Prod'

            Returns the Prod environment, or $null when it does not exist.

        .PARAMETER Folder
            The SSISDB CatalogFolder object whose environments to read, as returned by Get-SsisFolderObject.

        .PARAMETER Name
            The environment name to return. When omitted, every environment in the folder is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo')]
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
            if ($Folder.Environments.Contains($Name))
            {
                return $Folder.Environments[$Name]
            }

            return $null
        }

        return $Folder.Environments
    }
}
```

- [ ] **Step 4: Write `source/Private/Get-SsisEnvironmentVariableObject.ps1`**

```powershell
function Get-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Returns environment-variable object(s) from an SSISDB environment.

        .DESCRIPTION
            Returns the named variable from the environment's Variables collection, or all variables when
            no name is given. Returns $null when a named variable does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $variable = Get-SsisEnvironmentVariableObject -Environment $environment -Name 'ConnString'

            Returns the ConnString variable, or $null when it does not exist.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variables to read, as returned by Get-SsisEnvironmentObject.

        .PARAMETER Name
            The variable name to return. When omitted, every variable in the environment is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentVariableInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Environment.Variables.Contains($Name))
            {
                return $Environment.Variables[$Name]
            }

            return $null
        }

        return $Environment.Variables
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/Get-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Get-SsisEnvironmentVariableObject.tests.ps1 -Output Detailed`
Expected: PASS (3 + 3 tests).

- [ ] **Step 6: Confirm the assumed MOM member names**

With the module imported (rebuild first), verify the members the rest of the plan depends on exist on the real types:
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
[Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder].GetProperty('Environments') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo].GetMethod('Create') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo].GetMethod('Alter') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo].GetMethod('Drop') | Should -Not -BeNullOrEmpty
[Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo].GetProperty('Variables') | Should -Not -BeNullOrEmpty
# Inspect the Variables.Add overload so Task 5's Set wrapper matches the real signature:
[Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo].GetProperty('Variables').PropertyType.GetMethods().Name | Select-Object -Unique
```
Expected: the four `Should` lines return non-null; the last line lists the collection methods (confirm an `Add` and a `Remove` exist and note `Add`'s parameter order). If any name/signature differs, correct it here and in Tasks 4–10 before continuing.

- [ ] **Step 7: Commit**

```powershell
git add -A
git commit -m "feat: add environment and environment-variable read interop wrappers"
```

---

## Task 4: Private interop — action wrappers (environment create/drop, variable set/remove)

**Files:**
- Create: `source/Private/New-SsisEnvironmentObject.ps1`
- Create: `source/Private/Remove-SsisEnvironmentObject.ps1`
- Create: `source/Private/Set-SsisEnvironmentVariableObject.ps1`
- Create: `source/Private/Remove-SsisEnvironmentVariableObject.ps1`
- Test: `tests/Unit/Private/New-SsisEnvironmentObject.tests.ps1`
- Test: `tests/Unit/Private/Remove-SsisEnvironmentObject.tests.ps1`
- Test: `tests/Unit/Private/Set-SsisEnvironmentVariableObject.tests.ps1`
- Test: `tests/Unit/Private/Remove-SsisEnvironmentVariableObject.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests/Unit/Private/New-SsisEnvironmentObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironmentObject' {
    It 'Throws when constructing against a non-MOM folder (reaches the constructor)' {
        InModuleScope $script:moduleName {
            # The wrapper constructs a real EnvironmentInfo from the folder; a plain object is not a
            # CatalogFolder, so the typed constructor rejects it. This proves the wrapper calls the
            # constructor rather than silently succeeding. Real construction is covered by integration.
            $folder = [PSCustomObject]@{ Name = 'Finance' }

            { New-SsisEnvironmentObject -Folder $folder -Name 'Prod' -Description '' } | Should -Throw
        }
    }
}
```

`tests/Unit/Private/Remove-SsisEnvironmentObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentObject' {
    It 'Calls Drop on the supplied environment' {
        InModuleScope $script:moduleName {
            # A PSCustomObject with a Drop() ScriptMethod is a faithful stand-in for the MOM
            # EnvironmentInfo: the wrapper only calls Drop().
            $environment = [PSCustomObject]@{ DropCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Drop' -Value { $this.DropCalled = $true }

            Remove-SsisEnvironmentObject -Environment $environment

            $environment.DropCalled | Should -BeTrue
        }
    }
}
```

`tests/Unit/Private/Set-SsisEnvironmentVariableObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisEnvironmentVariableObject' {
    It 'Adds a new variable and alters the environment when the variable does not exist' {
        InModuleScope $script:moduleName {
            # Variables stand-in for the create branch: .Contains returns false; .Add captures its args.
            # No indexer is needed because the create branch never indexes.
            $variables = [PSCustomObject]@{ Added = $null }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Contains' -Value { param ($n) $false }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Add' -Value {
                param ($name, $type, $value, $sensitive, $description)
                $this.Added = [PSCustomObject]@{ Name = $name; Type = $type; Value = $value; Sensitive = $sensitive; Description = $description }
            }

            $environment = [PSCustomObject]@{ Variables = $variables; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $false -Description 'db port'

            $environment.Variables.Added.Name | Should -Be 'Port'
            $environment.Variables.Added.Value | Should -Be 1433
            $environment.Variables.Added.Type | Should -Be ([System.TypeCode]::Int32)
            $environment.Variables.Added.Sensitive | Should -BeFalse
            $environment.AlterCalled | Should -BeTrue
        }
    }

    It 'Updates the existing variable value and alters the environment when the variable exists' {
        InModuleScope $script:moduleName {
            # Update branch: a hashtable supports .Contains(name) (IDictionary.Contains) and the [name]
            # indexer, returning the live variable object the wrapper mutates.
            $existing = [PSCustomObject]@{ Name = 'Port'; Value = 1; Sensitive = $false; Description = 'old' }
            $environment = [PSCustomObject]@{ Variables = @{ 'Port' = $existing }; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $true -Description 'db port'

            $existing.Value | Should -Be 1433
            $existing.Sensitive | Should -BeTrue
            $existing.Description | Should -Be 'db port'
            $environment.AlterCalled | Should -BeTrue
        }
    }
}
```

`tests/Unit/Private/Remove-SsisEnvironmentVariableObject.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentVariableObject' {
    It 'Removes the named variable and alters the environment' {
        InModuleScope $script:moduleName {
            $variables = [PSCustomObject]@{ Removed = $null }
            $variables | Add-Member -MemberType 'ScriptMethod' -Name 'Remove' -Value { param ($name) $this.Removed = $name }

            $environment = [PSCustomObject]@{ Variables = $variables; AlterCalled = $false }
            $environment | Add-Member -MemberType 'ScriptMethod' -Name 'Alter' -Value { $this.AlterCalled = $true }

            Remove-SsisEnvironmentVariableObject -Environment $environment -Name 'Port'

            $environment.Variables.Removed | Should -Be 'Port'
            $environment.AlterCalled | Should -BeTrue
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/New-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Set-SsisEnvironmentVariableObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentVariableObject.tests.ps1 -Output Detailed`
Expected: FAIL — commands not recognized.

- [ ] **Step 3: Write `source/Private/New-SsisEnvironmentObject.ps1`**

```powershell
function New-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Creates an environment in an SSISDB catalog folder and returns the new environment object.

        .DESCRIPTION
            Constructs a Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo under the
            given folder and calls Create() to persist it. Internal interop helper, not exported from
            the module.

        .EXAMPLE
            $environment = New-SsisEnvironmentObject -Folder $folder -Name 'Prod' -Description 'Production'

            Creates the Prod environment in the folder and returns it.

        .PARAMETER Folder
            The SSISDB CatalogFolder object under which to create the environment.

        .PARAMETER Name
            The name of the environment to create within the folder.

        .PARAMETER Description
            A description stored on the new environment. Pass an empty string when no description is wanted.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (New-SsisEnvironment) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process
    {
        $environment = [Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo]::new($Folder, $Name, $Description)
        $environment.Create()
        return $environment
    }
}
```

- [ ] **Step 4: Write `source/Private/Remove-SsisEnvironmentObject.ps1`**

```powershell
function Remove-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Drops an environment from an SSISDB catalog.

        .DESCRIPTION
            Calls Drop() on the supplied EnvironmentInfo object to remove it (and its variables) from the
            catalog on the server. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisEnvironmentObject -Environment $environment

            Drops the environment from the catalog.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object to drop, as returned by Get-SsisEnvironmentObject.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironment) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment
    )

    process
    {
        $Environment.Drop()
    }
}
```

- [ ] **Step 5: Write `source/Private/Set-SsisEnvironmentVariableObject.ps1`**

```powershell
function Set-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Adds or updates a variable on an SSISDB environment and persists the change.

        .DESCRIPTION
            When the named variable already exists on the environment its value, sensitivity, and
            description are updated; otherwise a new variable is added with the supplied type code. The
            change is persisted by calling Alter() on the environment. Internal interop helper, not
            exported from the module.

        .EXAMPLE
            Set-SsisEnvironmentVariableObject -Environment $environment -Name 'Port' -Value 1433 -TypeCode ([System.TypeCode]::Int32) -Sensitive $false -Description 'db port'

            Adds or updates the Port variable and alters the environment to persist it.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variable to add or update.

        .PARAMETER Name
            The name of the variable to add or update on the environment.

        .PARAMETER Value
            The value to store in the variable. Its meaning follows the variable's type code.

        .PARAMETER TypeCode
            The System.TypeCode the variable is created with when it does not already exist.

        .PARAMETER Sensitive
            Whether the variable value is stored encrypted (sensitive) on the server.

        .PARAMETER Description
            A description stored on the variable. Pass an empty string when no description is wanted.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisEnvironmentVariable) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.TypeCode]
        $TypeCode,

        [Parameter(Mandatory = $true)]
        [bool]
        $Sensitive,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process
    {
        if ($Environment.Variables.Contains($Name))
        {
            $variable = $Environment.Variables[$Name]
            $variable.Value = $Value
            $variable.Sensitive = $Sensitive
            $variable.Description = $Description
        }
        else
        {
            $Environment.Variables.Add($Name, $TypeCode, $Value, $Sensitive, $Description)
        }

        $Environment.Alter()
    }
}
```

- [ ] **Step 6: Write `source/Private/Remove-SsisEnvironmentVariableObject.ps1`**

```powershell
function Remove-SsisEnvironmentVariableObject
{
    <#
        .SYNOPSIS
            Removes a variable from an SSISDB environment and persists the change.

        .DESCRIPTION
            Removes the named variable from the environment's Variables collection and calls Alter() on
            the environment to persist the removal. Internal interop helper, not exported from the module.

        .EXAMPLE
            Remove-SsisEnvironmentVariableObject -Environment $environment -Name 'Port'

            Removes the Port variable from the environment and alters it to persist the change.

        .PARAMETER Environment
            The SSISDB EnvironmentInfo object whose variable to remove.

        .PARAMETER Name
            The name of the variable to remove from the environment.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Remove-SsisEnvironmentVariable) that calls this seam.')]
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Environment,

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    process
    {
        $Environment.Variables.Remove($Name)
        $Environment.Alter()
    }
}
```

- [ ] **Step 7: Run to verify they pass**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Private/New-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentObject.tests.ps1, ./tests/Unit/Private/Set-SsisEnvironmentVariableObject.tests.ps1, ./tests/Unit/Private/Remove-SsisEnvironmentVariableObject.tests.ps1 -Output Detailed`
Expected: PASS (1 + 1 + 2 + 1 tests).

> If Task 3 Step 6 showed `Variables.Remove` takes the variable object rather than a name, change `Remove-SsisEnvironmentVariableObject` to `$Environment.Variables.Remove($Environment.Variables[$Name])` and update its test's stand-in accordingly.

- [ ] **Step 8: Commit**

```powershell
git add -A
git commit -m "feat: add environment create/drop and variable set/remove interop wrappers"
```

---

## Task 5: Public — `Get-SsisEnvironment`

**Files:**
- Create: `source/Public/Get-SsisEnvironment.ps1`
- Test: `tests/Unit/Public/Get-SsisEnvironment.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisEnvironment.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'F1' }, [PSCustomObject]@{ Name = 'F2' }) }
        }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'E1' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns folder-scoped environments tagged Ssis.Environment' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Finance' }
        }

        It 'Enumerates every folder when -Folder is omitted' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance'
            ($result | Measure-Object).Count | Should -Be 2
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 2 -Scope It
        }

        It 'Returns a single environment when -Folder and -Name are given' {
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod'
            $result.Name | Should -Be 'Prod'
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
        }

        It 'Warns and returns nothing when the catalog does not exist' {
            Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironment -SqlInstance 'TestInstance' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists environments of a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | Get-SsisEnvironment
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisEnvironment` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisEnvironment.ps1`**

```powershell
function Get-SsisEnvironment
{
    <#
        .SYNOPSIS
            Gets environments from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns SSISDB environments as
            Ssis.Environment objects. Returns every environment across all folders by default, the
            environments of one folder when -Folder is given, or a single environment when -Name is also
            given. Accepts a piped Ssis.Folder object to list that folder's environments without
            reconnecting. Writes a warning and returns nothing when the catalog or named folder does not
            exist.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance'

            Returns the environments in the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' | Get-SsisEnvironment

            Returns every environment in every folder by piping folder objects in.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder whose environments to return. When omitted, environments from every
            folder in the catalog are returned.

        .PARAMETER InputObject
            A piped Ssis.Folder object whose environments to list. Used instead of -SqlInstance/-Folder
            to keep the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of a specific environment to return. When omitted, all environments in scope are
            returned.

        .OUTPUTS
            Ssis.Environment
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Environment')]
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
        $environmentParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $environmentParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environments = Get-SsisEnvironmentObject -Folder $InputObject @environmentParameters

            foreach ($environment in $environments)
            {
                if ($null -ne $environment)
                {
                    $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
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
            $environments = Get-SsisEnvironmentObject -Folder $catalogFolder @environmentParameters

            foreach ($environment in $environments)
            {
                if ($null -ne $environment)
                {
                    $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: PASS (5 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisEnvironment command.` under `## [Unreleased]` → `### Added` in `CHANGELOG.md`.
```powershell
git add -A
git commit -m "feat: add Get-SsisEnvironment command"
```

---

## Task 6: Public — `New-SsisEnvironment`

**Files:**
- Create: `source/Public/New-SsisEnvironment.ps1`
- Test: `tests/Unit/Public/New-SsisEnvironment.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/New-SsisEnvironment.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'New-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        Mock -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = $Name } }
    }

    It 'Creates the environment and returns an Ssis.Environment' {
        $result = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
    }

    It 'Errors and does not create when the environment already exists' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Errors and does not create when the folder does not exist' {
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { $null }
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Nope' -Name 'Prod' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not create' {
        $null = New-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -WhatIf
        Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Creates in a piped folder without connecting' {
            $folder = [PSCustomObject]@{ Name = 'Finance' }
            $folder.PSObject.TypeNames.Insert(0, 'Ssis.Folder')

            $result = $folder | New-SsisEnvironment -Name 'Prod' -Confirm:$false
            $result.PSObject.TypeNames | Should -Contain 'Ssis.Environment'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName New-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Folder.Name -eq 'Finance' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/New-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: FAIL — `New-SsisEnvironment` not recognized.

- [ ] **Step 3: Write `source/Public/New-SsisEnvironment.ps1`**

```powershell
function New-SsisEnvironment
{
    <#
        .SYNOPSIS
            Creates an environment in a folder of the SSISDB catalog.

        .DESCRIPTION
            Connects to the specified SQL Server instance and creates an environment in the target
            folder. Accepts a piped Ssis.Folder object as the target. Writes an error and makes no change
            when an environment with the same name already exists, or when the catalog or folder does not
            exist. Returns the new environment as an Ssis.Environment object.

        .EXAMPLE
            New-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' -Description 'Production'

            Creates the Prod environment in the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisFolder -SqlInstance 'SQL01\PROD' -Name 'Finance' | New-SsisEnvironment -Name 'Prod'

            Creates the Prod environment in the piped Finance folder.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the existing folder to create the environment in.

        .PARAMETER InputObject
            A piped Ssis.Folder object to create the environment in, instead of -SqlInstance/-Folder,
            keeping the existing connection from a Get-SsisFolder pipeline.

        .PARAMETER Name
            The name of the environment to create within the folder.

        .PARAMETER Description
            An optional description stored on the environment. Defaults to an empty string when omitted.

        .OUTPUTS
            Ssis.Environment
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.Environment')]
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
        $Name,

        [Parameter()]
        [string]
        $Description = ''
    )

    process
    {
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

        if ($null -ne (Get-SsisEnvironmentObject -Folder $targetFolder -Name $Name))
        {
            Write-Error -Message ('An environment named ''{0}'' already exists in the folder.' -f $Name)
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create SSIS environment'))
        {
            $environment = New-SsisEnvironmentObject -Folder $targetFolder -Name $Name -Description $Description
            $environment | Add-SsisTypeName -TypeName 'Ssis.Environment'
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/New-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: PASS (5 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- New-SsisEnvironment command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add New-SsisEnvironment command"
```

---

## Task 7: Public — `Remove-SsisEnvironment`

**Files:**
- Create: `source/Public/Remove-SsisEnvironment.ps1`
- Test: `tests/Unit/Public/Remove-SsisEnvironment.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Remove-SsisEnvironment.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironment' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { }
    }

    It 'Removes the environment' {
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -Confirm:$false
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It
    }

    It 'Errors and does not remove when the environment does not exist' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable err
        $err | Should -Not -BeNullOrEmpty
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not remove' {
        Remove-SsisEnvironment -SqlInstance 'TestInstance' -Folder 'Finance' -Name 'Prod' -WhatIf
        Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Removes a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $environment | Remove-SsisEnvironment -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: FAIL — `Remove-SsisEnvironment` not recognized.

- [ ] **Step 3: Write `source/Public/Remove-SsisEnvironment.ps1`**

```powershell
function Remove-SsisEnvironment
{
    <#
        .SYNOPSIS
            Removes an environment from the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and drops an environment (and its variables)
            from a folder in the SSISDB catalog. Accepts a piped Ssis.Environment object. Writes an error
            when the catalog, folder, or named environment does not exist. This is a destructive
            operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod'

            Removes the Prod environment from the Finance folder on the named instance.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Remove-SsisEnvironment

            Removes the piped Prod environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment to remove.

        .PARAMETER InputObject
            A piped Ssis.Environment object to remove, instead of -SqlInstance/-Folder/-Name, keeping
            the existing connection from a Get-SsisEnvironment pipeline.

        .PARAMETER Name
            The name of the environment to remove from the folder.

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

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environment = $InputObject
            $environmentName = $environment.Name
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

            $environment = Get-SsisEnvironmentObject -Folder $folderObject -Name $Name

            if ($null -eq $environment)
            {
                Write-Error -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Name, $Folder)
                return
            }

            $environmentName = $Name
        }

        if ($PSCmdlet.ShouldProcess($environmentName, 'Remove SSIS environment'))
        {
            Remove-SsisEnvironmentObject -Environment $environment
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironment.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Remove-SsisEnvironment command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Remove-SsisEnvironment command"
```

---

## Task 8: Public — `Get-SsisEnvironmentVariable`

**Files:**
- Create: `source/Public/Get-SsisEnvironmentVariable.ps1`
- Test: `tests/Unit/Public/Get-SsisEnvironmentVariable.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Get-SsisEnvironmentVariable.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { @([PSCustomObject]@{ Name = 'ConnString' }) }
        }
    }

    Context 'ByInstance' {
        It 'Returns variables tagged Ssis.EnvironmentVariable for a folder and environment' {
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod'
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
            Should -Invoke -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Prod' }
        }

        It 'Returns a single variable when -Name is given' {
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'ConnString'
            $result.Name | Should -Be 'ConnString'
        }

        It 'Warns and returns nothing when the environment does not exist' {
            Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
            $result = Get-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Nope' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'ByObject' {
        It 'Lists variables of a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $result = $environment | Get-SsisEnvironmentVariable
            $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-SsisEnvironmentVariable` not recognized.

- [ ] **Step 3: Write `source/Public/Get-SsisEnvironmentVariable.ps1`**

```powershell
function Get-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Gets variables from an environment in the SSISDB catalog on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and returns the variables of an SSISDB
            environment as Ssis.EnvironmentVariable objects, or a single variable when -Name is given.
            Accepts a piped Ssis.Environment object to list its variables without reconnecting. Writes a
            warning and returns nothing when the catalog, folder, or named environment does not exist.
            Sensitive variable values are returned masked by the server.

        .EXAMPLE
            Get-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod'

            Returns the variables of the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Get-SsisEnvironmentVariable

            Returns the variables of the piped Prod environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment whose variables to return.

        .PARAMETER Environment
            The name of the environment whose variables to return.

        .PARAMETER InputObject
            A piped Ssis.Environment object whose variables to list. Used instead of
            -SqlInstance/-Folder/-Environment to keep the existing connection from a Get-SsisEnvironment
            pipeline.

        .PARAMETER Name
            The name of a specific variable to return. When omitted, all variables in the environment are
            returned.

        .OUTPUTS
            Ssis.EnvironmentVariable
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentVariable')]
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
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        $variableParameters = @{}

        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $variableParameters['Name'] = $Name
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject
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

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Warning -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }
        }

        $variables = Get-SsisEnvironmentVariableObject -Environment $environmentObject @variableParameters

        foreach ($variable in $variables)
        {
            if ($null -ne $variable)
            {
                $variable | Add-SsisTypeName -TypeName 'Ssis.EnvironmentVariable'
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Get-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Get-SsisEnvironmentVariable command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Get-SsisEnvironmentVariable command"
```

---

## Task 9: Public — `Set-SsisEnvironmentVariable`

**Files:**
- Create: `source/Public/Set-SsisEnvironmentVariable.ps1`
- Test: `tests/Unit/Public/Set-SsisEnvironmentVariable.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Set-SsisEnvironmentVariable.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Set-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith {
            if ($PSBoundParameters.ContainsKey('Name')) { [PSCustomObject]@{ Name = $Name } }
            else { [PSCustomObject]@{ Name = 'Prod' } }
        }
        Mock -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Port'; Value = 1433 } }
    }

    It 'Infers the type code from the value and returns an Ssis.EnvironmentVariable' {
        $result = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1433 -Confirm:$false
        $result.PSObject.TypeNames | Should -Contain 'Ssis.EnvironmentVariable'
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
            $Name -eq 'Port' -and $Value -eq 1433 -and $TypeCode -eq [System.TypeCode]::Int32 -and $Sensitive -eq $false
        }
    }

    It 'Honors an explicit -DataType override' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value '1433' -DataType 'Int32' -Confirm:$false
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $TypeCode -eq [System.TypeCode]::Int32 }
    }

    It 'Passes -Sensitive through to the interop wrapper' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Password' -Value 'secret' -Sensitive -Confirm:$false
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Sensitive -eq $true }
    }

    It 'Warns and does not set when the environment does not exist' {
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { $null }
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Nope' -Name 'Port' -Value 1 -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    It 'Supports -WhatIf and does not set' {
        $null = Set-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1 -WhatIf
        Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
    }

    Context 'ByObject' {
        It 'Sets on a piped environment without connecting' {
            $environment = [PSCustomObject]@{ Name = 'Prod' }
            $environment.PSObject.TypeNames.Insert(0, 'Ssis.Environment')

            $null = $environment | Set-SsisEnvironmentVariable -Name 'Port' -Value 1433 -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Set-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Environment.Name -eq 'Prod' }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Set-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: FAIL — `Set-SsisEnvironmentVariable` not recognized.

- [ ] **Step 3: Write `source/Public/Set-SsisEnvironmentVariable.ps1`**

```powershell
function Set-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Adds or updates a variable on an SSISDB environment.

        .DESCRIPTION
            Connects to the specified SQL Server instance and adds or updates a variable on an SSISDB
            environment (upsert: updates the value when the variable exists, otherwise creates it). The
            variable's data type is inferred from the supplied value's .NET type and can be overridden by
            -DataType. -Sensitive stores the value encrypted on the server. Accepts a piped
            Ssis.Environment object as the target. Writes a warning and makes no change when the catalog,
            folder, or environment does not exist. Returns the resulting Ssis.EnvironmentVariable.

        .EXAMPLE
            Set-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Value 1433

            Adds or updates the Int32 Port variable on the Prod environment.

        .EXAMPLE
            Get-SsisEnvironment -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Name 'Prod' | Set-SsisEnvironmentVariable -Name 'Password' -Value 'secret' -Sensitive

            Adds or updates a sensitive Password variable on the piped Prod environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the target environment.

        .PARAMETER Environment
            The name of the environment to add or update the variable on.

        .PARAMETER InputObject
            A piped Ssis.Environment object to set the variable on, instead of
            -SqlInstance/-Folder/-Environment, keeping the existing connection from a Get-SsisEnvironment
            pipeline.

        .PARAMETER Name
            The name of the variable to add or update on the environment.

        .PARAMETER Value
            The value to store in the variable. Its data type is inferred from this value unless
            -DataType is given.

        .PARAMETER DataType
            An explicit SSIS data type name (Boolean, Byte, Int16, Int32, Int64, Single, Double, Decimal,
            DateTime, String) that overrides the type inferred from -Value.

        .PARAMETER Sensitive
            Stores the variable value encrypted (sensitive) on the server. Sensitive values are returned
            masked when read back.

        .PARAMETER Description
            An optional description stored on the variable. Defaults to an empty string when omitted.

        .OUTPUTS
            Ssis.EnvironmentVariable
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByInstance')]
    [OutputType('Ssis.EnvironmentVariable')]
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
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter()]
        [AllowNull()]
        [object]
        $Value,

        [Parameter()]
        [ValidateSet('Boolean', 'Byte', 'Int16', 'Int32', 'Int64', 'Single', 'Double', 'Decimal', 'DateTime', 'String')]
        [string]
        $DataType,

        [Parameter()]
        [switch]
        $Sensitive,

        [Parameter()]
        [string]
        $Description = ''
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject
            $environmentName = $environmentObject.Name
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

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Warning -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }

            $environmentName = $Environment
        }

        $typeCodeParameters = @{ Value = $Value }

        if ($PSBoundParameters.ContainsKey('DataType'))
        {
            $typeCodeParameters['DataType'] = $DataType
        }

        $typeCode = ConvertTo-SsisTypeCode @typeCodeParameters

        if ($PSCmdlet.ShouldProcess(('{0} on {1}' -f $Name, $environmentName), 'Set SSIS environment variable'))
        {
            $splatSetVariable = @{
                Environment = $environmentObject
                Name        = $Name
                Value       = $Value
                TypeCode    = $typeCode
                Sensitive   = [bool]$Sensitive
                Description = $Description
            }

            Set-SsisEnvironmentVariableObject @splatSetVariable

            $variable = Get-SsisEnvironmentVariableObject -Environment $environmentObject -Name $Name
            $variable | Add-SsisTypeName -TypeName 'Ssis.EnvironmentVariable'
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Set-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: PASS (6 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Set-SsisEnvironmentVariable command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Set-SsisEnvironmentVariable command"
```

---

## Task 10: Public — `Remove-SsisEnvironmentVariable`

**Files:**
- Create: `source/Public/Remove-SsisEnvironmentVariable.ps1`
- Test: `tests/Unit/Public/Remove-SsisEnvironmentVariable.tests.ps1`

- [ ] **Step 1: Write the failing unit test**

`tests/Unit/Public/Remove-SsisEnvironmentVariable.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Remove-SsisEnvironmentVariable' {
    BeforeAll {
        Mock -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Marker = 'connected' } }
        Mock -CommandName Get-SsisCatalogObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'SSISDB' } }
        Mock -CommandName Get-SsisFolderObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Finance' } }
        Mock -CommandName Get-SsisEnvironmentObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Prod' } }
        Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { [PSCustomObject]@{ Name = 'Port' } }
        Mock -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { }
    }

    Context 'ByInstance' {
        It 'Removes the variable' {
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -Confirm:$false
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter { $Name -eq 'Port' }
        }

        It 'Warns and does not remove when the variable does not exist' {
            Mock -CommandName Get-SsisEnvironmentVariableObject -ModuleName $script:moduleName -MockWith { $null }
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Missing' -Confirm:$false -WarningAction SilentlyContinue
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }

        It 'Supports -WhatIf and does not remove' {
            Remove-SsisEnvironmentVariable -SqlInstance 'TestInstance' -Folder 'Finance' -Environment 'Prod' -Name 'Port' -WhatIf
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
        }
    }

    Context 'ByObject' {
        It 'Removes a piped variable via its parent environment without connecting' {
            $variable = [PSCustomObject]@{ Name = 'Port'; Parent = [PSCustomObject]@{ Name = 'Prod' } }
            $variable.PSObject.TypeNames.Insert(0, 'Ssis.EnvironmentVariable')

            $variable | Remove-SsisEnvironmentVariable -Confirm:$false
            Should -Invoke -CommandName Connect-SsisCatalog -ModuleName $script:moduleName -Exactly -Times 0 -Scope It
            Should -Invoke -CommandName Remove-SsisEnvironmentVariableObject -ModuleName $script:moduleName -Times 1 -Scope It -ParameterFilter {
                $Name -eq 'Port' -and $Environment.Name -eq 'Prod'
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: FAIL — `Remove-SsisEnvironmentVariable` not recognized.

- [ ] **Step 3: Write `source/Public/Remove-SsisEnvironmentVariable.ps1`**

```powershell
function Remove-SsisEnvironmentVariable
{
    <#
        .SYNOPSIS
            Removes a variable from an SSISDB environment on a SQL Server instance.

        .DESCRIPTION
            Connects to the specified SQL Server instance and removes a variable from an SSISDB
            environment. Accepts a piped Ssis.EnvironmentVariable object, reaching its environment via
            its Parent. Writes a warning when the catalog, folder, environment, or named variable does
            not exist. This is a destructive operation and prompts for confirmation by default.

        .EXAMPLE
            Remove-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port'

            Removes the Port variable from the Prod environment in the Finance folder.

        .EXAMPLE
            Get-SsisEnvironmentVariable -SqlInstance 'SQL01\PROD' -Folder 'Finance' -Environment 'Prod' -Name 'Port' | Remove-SsisEnvironmentVariable

            Removes the piped Port variable via its parent environment.

        .PARAMETER SqlInstance
            The SQL Server instance hosting SSISDB (for example 'SQL01\PROD'), or an SMO Server or
            IntegrationServices object to reuse an existing connection.

        .PARAMETER SqlCredential
            A PSCredential for SQL Server authentication. When omitted, the current Windows identity
            is used (integrated authentication).

        .PARAMETER Folder
            The name of the folder containing the environment whose variable to remove.

        .PARAMETER Environment
            The name of the environment whose variable to remove.

        .PARAMETER InputObject
            A piped Ssis.EnvironmentVariable object to remove, instead of
            -SqlInstance/-Folder/-Environment/-Name, keeping the existing connection from a
            Get-SsisEnvironmentVariable pipeline.

        .PARAMETER Name
            The name of the variable to remove from the environment.

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
        $Environment,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject', ValueFromPipeline = $true)]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInstance')]
        [string]
        $Name
    )

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ByObject')
        {
            $environmentObject = $InputObject.Parent
            $variableName = $InputObject.Name
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

            $environmentObject = Get-SsisEnvironmentObject -Folder $folderObject -Name $Environment

            if ($null -eq $environmentObject)
            {
                Write-Warning -Message ('Environment ''{0}'' was not found in folder ''{1}''.' -f $Environment, $Folder)
                return
            }

            $variable = Get-SsisEnvironmentVariableObject -Environment $environmentObject -Name $Name

            if ($null -eq $variable)
            {
                Write-Warning -Message ('Variable ''{0}'' was not found in environment ''{1}''.' -f $Name, $Environment)
                return
            }

            $variableName = $Name
        }

        if ($PSCmdlet.ShouldProcess($variableName, 'Remove SSIS environment variable'))
        {
            Remove-SsisEnvironmentVariableObject -Environment $environmentObject -Name $variableName
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `./build.ps1 -Tasks build; Invoke-Pester -Path ./tests/Unit/Public/Remove-SsisEnvironmentVariable.tests.ps1 -Output Detailed`
Expected: PASS (4 tests).

- [ ] **Step 5: Update CHANGELOG and commit**

Add `- Remove-SsisEnvironmentVariable command.` under `### Added`.
```powershell
git add -A
git commit -m "feat: add Remove-SsisEnvironmentVariable command"
```

---

## Task 11: Integration test — environment lifecycle

**Files:**
- Create: `tests/Integration/Ssis.Environment.Integration.tests.ps1`

- [ ] **Step 1: Write the integration test**

`tests/Integration/Ssis.Environment.Integration.tests.ps1`:
```powershell
BeforeAll {
    $script:moduleName = 'IntegrationServicesTools'
    Import-Module -Name $script:moduleName -Force -ErrorAction Stop

    $script:instance = $env:SSIS_TEST_INSTANCE
    $script:skip = [string]::IsNullOrWhiteSpace($script:instance)

    $script:folderName = 'ISTools_EnvTest'
    $script:environmentName = 'IntegrationEnv'
}

AfterAll {
    if (-not $script:skip)
    {
        # Best-effort cleanup; ignore errors if a prior step failed before creating an object.
        Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false -ErrorAction SilentlyContinue
    }

    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Environment lifecycle' -Tag 'Integration' {
    It 'Creates, populates, reads, updates, and removes an environment end to end' -Skip:$script:skip {
        # Arrange: a clean folder to hold the environment.
        if ($null -ne (Get-SsisFolder -SqlInstance $script:instance -Name $script:folderName))
        {
            Remove-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false
        }
        New-SsisFolder -SqlInstance $script:instance -Name $script:folderName -Confirm:$false | Out-Null

        # Create the environment.
        $environment = New-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Description 'integration' -Confirm:$false
        $environment.PSObject.TypeNames | Should -Contain 'Ssis.Environment'

        # Add a typed variable (Int32 inferred) and a sensitive variable.
        $port = Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1433 -Confirm:$false
        $port.Type | Should -Be ([System.TypeCode]::Int32)
        $port.Value | Should -Be 1433

        Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Password' -Value 'p@ss' -Sensitive -Confirm:$false | Out-Null

        # Read them back.
        $variables = Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName
        ($variables | Measure-Object).Count | Should -Be 2
        ($variables | Where-Object -FilterScript { $_.Name -eq 'Password' }).Sensitive | Should -BeTrue

        # Update the Port value (upsert path).
        $updated = Set-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' -Value 1450 -Confirm:$false
        $updated.Value | Should -Be 1450

        # Remove a variable.
        Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName -Name 'Port' |
            Remove-SsisEnvironmentVariable -Confirm:$false
        $remaining = Get-SsisEnvironmentVariable -SqlInstance $script:instance -Folder $script:folderName -Environment $script:environmentName
        ($remaining | Measure-Object).Count | Should -Be 1

        # Remove the environment.
        Remove-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -Confirm:$false
        Get-SsisEnvironment -SqlInstance $script:instance -Folder $script:folderName -Name $script:environmentName -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Verify it skips cleanly without an instance**

Run (with `$env:SSIS_TEST_INSTANCE` unset):
```powershell
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Invoke-Pester -Path ./tests/Integration/Ssis.Environment.Integration.tests.ps1 -Output Detailed
```
Expected: the test is **skipped** (not failed). With a real `$env:SSIS_TEST_INSTANCE` set, it runs the full lifecycle and passes.

- [ ] **Step 3: Commit**

```powershell
git add -A
git commit -m "test: add environment lifecycle integration test"
```

---

## Task 12: Full QA gate and finalize

**Files:** none (verification only)

- [ ] **Step 1: Run the full build + test (QA + unit)**

Run: `./build.ps1 -Tasks build,test`
Expected: QA tests (help quality, PSScriptAnalyzer, manifest) pass for all new public and private functions; all new unit tests pass; integration tests skip cleanly (no `$env:SSIS_TEST_INSTANCE`). The only expected shortfall is the **code-coverage gate** (85%), which is met only when Integration tests run against a real SSISDB — the interop wrappers are integration-only, per the spec. Confirm there are no PSScriptAnalyzer or help failures.

- [ ] **Step 2: Verify the six commands are exported**

```powershell
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module IntegrationServicesTools -Force -ErrorAction Stop
'Get-SsisEnvironment', 'New-SsisEnvironment', 'Remove-SsisEnvironment', 'Get-SsisEnvironmentVariable', 'Set-SsisEnvironmentVariable', 'Remove-SsisEnvironmentVariable' |
    ForEach-Object -Process { Get-Command -Module IntegrationServicesTools -Name $_ -ErrorAction Stop }
```
Expected: all six commands resolve (no error).

- [ ] **Step 3: Final commit if anything changed**

```powershell
git add -A
git commit -m "chore: finalize Phase 3a environments & variables" --allow-empty
```

---

## Self-review checklist (for the implementer before opening the PR)

- [ ] No backticks anywhere; splats used for 3+ params (e.g. `$splatSetVariable`), hashtables aligned.
- [ ] Allman braces, single quotes for non-interpolated strings, `Mandatory = $true`, 4-space indent, no trailing whitespace.
- [ ] PS5.1-compatible (Desktop); `::new()` used for `EnvironmentInfo`.
- [ ] Every new function (public + private) has its own `<Name>.tests.ps1`, full comment-based help; public functions have `.OUTPUTS`.
- [ ] State-changers (`New`/`Set`/`Remove`) declare `SupportsShouldProcess`; `Remove-*` is `ConfirmImpact High`; interop wrappers carry the `SuppressMessage` justification.
- [ ] Returns `Ssis.Environment` / `Ssis.EnvironmentVariable`-decorated objects; pipeline output emitted immediately.
- [ ] Each interop call behind a `*-Ssis*Object` wrapper; the one pure helper is `ConvertTo-SsisTypeCode`; unit tests mock the seam and pass.
- [ ] `./build.ps1 -Tasks test` green for QA + unit; integration test skips cleanly without `$env:SSIS_TEST_INSTANCE`.
- [ ] Commit messages use Conventional Commits.
