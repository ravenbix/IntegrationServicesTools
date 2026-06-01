# IntegrationServicesTools — Style Guide for Claude Code

Coding standards for this module. Adapted from the dbatools CLAUDE.md, reconciled with this
project's locked decisions (see `docs/superpowers/specs/2026-05-31-ssis-tools-module-design.md`)
and the Sampler/DSC-Community scaffold it is built on. Where this project and dbatools differ, the
rules below win — do not "port" dbatools habits that contradict them.

## What this module is

A Windows PowerShell module wrapping the `Microsoft.SqlServer.Management.IntegrationServices`
managed object model (MOM) for administering the SSISDB catalog (SQL Server 2012+, Project
Deployment Model). Built on the **Sampler** scaffold (ModuleBuilder, Pester v5, PSScriptAnalyzer,
Public/Private layout).

## Runtime target (READ FIRST — differs from dbatools)

- **Windows PowerShell 5.1, `Desktop` edition only.** Not PowerShell 7, not PSv3.
- **PS5.1+ syntax is encouraged**, including `[Type]::new()` and other static/`::` calls. dbatools
  bans `::new()` for PSv3 support; this project does NOT — the codebase relies on it. Do not
  "downgrade" to `New-Object`.
- No cross-platform, Azure-AD/Entra interactive auth, or legacy MSDB/`dtutil` package model (YAGNI).

## Command syntax rules

