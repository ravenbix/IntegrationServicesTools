# IntegrationServicesTools — Phase 4b Design Spec: Execution Monitoring

**Date:** 2026-06-01
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`
**Phase:** 4b (second half of Phase 4 — Executions/Monitoring)

## 1. Summary

Phase 4b completes Phase 4 by adding the **monitoring** read surface over the SSISDB catalog:
inspecting an execution's message log, and listing the catalog's operations (executions,
deployments, validations). It follows Phase 4a (`Start`/`Stop`/`Get`/`Wait-SsisExecution`,
merged as PR #6) and reuses its `Ssis.Execution` object and the existing interop seam.

Two public commands are delivered, both **read-only**:

- `Get-SsisExecutionMessage` — return an execution's message log.
- `Get-SsisOperation` — list/query the catalog's operations.

## 2. Locked decisions (Phase 4b)

| Decision | Choice |
|----------|--------|
| Scope | Phase 4 closes with 4b (monitoring, this spec). Both commands are read-only — no `ShouldProcess`. |
| Message filtering | **None.** `Get-SsisExecutionMessage` emits every message; users narrow with `Where-Object`. No `-MessageType`/`-MessageSourceType` ValidateSet. |
| Message pipeline input | **Execution only.** ByObject accepts a piped `Ssis.Execution`; the command stays tightly scoped to its name. Other operations' messages are out of scope. |
| Operation filtering | `-OperationId` (single) and `-Status` (list filter). **No `-OperationType` filter** — users filter `.OperationType` with `Where-Object`. |
| Operation volume | Emit all by default; `-Top <int>` caps output to the most recent N operations (sort by `Id` descending, take N). |
| Status ValidateSet | `Get-SsisOperation -Status` reuses the exact `ServerOperationStatus` member names already used by `Get-SsisExecution` (see §6). |

## 3. Command surface

### 3.1 `Get-SsisExecutionMessage`

Returns the message log recorded for a single execution.

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`), mandatory `-ExecutionId`.
- `ByObject`: `-InputObject` (piped `Ssis.Execution`), `ValueFromPipeline`.

**Behaviour**

1. Resolve the execution — ByInstance: connect → catalog (warn + return if SSISDB absent) →
   `Get-SsisExecutionObject -ExecutionId` (warn + return if the execution is absent); ByObject:
   use `-InputObject` directly.
2. Read the execution's message log via the new `Get-SsisExecutionMessageObject` wrapper
   (`ExecutionOperation.Messages`).
3. Decorate each message as `Ssis.ExecutionMessage` and **emit immediately** — no filtering, no
   accumulation.

No `ShouldProcess` (read-only). Returns `Ssis.ExecutionMessage`.

### 3.2 `Get-SsisOperation`

Read-only query over the catalog's operations (every execution, deployment, and validation, subject
to the catalog's operation-log retention).

**Parameter sets**

- `ByInstance`: `-SqlInstance` (+ optional `-SqlCredential`); selection by `-OperationId`
  (single) **or** an optional `-Status` filter; `-Top <int>` to cap a list to the most recent N.
- `ByObject`: `-InputObject` (piped `Ssis.Catalog`), `ValueFromPipeline` — lists that catalog's
  operations.

**Behaviour**

1. Connect → catalog (warn + return if SSISDB absent), or use the piped `Ssis.Catalog`.
2. When `-OperationId` is given, index `Catalog.Operations[id]` directly via `Get-SsisOperationObject`
   (warn + return if absent); the `-Status`/`-Top` parameters are ignored.
3. Otherwise enumerate `Catalog.Operations`, filter by `-Status` when given, and emit each decorated
   as `Ssis.Operation`.
4. **`-Top N`**: emit only the most recent N operations — sort the (already-materialized) collection
   by `Id` descending and take N. This is a deliberate, scoped exception to the
   emit-immediately-no-accumulation rule: top-N inherently requires bounding the result. Without
   `-Top`, output is emitted immediately as each operation is produced.

No `ShouldProcess` (read-only). Returns `Ssis.Operation`.

## 4. Interop seam (private `*-Ssis*Object` wrappers)

Each distinct MOM call lives behind a thin private wrapper. Both construct/operate on
`IntegrationServices` objects that open real SQL connections, so they are integration-only for
coverage (consistent with the existing wrappers) but still require their own `.tests.ps1` and full
comment-based help for Sampler QA.

| Wrapper | Wraps | Returns |
|---------|-------|---------|
| `Get-SsisExecutionMessageObject` | `ExecutionOperation.Messages` (the execution's message collection). | `OperationMessage` (collection) |
| `Get-SsisOperationObject` | Indexes `Catalog.Operations[id]`, or enumerates `Catalog.Operations`. | `Operation` (one or many) |

Execution resolution by id reuses the existing Phase 4a `Get-SsisExecutionObject`; no new execution
wrapper is added. The catalog connection reuses `Connect-SsisCatalog` and `Get-SsisCatalogObject`.

## 5. MOM member names — verify by reflection BEFORE implementation

Per the project's hard-won lesson (see the `ssis-mom-property-names` memory and Phase 4a, where the
`ServerOperationStatus` member names differed from the SQL docs and only the live integration run
caught the mismatch), the member names below are **assumptions** and MUST be pinned by reflection
against the `dbatools.library` assembly as the first task of the implementation plan. Column
definitions, the `-Status` ValidateSet, and any property access depend on the verified names.

