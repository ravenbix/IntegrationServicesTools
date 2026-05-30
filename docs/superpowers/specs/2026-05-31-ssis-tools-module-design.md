# IntegrationServicesTools — Design Spec

**Date:** 2026-05-31
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`

## 1. Summary

A Windows PowerShell module that wraps the `Microsoft.SqlServer.Management.IntegrationServices`
.NET object model (the managed API for the SSISDB catalog / SSIS Project Deployment Model on
SQL Server 2012+). It provides discoverable, pipeline-friendly cmdlets for administering the
catalog, managing folders, deploying projects/packages, managing environments and parameters,
and starting/monitoring executions.

The module is built on the existing **Sampler** scaffold already present in the repo
(ModuleBuilder, Pester, PSScriptAnalyzer, Public/Private layout).

## 2. Goals & non-goals

**Goals**
- Cover all five functional areas of the SSISDB catalog: catalog admin, folders,
  projects/packages, environments/parameters, executions/monitoring.
- dbatools-style ergonomics: `-SqlInstance` / `-SqlCredential`, rich objects, pipeline support.
- Self-contained at runtime: bundle the required assemblies so users don't have to install
  SSMS/DACFx separately.

**Non-goals (YAGNI for v1)**
- The legacy package-deployment model (MSDB / file system / `dtutil`). This namespace is for the
  Project Deployment Model (SSISDB) only.
- Cross-platform / PowerShell 7 support.
- Azure-AD / Entra interactive auth flows.
- A dbatools-style `-EnableException` message subsystem.
- Designing/editing package contents (control flow, data flow). This module manages the
  *catalog*, not package internals.

## 3. Locked decisions

| Decision | Choice |
|----------|--------|
| Scope | All five functional areas (phased delivery) |
| Assembly source | Depend on the `dbatools.library` PowerShell module (RequiredModule) and load the MOM from its `desktop/lib/` at import. The MOM (`Microsoft.SqlServer.Management.IntegrationServices.dll`) is **not** distributed via NuGet or the `SqlServer` module — `dbatools.library` is the only redistributable source. |
| Runtime | Windows PowerShell 5.1 / .NET Framework, `Desktop` edition only |
| Connection | `-SqlInstance` (string *or* SMO `Server`/`SqlConnection` object) + `-SqlCredential` (PSCredential); Windows integrated auth by default |
| Noun prefix | `Ssis` (known collisions with Gallery modules `MSBITools` / `SqlBIManager` accepted; module-qualified names are the fallback) |
| Return shape | Native MOM objects decorated with a custom `PSTypeName` + `format.ps1xml` views |

## 4. Architecture

### 4.1 Layers

```
Public functions (Verb-Ssis*)          <- user-facing cmdlets, param sets, ShouldProcess, help
        |
Private helpers
  - Connect-SsisCatalog                 <- resolves -SqlInstance/-SqlCredential -> SqlConnection
  - Get-SsisInteropCatalog              <- builds IntegrationServices/Catalog from a connection
  - thin interop wrappers               <- one tiny function per .NET call we make (testable seam)
        |
MOM assemblies                          <- Microsoft.SqlServer.Management.IntegrationServices.dll + deps,
                                           loaded at import from the dbatools.library module's desktop/lib/
