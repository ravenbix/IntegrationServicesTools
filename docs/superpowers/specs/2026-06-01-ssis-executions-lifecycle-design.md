# IntegrationServicesTools — Phase 4a Design Spec: Execution Lifecycle

**Date:** 2026-06-01
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`
**Phase:** 4a (first half of Phase 4 — Executions/Monitoring)

## 1. Summary

Phase 4a adds the **execution lifecycle** commands to the module: starting a package execution
in the SSISDB catalog, stopping a running execution, querying executions, and waiting for an
execution to reach a terminal state. It is the first of two sub-phases; **Phase 4b** (monitoring:
`Get-SsisExecutionMessage`, `Get-SsisOperation`) follows in its own spec → plan → implementation
cycle.

Four public commands are delivered:

- `Start-SsisExecution` — start a package execution (the rich entry point).
- `Stop-SsisExecution` — cancel a running execution.
- `Get-SsisExecution` — query executions by id, by folder/project/package, and/or by status.
- `Wait-SsisExecution` — poll an execution until it reaches a terminal state.

## 2. Why this differs from the CRUD phases

Phases 1–3 followed a get/new/set/remove shape over catalog objects. Executions do not. The MOM
call

```
long PackageInfo.Execute(bool use32BitRuntime,
                         EnvironmentReference reference,
                         Collection<PackageInfo.ExecutionValueParameterSet> setValueParameters)
```

is **fire-and-forget**: it returns a numeric execution id immediately and the run proceeds on the
server. `Catalog.Executions[id]` returns an `ExecutionOperation` whose `Status` is a cached snapshot
that only updates after `Refresh()`.

**Terminal states** (waiting stops): `Succeeded`, `Failed`, `Cancelled`, `Ended Unexpectedly`.
**Non-terminal states** (keep waiting): `Created`, `Pending`, `Running`, `Stopping`.

This asynchronous shape is why `Wait-SsisExecution` exists and why the poll loop is a first-class
concern.

## 3. Locked decisions (Phase 4a)

| Decision | Choice |
|----------|--------|
| Scope split | Phase 4 is delivered as 4a (lifecycle, this spec) and 4b (monitoring, later). |
| Start configurability | Comprehensive: environment reference, parameter overrides, 32-bit runtime, logging level, and optional synchronous wait. |
| Wait/timeout semantics | Configurable `-PollInterval` (default 5s) and `-Timeout` (default `0` = wait indefinitely). On timeout: **non-terminating** `Write-Error` **and return** the still-running execution. On success: return the completed execution. |
| Wait reuse | `Wait-SsisExecution` owns the poll loop. `Start -Synchronous` delegates to it via the ByObject path — no duplicated loop, no extra private helper. |
| Get scoping | `-ExecutionId`, `-Folder`/`-Project`/`-Package` filters, `-Status` filter, and a piped `Ssis.Package`. |
| Stop confirm impact | `ConfirmImpact = 'High'` — cancelling in-flight work is irreversible and consequential. A deliberate, documented deviation from "only `Remove-*` is High" (that rule is a floor, not a ceiling). |
| Stop output | Silent by default; `-PassThru` returns the refreshed `Ssis.Execution` (the `Stop-Process` idiom). |

## 4. Command surface

### 4.1 `Start-SsisExecution`

The rich entry point. Resolves a package, optionally binds an environment reference and parameter
overrides, starts the execution, and returns the resulting `Ssis.Execution` (or, with
`-Synchronous`, the completed one).

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`), mandatory `-Folder`, `-Project`,
  `-Package`.
- `ByObject`: `-InputObject` (piped `Ssis.Package`), `ValueFromPipeline`.

**Launch options (both sets)**

- `-EnvironmentName` — bind the execution to an environment reference so referenced parameters
  resolve. Optional `-EnvironmentFolder` selects a reference whose environment lives in a different
  folder than the project (project-relative vs. absolute reference).
- `-Parameter` — a hashtable of `Name = Value` overrides applied to this run only.
- `-Use32BitRuntime` — switch; maps to the first `Execute()` argument for packages needing a 32-bit
  provider/driver.
- `-LoggingLevel` — `[ValidateSet('None','Basic','Performance','Verbose')]`; applied as the
  `LOGGING_LEVEL` execution value (object type 50).
- `-Synchronous` — switch; after starting, wait for a terminal state before returning. When set,
  `-PollInterval` and `-Timeout` pass through to `Wait-SsisExecution`.

**Behaviour**

1. Resolve the package object (ByInstance: catalog → folder → project → package, warning + return on
   any missing link; ByObject: use `-InputObject`).
2. When `-EnvironmentName` is given, resolve the matching `EnvironmentReference` from the project's
   references (reusing the Phase 3b `Get-SsisEnvironmentReferenceObject`); warn + return if absent.