### No backticks — use splats
Never use backticks (`` ` ``) for line continuation.
- **1–2 parameters:** direct syntax.
- **3+ parameters:** splatted hashtable named `$splat<Purpose>` (never a bare `$splat`).

```powershell
# 2 params — direct
$catalog = Get-SsisCatalog -SqlInstance $instance

# 4 params — splat
$splatFolder = @{
    SqlInstance = $instance
    Name        = $folderName
    Description = $description
    Confirm     = $false
}
New-SsisFolder @splatFolder
```

### Aligned hashtables (mandatory)
All hashtable `=` signs align vertically, as above.

### Pipeline output — emit immediately
Output each object to the pipeline as it is produced. Never accumulate in an array/ArrayList and
return at the end. For this module that means: decorate each MOM object with `Add-SsisTypeName` and
emit it.

### No output-mode switches
No `-Detailed` / `-Simple` parameters.

## Formatting (this project's style — differs from dbatools)

- **Allman braces** — opening brace on its own line (dbatools uses OTBS; we do not).
- **Single quotes** for non-interpolated strings; double quotes only when interpolating
  (`"...$($x)..."`). (dbatools standardizes on double quotes; we do not.)
- **`[Parameter(Mandatory = $true)]`** — explicit form (dbatools drops `= $true`; we keep it).
- 4-space indentation, no trailing whitespace, UTF-8.
- One blank line between parameter declarations in a `param` block (match existing files).

```powershell
function Get-SsisFolder
{
    [CmdletBinding()]
    [OutputType('Ssis.Folder')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $SqlInstance,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        # ...
    }
}
```

## Comment preservation
Preserve every comment exactly as written, including development/TODO notes and metadata. Never
silently delete comments while editing.

## Module conventions

### Naming
- Singular nouns, approved verbs only.
- Pattern: `<Verb>-Ssis<Noun>` (e.g. `Get-SsisFolder`, `New-SsisCatalog`, `Publish-SsisProject`).
- `Publish-`/`Export-` for `.ispac` deploy/retrieve; `Start-`/`Stop-`/`Wait-` for execution lifecycle.
- A `-Pattern` parameter (if added) uses **regex**, not SQL `LIKE` or PowerShell wildcards.

### No manual export registration (differs from dbatools)
Sampler/ModuleBuilder builds the manifest from `source/Public` and `source/Private`. Do **not**
hand-edit `FunctionsToExport` or add `Export-ModuleMember` calls — add the function file in the
right folder and the build wires it up.

### Connection & parameter sets
Every public command exposes two parameter sets:
- **ByInstance:** `-SqlInstance` (+ optional `-SqlCredential`) — resolved via private
  `Connect-SsisCatalog`. Windows integrated auth by default.
- **ByObject:** a piped `Ssis.*` object carrying its own connection, for fluent pipelines.

### ShouldProcess
All state-changing commands (`New`/`Set`/`Remove`/`Publish`/`Export`/`Start`/`Stop`) declare
`SupportsShouldProcess` and gate the mutating call behind `$PSCmdlet.ShouldProcess(...)`.
`Remove-*` sets `ConfirmImpact = 'High'`.

### Interop seam (testability)
Each distinct .NET/MOM call lives behind a thin private wrapper named `*-Ssis*Object`
(e.g. `Get-SsisCatalogObject`, `New-SsisFolderObject`). Public-function logic (param resolution,
validation, object shaping, `ShouldProcess`) is unit-tested by mocking this seam — no live SQL.
Note: these wrappers construct `IntegrationServices`, which eagerly opens a SQL connection, so they
themselves are integration-only (not unit-testable) — see the coverage note under Testing.

### Output objects
Return native MOM objects decorated with a `PSTypeName` (`Ssis.Catalog`, `Ssis.Folder`,
`Ssis.Project`, …) via `Add-SsisTypeName`. `source/IntegrationServicesTools.format.ps1xml`
(shipped via `FormatsToProcess`) defines the default views. Native members stay accessible.

### Error handling (differs from dbatools — no -EnableException)
Wrap interop calls in try/catch. Surface recoverable failures with `Write-Error`; `throw` only for
connection failures that make the command unrunnable. There is **no** `-EnableException` subsystem.

### Object model over T-SQL
Use the IntegrationServices MOM for object manipulation and property access. Reach for T-SQL only
where the MOM has no equivalent.

### Help
Comment-based help (`.SYNOPSIS` / `.DESCRIPTION` / `.PARAMETER` / `.EXAMPLE` / `.OUTPUTS`) on every
**public and private** function. Sampler's QA tests enumerate private functions too, so private
helpers need full help — not just public commands (see Testing).

### Assemblies & the resolver
The MOM is not on NuGet; it is loaded at import from the `dbatools.library` module's `desktop/lib`
(see `source/prefix.ps1`). Never commit binaries; never add a NuGet restore step.

The `AssemblyResolve` handler **must be compiled** (an `Add-Type`/C# type registered once per
process), **not a PowerShell scriptblock**. A scriptblock handler recurses — invoking it drags in
PowerShell machinery that itself triggers assembly resolution — and **StackOverflows when
PSScriptAnalyzer runs with the module imported**. Do not revert it to a scriptblock.

## Testing

- **TDD.** Follow the superpowers `test-driven-development` skill (RED → GREEN → REFACTOR) before
  writing implementation. Pester v5.
- **Sampler QA runs against public AND private functions.** Every function (public or private) needs
  its own `<Name>.tests.ps1`, must pass PSScriptAnalyzer, and needs full comment-based help.
- **Unit** (`tests/Unit/...`): mock the interop seam; assert param resolution, connection-string
  construction, `ShouldProcess` gating, param-set binding, object decoration. No SQL Server.
- **Integration** (`tests/Integration/...`, tag `Integration`, opt-in): run against a real SQL
  Server with SSISDB; gate on `$env:SSIS_TEST_INSTANCE` and skip cleanly when unset. LocalDB cannot
  host SSISDB.
- **Binary test data exception.** `tests/Integration/fixtures/*.ispac` are committed `.ispac` build
  artifacts used to exercise project deploy/export. They are sanctioned **test data** — the
  "never commit binaries" rule targets the MOM/assemblies, not test fixtures. The project
  integration test self-skips when the fixture is absent.
- **QA** (`tests/QA`): help quality, PSScriptAnalyzer, manifest correctness must pass.
  `PSUseOutputTypeCorrectly` is intentionally excluded in `tests/QA/module.tests.ps1` — it only
  activates once the SSIS assemblies are loaded and misfires on functions returning native MOM types.
- **Code coverage threshold is 85%** (`build.yaml`, the scaffold default) and is met ONLY when the
  run includes the Integration tests against a real SSISDB (`$env:SSIS_TEST_INSTANCE`). The interop
  wrappers open a real SQL connection on construction, so they are integration-only; and because
  ModuleBuilder merges every function into a single `.psm1`, the file-based `ExcludeFromCodeCoverage`
  setting cannot exclude individual functions. Unit-only runs therefore fall under the bar — keep
  genuinely testable logic well covered and exercise the interop seam from Integration tests.
- **Single-file test runs** need BOTH `output/module` AND `output/RequiredModules` on
  `$env:PSModulePath` (importing the module pulls in `dbatools.library`).
- When parameters change, update the parameter-validation tests. Add 1–3 focused tests per new
  behavior.

## Build & workflow

- Build: `./build.ps1 -Tasks build`. Test: `./build.ps1 -Tasks test`. Requires `dbatools.library`
  installed (`Install-Module dbatools.library`).
- **Conventional Commits** for every commit message (e.g. `feat:`, `fix:`, `docs:`). Do NOT use
  dbatools' `(do ...)` CI pattern.
- Use the superpowers skills: brainstorming before new features, systematic-debugging for bugs,
  verification-before-completion before claiming done.

## Golden rules

1. **Never use backticks** — splat for 3+ params (`$splat<Purpose>`, aligned).
2. **PS5.1 Desktop only** — `::new()` is fine; never downgrade for PSv3.
3. **Emit pipeline output immediately** — decorate with `Add-SsisTypeName`, don't collect.
4. **Keep project formatting** — Allman braces, single quotes, `Mandatory = $true`.
5. **Preserve every comment** exactly.
6. **Add files, don't register** — Sampler builds the manifest from Public/Private.
7. **Two param sets** — ByInstance and ByObject; resolve via `Connect-SsisCatalog`.
8. **ShouldProcess** on all state-changers; `ConfirmImpact High` on `Remove-*`.
9. **Mock the `*-Ssis*Object` seam** in unit tests; no live SQL. Resolver stays compiled, not a scriptblock.
10. **Conventional Commits**, comment-based help with `.OUTPUTS`, MOM over T-SQL.

## Verification checklist (before claiming done)

- [ ] No backticks; splats for 3+ params, aligned hashtables.
- [ ] Allman braces, single quotes, `Mandatory = $true`, 4-space indent, no trailing whitespace.
- [ ] PS5.1-compatible (Desktop); `::new()` allowed.
- [ ] New function (public or private) has its own `<Name>.tests.ps1` and full comment-based help
      incl. `.OUTPUTS`; public functions placed in `source/Public` (not manually registered).
- [ ] State-changers declare `SupportsShouldProcess`; `Remove-*` is `ConfirmImpact High`.
- [ ] Returns `Ssis.*`-decorated objects; pipeline output emitted immediately.
- [ ] Interop behind a `*-Ssis*Object` wrapper; unit tests mock the seam and pass.
- [ ] `./build.ps1 -Tasks test` green (QA + unit); integration tests skip cleanly without
      `$env:SSIS_TEST_INSTANCE`.
- [ ] Commit message uses Conventional Commits.
```
