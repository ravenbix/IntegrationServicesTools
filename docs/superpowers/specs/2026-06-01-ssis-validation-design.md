# IntegrationServicesTools — Design Spec: Validation Operations

**Date:** 2026-06-01
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`
**Feature:** Validation operations (`Start-SsisValidation` + `Wait-SsisOperation`)

## 1. Summary

This feature adds the **validation** verb to the module — the one operation-producing action left
out of scope by the Phase 4b monitoring spec (§10). It lets an administrator validate a deployed
SSISDB project (or a single package within it) and inspect the resulting validation operation,
optionally waiting for it to finish.

It is the first work beyond the original five-area roadmap (catalog, folders, projects/packages,
environments/parameters, executions/monitoring), and is built squarely on that foundation: the
MOM `Validate()` call returns a validation **operation** that the existing `Get-SsisOperation` /
`Ssis.Operation` surface already understands, so no new output type is introduced.

Two public commands are delivered:

- `Start-SsisValidation` — validate a project or a package; returns the validation `Ssis.Operation`.
- `Wait-SsisOperation` — poll any `Ssis.Operation` to a terminal state (the general waiter that
  `Start-SsisValidation -Synchronous` delegates to, mirroring the `Start`/`Wait-SsisExecution` split).

Plus two private interop seams: `Start-SsisValidationObject` and `Update-SsisOperationObject`.

## 2. MOM facts (pinned by reflection, 2026-06-01)

Verified against the assemblies shipped in `dbatools.library` `desktop\lib`, before writing this spec
(applying the Phase 4a/4b lesson — pin MOM members before designing, not during debugging):

| Fact | Value |
|------|-------|
| `ProjectInfo.Validate` signature | `Validate(bool use32RuntimeOn64, ProjectInfo.ReferenceUsage referenceUsage, EnvironmentReference reference) → Int64` |
| `PackageInfo.Validate` signature | Identical signature; same return (the validation operation id) |
| `ReferenceUsage` enum (full name `Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo+ReferenceUsage`) | `UseAllReferences`, `UseNoReference`, `SpecifyReference` |
| Validation result type | `ValidationOperation` **inherits from** `Operation` — so `Catalog.Operations[id]` returns it and it decorates cleanly as `Ssis.Operation`; **no new type/view needed** |
| `Operation.Refresh()` | Present — re-reads server state in place (poll primitive for `Wait-SsisOperation`) |
| `Operation.Status` type | `Operation+ServerOperationStatus` — the **same** enum `Get-SsisExecution`/`Wait-SsisExecution` already use |
| Terminal `ServerOperationStatus` members | `Success`, `Failed`, `Canceled`, `UnexpectTerminated`, `Completion` (reused verbatim from `Wait-SsisExecution`) |

**Note:** there is **no** `ValidationType` (Full/Dependencies) on this overload — validation is
parameterized solely by how environment references are applied (`ReferenceUsage`) and the runtime
bitness flag.

## 3. Locked decisions

| Decision | Choice |
|----------|--------|
| Target scope | **Both project and package.** `-Package` is optional in the ByInstance set: omit it to validate the whole project (`ProjectInfo.Validate`); supply it to validate one package (`PackageInfo.Validate`). |
| Output type | **Reuse `Ssis.Operation`** and its existing format view. No `Ssis.Validation` type. |
| Waiting | `Start-SsisValidation` exposes `-Synchronous` (+ `-PollInterval`/`-Timeout`); when set it delegates to the new **general** `Wait-SsisOperation` via the ByObject pipe. |
| Reference usage | Inferred + a `-NoReference` switch: `-EnvironmentName` → `SpecifyReference`; `-NoReference` → `UseNoReference`; neither → `UseAllReferences` (default). `-EnvironmentName` and `-NoReference` are **mutually exclusive** (runtime `throw`, the `Set-SsisParameter` pattern — not param sets). |
| Runtime bitness | Reuse the `-Use32BitRuntime` switch from `Start-SsisExecution`; it maps directly to the `use32RuntimeOn64` argument. |
| Parameter overrides | **Out of scope.** `Validate()` takes no value-parameter-set argument (unlike `Execute()`), so there is no `-Parameter`. |
| Validation messages | **Out of scope** this feature. The returned operation exposes `.Messages`, but a `Get-SsisOperationMessage` command stays deferred (Phase 4b §10). |

## 4. Command surface

### 4.1 `Start-SsisValidation`

Validates a deployed project or one of its packages, returning the started validation operation.

**Parameter sets**

- **ByInstance** (default): `-SqlInstance` (+ optional `-SqlCredential`); mandatory `-Folder`,
  mandatory `-Project`; optional `-Package` (omit → project-level validation).
- **ByObject**: `-InputObject` (`ValueFromPipeline`) — a piped `Ssis.Project` **or** `Ssis.Package`.
  The target kind is detected from the MOM type (`ProjectInfo` vs `PackageInfo`); for a package the
  parent project (`.Parent`) is used to resolve a named environment reference.

**Common parameters** (both sets)

- `-EnvironmentName` / `-EnvironmentFolder` — same surface and folder-matching semantics as
  `Start-SsisExecution` (omitted `-EnvironmentFolder` matches a reference by name regardless of folder).
- `-NoReference` — switch; forces `UseNoReference`.
- `-Use32BitRuntime` — switch; passed as `use32RuntimeOn64`.
- `-Synchronous` — switch; wait for the validation operation to finish before returning.
- `-PollInterval` — `[ValidateRange(1, [int]::MaxValue)]`, default 5; seconds between refreshes when
  `-Synchronous`.
- `-Timeout` — `[ValidateRange(0, [int]::MaxValue)]`, default 0 (wait indefinitely) when `-Synchronous`.

**Attributes:** `SupportsShouldProcess`, `ConfirmImpact = 'Medium'` (matches `Start-SsisExecution`),
`DefaultParameterSetName = 'ByInstance'`, `[OutputType('Ssis.Operation')]`.

**Behaviour**

1. **Resolve the target.**
   - ByObject: `$InputObject` is the target; if it is a `PackageInfo`, the project for reference
     lookup is `$InputObject.Parent`; if a `ProjectInfo`, it is the project itself. `$catalog = $null`
     (the piped object already carries its connection).
   - ByInstance: `Connect-SsisCatalog` → `Get-SsisCatalogObject` → `Get-SsisFolderObject` →
     `Get-SsisProjectObject`; if `-Package` supplied, `Get-SsisPackageObject`. Each missing level
     writes a `Write-Warning` and returns (no change) — the same guard ladder as `Start-SsisExecution`.
     The target is the package when `-Package` is supplied, otherwise the project.
2. **Resolve reference usage** (see §5). On the `-EnvironmentName`/`-NoReference` conflict, `throw`.
   When `-EnvironmentName` is supplied but no matching reference exists on the project, `Write-Warning`
   and return.
3. `ShouldProcess($targetName, 'Start SSIS validation')` — return if declined.
4. `$operationId = Start-SsisValidationObject -Target $target -ReferenceUsage <usage> -Reference <ref> [-Use32BitRuntime]`.
5. Resolve the catalog if it was `$null` (walk `.Parent` to the catalog, as `Start-SsisExecution` does),
   then `$operation = Get-SsisOperationObject -Catalog $catalog -OperationId $operationId`.
6. If `-Synchronous`: pipe the **undecorated** operation to `Wait-SsisOperation -PollInterval -Timeout`
   (the waiter decorates). Otherwise `$operation | Add-SsisTypeName -TypeName 'Ssis.Operation'`.

### 4.2 `Wait-SsisOperation`

Polls a catalog operation until it reaches a terminal state, then returns it. A general waiter — it
takes any `Ssis.Operation`, not just validations.

**Parameter sets**

- **ByInstance** (default): `-SqlInstance` (+ optional `-SqlCredential`); mandatory `-OperationId` (`[long]`).
- **ByObject**: `-InputObject` (`ValueFromPipeline`) — a piped `Ssis.Operation`.

**Common parameters:** `-PollInterval` (`[ValidateRange(1, …)]`, default 5), `-Timeout`
(`[ValidateRange(0, …)]`, default 0).

**Attributes:** no `ShouldProcess` (read-only poll), `DefaultParameterSetName = 'ByInstance'`,
`[OutputType('Ssis.Operation')]`.

**Behaviour** (identical shape to `Wait-SsisExecution`)

1. ByObject: `$operation = $InputObject`. ByInstance: connect → catalog (warn+return if absent) →
   `Get-SsisOperationObject -OperationId` (warn+return if absent).
2. Loop on **logical** elapsed time (`$elapsed += $PollInterval`, so the timeout path is unit-testable
   with `Start-Sleep` mocked):
   - `$operation = Update-SsisOperationObject -Operation $operation`.
   - If `Status.ToString()` is terminal (`Success`/`Failed`/`Canceled`/`UnexpectTerminated`/`Completion`):
     decorate and return.
   - If `-Timeout > 0` and `$elapsed >= $Timeout`: non-terminating `Write-Error`, decorate the
     still-running operation, return (caller escalates with `-ErrorAction Stop`).
   - `Start-Sleep -Seconds $PollInterval`; `$elapsed += $PollInterval`.

### 4.3 `Start-SsisValidationObject` (private seam)

`Validate()` wrapper. Returns the operation id.

- Params: `-Target` (mandatory, the `ProjectInfo`/`PackageInfo`), `-Reference`
  (`[AllowNull()]`, the `EnvironmentReference` or `$null`), `-ReferenceUsage`
  (`[ValidateSet('UseAllReferences','UseNoReference','SpecifyReference')]`), `-Use32BitRuntime` (switch).
- Body: cast `$ReferenceUsage` to the `ProjectInfo+ReferenceUsage` enum and call
  `$Target.Validate($Use32BitRuntime.IsPresent, $referenceUsageEnum, $Reference)`; `return` the `[long]`.
- `[OutputType([long])]`; `[SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', …)]`
  (public layer owns ShouldProcess).

### 4.4 `Update-SsisOperationObject` (private seam)

Parallel to `Update-SsisExecutionObject`: `-Operation` (mandatory) → `$Operation.Refresh(); return $Operation`.
`[OutputType('Microsoft.SqlServer.Management.IntegrationServices.Operation')]`; same PSSA suppression
(the `Update` verb trips the rule but `Refresh()` only re-reads server state).

## 5. Reference-usage resolution

```
if ($EnvironmentName-bound -and $NoReference) { throw 'mutually exclusive' }

if ($EnvironmentName-bound) {
    reference = matching reference on the project (warn+return if none)
    usage     = 'SpecifyReference'
}
elseif ($NoReference) {
    reference = $null
    usage     = 'UseNoReference'
}
else {
    reference = $null
    usage     = 'UseAllReferences'   # default
}
```

Reference matching reuses `Get-SsisEnvironmentReferenceObject -Project $projectObject` and the same
name/folder `Where-Object` filter as `Start-SsisExecution` (capturing the `-EnvironmentFolder`-bound
flag into a local before the filter scriptblock, since `$PSBoundParameters` inside `Where-Object`
refers to `Where-Object`'s own parameters).

## 6. Output objects & formatting

Both commands emit native MOM operation objects decorated `Ssis.Operation` via `Add-SsisTypeName`,
exactly as `Get-SsisOperation` already does. The existing `Ssis.Operation` format view in
`source/IntegrationServicesTools.format.ps1xml` is reused unchanged. Output is emitted immediately.

## 7. Error handling

- Recoverable "not found" conditions (no catalog/folder/project/package, no matching reference, no
  operation) → `Write-Warning` + return, consistent with `Start-SsisExecution`/`Wait-SsisExecution`.
- The `-EnvironmentName` + `-NoReference` conflict → `throw` (programming error, like
  `Set-SsisParameter`'s `-Value`/`-ReferencedVariable` guard).
- `-Synchronous`/`Wait-SsisOperation` timeout → non-terminating `Write-Error` + return the
  still-running operation.
- Interop calls wrapped in try/catch in the seams where a `.NET` failure is plausible; `throw` only for
  connection failures that make the command unrunnable. No `-EnableException` subsystem.

## 8. Testing

**Unit** (`tests/Unit/...`, mock the interop seams — no live SQL):

- `Start-SsisValidation`: param-set binding (ByInstance/ByObject); project-vs-package target selection
  (`-Package` present/absent; piped `ProjectInfo` vs `PackageInfo`); reference-usage inference for all
  three cases **and** the mutually-exclusive `throw`; warn-and-return guards for each missing level and
  for a missing named reference; `ShouldProcess` gating (declined → no `Validate` call); `Ssis.Operation`
  decoration; `-Synchronous` delegates to `Wait-SsisOperation` (and pipes an undecorated object so the
  type is not inserted twice).
- `Wait-SsisOperation`: ByInstance/ByObject binding; terminal-state detection for each terminal member;
  timeout path with `Start-Sleep` mocked (logical elapsed time) → `Write-Error` + returns the object;
  warn-and-return when catalog/operation absent.
- `Start-SsisValidationObject`: builds the right `ReferenceUsage` enum value and forwards
  `use32RuntimeOn64`; returns the id. **Fakes return the real types** (the Phase 2 lesson — a fake
  `Validate` that returns nothing would hide an array-leak).
- `Update-SsisOperationObject`: calls `Refresh()` and returns the same object.

**Integration** (`tests/Integration/...`, tag `Integration`, opt-in on `$env:SSIS_TEST_INSTANCE`,
self-skips when unset): using the committed `.ispac` fixture — publish the project, then
`Start-SsisValidation` at project level and at package level with `-Synchronous`, asserting the
returned `Ssis.Operation` reaches `Success`; exercise `Wait-SsisOperation` directly against a started
validation. Teardown drains the folder before `Remove-SsisFolder` (SSISDB only drops empty folders).

**QA** (`tests/QA`): help quality (full comment-based help incl. `.OUTPUTS` on all four functions —
public and private), PSScriptAnalyzer, manifest correctness; README drift test regenerates the command
index from the new public synopses.

## 9. Build & conventions

- Add files under `source/Public` / `source/Private`; Sampler/ModuleBuilder wires exports — no manual
  `FunctionsToExport`/`Export-ModuleMember`.
- Allman braces, single quotes, `Mandatory = $true`, 4-space indent, no backticks (splat for 3+ params,
  aligned hashtables), PS5.1 Desktop (`::new()` allowed).
- TDD (RED → GREEN → REFACTOR), Conventional Commits, comment-based help with `.OUTPUTS` everywhere.
- Run the comprehensive suite with `$env:SSIS_TEST_INSTANCE='localhost'` (integration **runs**, not
  skips) green **before** opening a PR.

## 10. Out of scope (YAGNI)

- `-Parameter` value overrides on validation (the `Validate()` overload has no value-parameter-set arg).
- A `Get-SsisOperationMessage` for reading validation/deployment operation messages (still
  execution-scoped per Phase 4b §10; the returned operation's `.Messages` remains accessible natively).
- A `ValidationType` (Full/Dependencies) parameter — not present on the MOM overload used here.
- An `-OperationType` filter or other additions to `Get-SsisOperation` (unchanged by this feature).