3. Gate the start behind `$PSCmdlet.ShouldProcess(<package>, 'Start SSIS execution')`.
4. Call `Start-SsisExecutionObject` with the package, resolved reference (or `$null`), `-Parameter`,
   `-LoggingLevel`, and `-Use32BitRuntime`; receive the `[long]` execution id.
5. Fetch the new execution via `Get-SsisExecutionObject` and decorate as `Ssis.Execution`.
6. If `-Synchronous`, pipe it to `Wait-SsisExecution` (passing `-PollInterval`/`-Timeout`) and emit
   the completed object; otherwise emit the started object.

`SupportsShouldProcess`, `ConfirmImpact = 'Medium'`. Returns `Ssis.Execution`.

### 4.2 `Stop-SsisExecution`

Cancels a running execution.

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`), mandatory `-ExecutionId`.
- `ByObject`: `-InputObject` (piped `Ssis.Execution`), `ValueFromPipeline`.

**Behaviour**

1. Resolve the execution (ByInstance: `Get-SsisExecutionObject` by id, warn + return if absent;
   ByObject: use `-InputObject`).
2. Gate behind `$PSCmdlet.ShouldProcess(<id>, 'Stop SSIS execution')`.
3. Call `Stop-SsisExecutionObject` (`ExecutionOperation.Stop()`).
4. With `-PassThru`: `Refresh()` and emit the `Ssis.Execution` (now `Stopping`/`Cancelled`);
   otherwise emit nothing.

`SupportsShouldProcess`, `ConfirmImpact = 'High'`. Adds `-PassThru` switch. Silent by default.

### 4.3 `Get-SsisExecution`

Read-only query surface.

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`); selection by `-ExecutionId`
  **or** any of `-Folder`/`-Project`/`-Package`; plus an optional `-Status` filter.
- `ByObject`: `-InputObject` (piped `Ssis.Package`), `ValueFromPipeline` — lists that package's
  executions.

`-Status` uses `[ValidateSet]` over the catalog statuses
(`Created`, `Running`, `Cancelled`, `Failed`, `Pending`, `EndedUnexpectedly`, `Succeeded`,
`Stopping`, `Completed`).

**Behaviour**

1. Connect → catalog (warn + return if SSISDB absent).
2. When `-ExecutionId` is given, index `Catalog.Executions[id]` directly.
3. Otherwise enumerate `Catalog.Executions` and filter by folder/project/package and/or status.
4. Decorate each result as `Ssis.Execution` and **emit immediately** (no accumulation).

No `ShouldProcess` (read-only). Returns `Ssis.Execution`.

### 4.4 `Wait-SsisExecution`