```

The thin interop wrappers exist so that public-function logic (parameter resolution, validation,
object shaping, `ShouldProcess`) can be unit-tested by mocking the seam, without a live SQL Server.

### 4.2 Connection model

A private `Connect-SsisCatalog` accepts `-SqlInstance` and optional `-SqlCredential`:

- `-SqlInstance` is a `string` (e.g. `SQL01\PROD`) **or** an already-built
  `Microsoft.SqlServer.Management.Smo.Server` / `System.Data.SqlClient.SqlConnection`.
- When a string is given: build a `SqlConnection`. With `-SqlCredential`, use SQL auth
  (`User ID`/`Password`); otherwise `Integrated Security=SSPI`.
- It returns the `Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices` root and
  its `.Catalogs["SSISDB"]` `Catalog` (when present).

Every public command exposes two parameter sets:
- **ByInstance:** `-SqlInstance` (+ `-SqlCredential`) — connects internally.
- **ByObject:** a piped `Ssis.*` object (`Catalog`, `Folder`, `Project`, …) carrying its own
  connection, for fluent pipelines (`Get-SsisFolder | Get-SsisProject`).

### 4.3 Output objects

Commands return the native MOM objects, decorated by inserting a `PSTypeName` (e.g.
`Ssis.Catalog`, `Ssis.Folder`, `Ssis.Project`, `Ssis.Package`, `Ssis.Environment`,
`Ssis.Execution`, `Ssis.Operation`). A `source/IntegrationServicesTools.format.ps1xml`
(shipped via `FormatsToProcess`) defines concise default table/list views per type. Native
properties and methods remain accessible for advanced use.

## 5. Command surface (roadmap)

| Area | Commands |
|------|----------|
| Catalog admin | `Get-SsisCatalog`, `New-SsisCatalog`, `Set-SsisCatalog` |
| Folders | `Get-SsisFolder`, `New-SsisFolder`, `Set-SsisFolder`, `Remove-SsisFolder` |
| Projects/Packages | `Get-SsisProject`, `Publish-SsisProject` (deploy `.ispac`), `Export-SsisProject`, `Remove-SsisProject`, `Get-SsisPackage` |
| Environments/Parameters | `Get-SsisEnvironment`, `New-SsisEnvironment`, `Remove-SsisEnvironment`, `Get-SsisEnvironmentVariable`, `Set-SsisEnvironmentVariable`, `Remove-SsisEnvironmentVariable`, `New-SsisEnvironmentReference`, `Remove-SsisEnvironmentReference`, `Get-SsisParameter`, `Set-SsisParameter` |
| Executions/Monitoring | `Start-SsisExecution` (`-Synchronous` optional), `Stop-SsisExecution`, `Get-SsisExecution`, `Wait-SsisExecution`, `Get-SsisExecutionMessage`, `Get-SsisOperation` |

## 6. Cross-cutting conventions

- **Parameter sets:** `ByInstance` (`-SqlInstance`/`-SqlCredential`) vs `ByObject` (pipeline), as above.
- **ShouldProcess:** all state-changing commands (`New`/`Set`/`Remove`/`Publish`/`Export`/`Start`/`Stop`)
  declare `SupportsShouldProcess` and gate the mutating call behind `$PSCmdlet.ShouldProcess(...)`,
  giving `-WhatIf`/`-Confirm`. `Remove-*` uses `ConfirmImpact = 'High'`.
- **Errors:** interop calls wrapped in try/catch; failures surface via `Write-Error` (terminating
  via `throw` only for connection failures that make the command unrunnable). No custom message
  subsystem.
- **Help:** comment-based help (Synopsis/Description/Parameters/Examples) on every public function,
  enforced by the scaffold's QA tests (`tests/QA/module.tests.ps1`).
- **Naming:** singular nouns, approved verbs only; `Publish-`/`Export-` for deploy/retrieve of
  `.ispac`; `Start-`/`Stop-`/`Wait-` for execution lifecycle.

## 7. Dependency & assembly loading (`dbatools.library`)

The MOM is not on NuGet; the only redistributable source is the `dbatools.library` module,
which ships `Microsoft.SqlServer.Management.IntegrationServices.dll` (plus
`IntegrationServicesEnum` and `IntegrationServices.Common.ObjectModel`) and the full SMO stack in
its `desktop/lib/` folder (the .NET Framework build for Windows PowerShell).

- `RequiredModules.psd1` adds `dbatools.library` (pinned to a known-good minimum version) so the
  build/test environment restores it; the manifest's `RequiredModules` also declares it so it is
  present at import.
- At import, the `.psm1` resolves the dependency's library folder via
  `(Get-Module -ListAvailable dbatools.library | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase`
  joined with `desktop\lib`, then `Add-Type -Path` the three MOM assemblies from there.
- Because the MOM has transitive dependencies (SMO, `Sdk.Sfc`, `ConnectionInfo`, SqlClient) that
  also live in that folder, the `.psm1` registers an `AppDomain.AssemblyResolve` handler scoped to
  that folder so dependent assemblies resolve on demand.
- A clear, actionable error is thrown at import if `dbatools.library` (or the expected DLLs) cannot
  be found, telling the user to `Install-Module dbatools.library`.
- No binaries are committed to this repo and no NuGet restore step is added.

## 8. Testing strategy

- **Unit tests** (`tests/Unit/...`, no SQL Server): mock the private interop seam and assert
  parameter resolution, connection-string construction, `ShouldProcess` gating, parameter-set
  binding, and object decoration.
- **Integration tests** (`tests/Integration/...`, tagged `Integration`, opt-in): run against a
  real SQL Server with SSISDB. Skipped automatically when no instance is configured (via an env
  var such as `$env:SSIS_TEST_INSTANCE`). Documented setup. **Note:** LocalDB cannot host SSISDB,
  so a full SQL Server (Developer/Express with the SSISDB-capable engine) is required.
- **QA tests** (existing): help quality, script analyzer, manifest correctness.
- **Code coverage:** the scaffold's 85% threshold conflicts with interop-only code. Resolution:
  exclude the thin interop wrappers from coverage (`Pester.ExcludeFromCodeCoverage` in
  `build.yaml`) so the threshold applies to genuinely testable logic, rather than lowering the bar.

## 9. Phased delivery

Each phase becomes its own implementation plan (plan → implement → review). This spec covers the
whole architecture; the first plan tackles **Phase 0 + Phase 1**.

- **Phase 0 — Foundation:** add `dbatools.library` dependency (`RequiredModules.psd1` + manifest
  `RequiredModules`); MOM assembly loading in `.psm1` (resolve `dbatools.library` `desktop/lib`,
  `Add-Type` the three DLLs, register `AssemblyResolve` handler); `Connect-SsisCatalog` + interop
  seam; type/format files; manifest updates (`PowerShellVersion = '5.1'`,
  `CompatiblePSEditions = @('Desktop')`); test conventions; `Get-SsisCatalog`.
- **Phase 1 — Catalog admin + Folders:** `New-SsisCatalog`, `Set-SsisCatalog`;
  `Get/New/Set/Remove-SsisFolder`.
- **Phase 2 — Projects/Packages:** `Get/Publish/Export/Remove-SsisProject`, `Get-SsisPackage`.
- **Phase 3 — Environments/Parameters:** environment, variable, reference, and parameter commands.
- **Phase 4 — Executions/Monitoring:** `Start/Stop/Get/Wait-SsisExecution`,
  `Get-SsisExecutionMessage`, `Get-SsisOperation`.

## 10. Acceptance criteria (Phase 0 + 1)

- With `dbatools.library` installed, `./build.ps1 -Tasks build` produces a built module that imports
  cleanly in Windows PowerShell 5.1 with the MOM assemblies loaded from `dbatools.library`'s
  `desktop/lib/`; importing without `dbatools.library` present fails with a clear, actionable error.
- `Get-SsisCatalog -SqlInstance <inst>` returns an `Ssis.Catalog` object (or `$null`/warning when
  SSISDB is absent) with a clean default format view.
- `New-SsisCatalog`, `Set-SsisCatalog`, and the four `*-SsisFolder` commands work against a real
  instance and honor `-WhatIf`/`-Confirm`.
- Unit tests pass with the interop seam mocked; integration tests pass against a configured
  instance and are skipped cleanly when none is configured.
- QA tests (help, analyzer, manifest) pass.

## 11. Risks & open items (resolved during planning)

1. **Assembly source (RESOLVED 2026-05-31).** Investigation showed the MOM is not on NuGet, not in
   the core/SSMS SMO packages, and not in the `SqlServer` module. The only redistributable source is
   the `dbatools.library` module (`desktop/lib/Microsoft.SqlServer.Management.IntegrationServices.dll`
   + `IntegrationServicesEnum` + `IntegrationServices.Common.ObjectModel`). Decision: depend on
   `dbatools.library` (see §7).
2. **`dbatools.library` coupling** — we depend on a third-party module's assembly versions and its
   `desktop/lib/` layout. Mitigations: pin a minimum version, resolve the path defensively, register
   an `AssemblyResolve` handler for transitive deps, and fail import with a clear message if absent.
   Watch for SqlClient/SMO load conflicts if both `dbatools` and this module are imported together.
3. **Integration host** — requires a real SQL Server with SSISDB; LocalDB is insufficient.
4. **Git** — initialized 2026-05-31 on `main`; spec and code are committed there.