Members to confirm by reflection:

- **`OperationMessage`** (the element type of `ExecutionOperation.Messages`): expected
  `MessageTime`, `MessageSourceType`, `MessageType`, `Message`, `Id` — confirm exact names and the
  type of `MessageType`/`MessageSourceType`.
- **`Operation`** (base type of the `Catalog.Operations` collection elements): expected `Id`,
  `OperationType`, `Status`, `StartTime`, `EndTime`, `CallerName` (plus `ServerName`, `CreatedTime`,
  `ObjectName`, `ObjectType`) — confirm exact names and that `Status` is the same
  `Operation+ServerOperationStatus` enum used in Phase 4a.

## 6. Output objects & formatting

Two new `PSTypeName`s, applied via the existing `Add-SsisTypeName` helper, with new table views added
to `source/IntegrationServicesTools.format.ps1xml` (shipped via `FormatsToProcess`). Native
`OperationMessage`/`Operation` members remain accessible for advanced use. **Final column property
names are subject to the §5 reflection check.**

- **`Ssis.ExecutionMessage`** — proposed columns: `MessageTime`, `MessageSourceType`, `MessageType`,
  `Message`.
- **`Ssis.Operation`** — proposed columns: `Id`, `OperationType`, `Status`, `StartTime`, `EndTime`,
  `CallerName`.

`Get-SsisOperation -Status` uses `[ValidateSet]` over the same `ServerOperationStatus` member names
already used by Phase 4a `Get-SsisExecution` (verified by reflection there): `Created`, `Running`,
`Canceled` (one L), `Failed`, `Pending`, `UnexpectTerminated`, `Success`, `Stopping`, `Completion`.

## 7. Cross-cutting conventions (unchanged from the module spec)

- **Two parameter sets** per command: `ByInstance` and `ByObject`, resolved via `Connect-SsisCatalog`.
- **No `ShouldProcess`** — both commands are read-only.
- **Errors:** interop wrapped in try/catch; recoverable failures via `Write-Error`; `throw` only for
  connection failures that make the command unrunnable. No `-EnableException` subsystem.
- **Pipeline output emitted immediately**, decorated with `Add-SsisTypeName` (the `-Top` cap in §3.2
  is the single, documented exception).
- **Formatting:** Allman braces, single quotes, `Mandatory = $true`, 4-space indent, splats for 3+
  params (`$splat<Purpose>`, aligned), no backticks. PS5.1 Desktop; `::new()` allowed.
- **Help:** full comment-based help (incl. `.OUTPUTS`) on every public and private function.
- **No manual export registration** — add files under `source/Public` and `source/Private`; Sampler
  builds the manifest.

## 8. Testing strategy

**Unit** (`tests/Unit/...`, mock the seam, no SQL):

- Parameter-set binding for each command (ByInstance vs. ByObject; mandatory params).
- `Get-SsisExecutionMessage`: ByInstance resolves via `Get-SsisExecutionObject` then reads
  `Get-SsisExecutionMessageObject`; warning + no output when the catalog or execution is absent;
  ByObject reads messages off `-InputObject`; object decoration as `Ssis.ExecutionMessage`.
- `Get-SsisOperation`: `-OperationId` vs. list selection; `-Status` filtering; `-Top` sorts by `Id`
  descending and caps to N; warning when SSISDB absent; object decoration as `Ssis.Operation`.

**Private wrappers:** each new `*Object` wrapper gets its own `.tests.ps1` and full comment-based
help (Sampler QA enumerates private functions). Their interop bodies are exercised by the
integration tests.

**Integration** (`tests/Integration/...`, tag `Integration`, opt-in via `$env:SSIS_TEST_INSTANCE`;
self-skips when unset): deploy the fixture `.ispac`, start an execution and wait for a terminal
state, then `Get-SsisExecutionMessage` returns a non-empty log for that execution id and via a piped
`Ssis.Execution`; `Get-SsisOperation` returns the operation by id, filters by `-Status`, and honours
`-Top` (most-recent ordering). LocalDB cannot host SSISDB.

## 9. Acceptance criteria (Phase 4b)

- `Get-SsisExecutionMessage` returns an execution's messages as `Ssis.ExecutionMessage` objects, by
  `-ExecutionId` and via a piped `Ssis.Execution`; warns and returns nothing when the catalog or
  execution is absent.
- `Get-SsisOperation` returns operations as `Ssis.Operation` objects by `-OperationId`, filtered by
  `-Status`, and capped by `-Top` (most recent first); accepts a piped `Ssis.Catalog`; warns when
  SSISDB is absent.
- Both return `Ssis.*`-decorated objects with a clean default format view.
- All MOM member names used in code, columns, and the `-Status` ValidateSet are confirmed by
  reflection (§5) before implementation.
- Unit tests pass with the seam mocked; integration tests pass against a configured instance and
  skip cleanly when none is configured; QA tests (help, analyzer, manifest) pass.

## 10. Out of scope (beyond Phase 4b)

- Validation operations (`Start-SsisValidation` / `Validate-*`) and other operation-producing verbs.
- A general `Get-SsisOperationMessage` over non-execution operations (deployments, validations);
  message retrieval stays execution-scoped this phase.
- An `-OperationType` filter on `Get-SsisOperation` (use `Where-Object`).
- Designing/editing package internals.