Owns the shared poll loop; observes only.

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`), mandatory `-ExecutionId`.
- `ByObject`: `-InputObject` (piped `Ssis.Execution`), `ValueFromPipeline`.

**Options**

- `-PollInterval` — seconds between refreshes (default `5`).
- `-Timeout` — total seconds to wait; `0` (default) waits indefinitely.

**Behaviour**

1. Resolve the execution object (ByInstance: `Get-SsisExecutionObject` by id; ByObject:
   `-InputObject`).
2. Loop: `Update-SsisExecutionObject` (`Refresh()`) → if `Status` is terminal, emit the completed
   `Ssis.Execution` and return. If `-Timeout` > 0 and elapsed ≥ `-Timeout`, write a
   **non-terminating** error (`Write-Error`) and **return the still-running** object. Otherwise
   `Start-Sleep -Seconds $PollInterval` and repeat.

No `ShouldProcess` (it observes, does not mutate). Returns `Ssis.Execution`.

The timeout design follows the module's error rule (recoverable failures use `Write-Error`, not
`throw`): callers that want a hard failure opt in with `-ErrorAction Stop`; callers that want to
inspect get the object back and read `.Status`; `$?` reflects the incomplete wait either way.

## 5. Interop seam (private `*-Ssis*Object` wrappers)

Each distinct MOM call lives behind a thin private wrapper. These construct/operate on
`IntegrationServices` objects that open real SQL connections, so they are integration-only for
coverage (consistent with the existing wrappers) but still require their own `.tests.ps1` and full
comment-based help for Sampler QA.

| Wrapper | Wraps | Returns |
|---------|-------|---------|
| `Start-SsisExecutionObject` | Builds the `ExecutionValueParameterSet` collection from `-Parameter` (object type 20 for project parameters, 30 for package parameters) and `-LoggingLevel` (`LOGGING_LEVEL`, object type 50), then calls `PackageInfo.Execute(use32Bit, reference, valueParameters)`. | `[long]` execution id |
| `Get-SsisExecutionObject` | Indexes `Catalog.Executions[id]`, or enumerates `Catalog.Executions`. | `ExecutionOperation` (one or many) |
| `Stop-SsisExecutionObject` | `ExecutionOperation.Stop()`. | (none) |
| `Update-SsisExecutionObject` | `ExecutionOperation.Refresh()`. | the refreshed `ExecutionOperation` |

Keeping `ExecutionValueParameterSet` construction **inside** `Start-SsisExecutionObject` (rather than
a separate helper) keeps the public function's intent unit-testable by mocking a single seam, and
avoids an extra private function carrying QA overhead for logic with one caller.

Environment-reference resolution reuses the existing Phase 3b `Get-SsisEnvironmentReferenceObject`;
no new reference wrapper is added.

## 6. Output objects & formatting

- New `PSTypeName`: `Ssis.Execution`, applied via the existing `Add-SsisTypeName` helper.
- New table view in `source/IntegrationServicesTools.format.ps1xml`: **Id, Folder, Project, Package,
  Status, StartTime, EndTime**.
- Native `ExecutionOperation` members remain accessible for advanced use.

## 7. Cross-cutting conventions (unchanged from the module spec)

- **Two parameter sets** per command: `ByInstance` and `ByObject`, resolved via `Connect-SsisCatalog`.
- **ShouldProcess** on `Start` (`Medium`) and `Stop` (`High`); `Get` and `Wait` do not change state.
- **Errors:** interop wrapped in try/catch; recoverable failures via `Write-Error`; `throw` only for
  connection failures that make the command unrunnable. No `-EnableException` subsystem.
- **Pipeline output emitted immediately**, decorated with `Add-SsisTypeName`.
- **Formatting:** Allman braces, single quotes, `Mandatory = $true`, 4-space indent, splats for 3+
  params (`$splat<Purpose>`, aligned), no backticks. PS5.1 Desktop; `::new()` allowed.
- **Help:** full comment-based help (incl. `.OUTPUTS`) on every public and private function.

## 8. Testing strategy

**Unit** (`tests/Unit/...`, mock the seam, no SQL):

- Parameter-set binding for each command (ByInstance vs. ByObject; mandatory params).
- `Start-SsisExecution`: environment-reference resolution path; `-Parameter`/`-LoggingLevel`/
  `-Use32BitRuntime` passed through to `Start-SsisExecutionObject` correctly; `ShouldProcess`
  gating; `-Synchronous` delegates to the wait path; object decoration.
- `Wait-SsisExecution` poll loop: mock `Update-SsisExecutionObject` to yield
  `Running, Running, Succeeded` and assert it stops and emits; mock a never-terminal status with a
  finite `-Timeout` and assert a non-terminating `Write-Error` **and** that the running object is
  returned; mock `Start-Sleep` so tests do not actually sleep and assert `-PollInterval` is honored.
- `Stop-SsisExecution`: `ShouldProcess` gating; silent by default; `-PassThru` returns the refreshed
  object.
- `Get-SsisExecution`: id vs. filter selection; `-Status` filtering; warning when SSISDB absent.

**Private wrappers:** each new `*-SsisExecutionObject` gets its own `.tests.ps1` and full
comment-based help (Sampler QA enumerates private functions). Their interop bodies are exercised by
the integration tests.

**Integration** (`tests/Integration/...`, tag `Integration`, opt-in via `$env:SSIS_TEST_INSTANCE`;
self-skips when unset): deploy the fixture `.ispac`, then start → wait → assert `Succeeded`;
start → stop → assert `Cancelled`; get by id and by `-Status`. LocalDB cannot host SSISDB.

## 9. Acceptance criteria (Phase 4a)

- `Start-SsisExecution` starts a package and returns an `Ssis.Execution`; with `-Synchronous` it
  blocks until a terminal state and returns the completed execution; honours `-WhatIf`/`-Confirm`.
- `-EnvironmentName`, `-Parameter`, `-Use32BitRuntime`, and `-LoggingLevel` flow through to the
  `Execute()` call.
- `Stop-SsisExecution` cancels a running execution; is silent by default, returns the refreshed
  object with `-PassThru`, prompts by default (`ConfirmImpact High`), and honours `-WhatIf`.
- `Get-SsisExecution` returns executions by id, by folder/project/package, and by `-Status`, and
  accepts a piped `Ssis.Package`.
- `Wait-SsisExecution` returns the completed execution on success; on `-Timeout` emits a
  non-terminating error and returns the still-running object; `-PollInterval`/`-Timeout` are honored.
- All four return `Ssis.Execution` objects with a clean default format view.
- Unit tests pass with the seam mocked; integration tests pass against a configured instance and
  skip cleanly when none is configured; QA tests (help, analyzer, manifest) pass.

## 10. Out of scope (Phase 4b and beyond)

- `Get-SsisExecutionMessage` (execution message log) and `Get-SsisOperation` (catalog operations).
- Validation operations (`Validate-*`), operation message enumeration beyond executions.
- Designing/editing package internals.
