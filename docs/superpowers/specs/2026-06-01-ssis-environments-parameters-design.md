# IntegrationServicesTools — Phase 3 Design Spec: Environments & Parameters

**Date:** 2026-06-01
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`
**Parent spec:** `2026-05-31-ssis-tools-module-design.md` (§5, §9 Phase 3)

## 1. Summary

Phase 3 adds the **Environments/Parameters** functional area: SSISDB environments and their
typed variables, the environment **references** that bind a project to an environment, and the
project/package **parameters** whose values are set either as literals or as references to an
environment variable. It extends the Phase 0–2 foundation (assembly loading, `Connect-SsisCatalog`,
the catalog/folder/project/package interop seam, `Add-SsisTypeName`, `format.ps1xml`) without
changing it.

Eleven public commands, delivered as one design spec and **two implementation plans/PRs**:

- **Plan 3a — Environments & variables:** `Get-SsisEnvironment`, `New-SsisEnvironment`,
  `Remove-SsisEnvironment`, `Get-SsisEnvironmentVariable`, `Set-SsisEnvironmentVariable`,
  `Remove-SsisEnvironmentVariable`.
- **Plan 3b — References & parameters:** `Get-SsisEnvironmentReference`,
  `New-SsisEnvironmentReference`, `Remove-SsisEnvironmentReference`, `Get-SsisParameter`,
  `Set-SsisParameter`.

(`Get-SsisEnvironmentReference` is one command beyond the parent spec's surface, added during
brainstorming for symmetry: it lists a project's environment bindings and enables
`Get-SsisEnvironmentReference | Remove-SsisEnvironmentReference`.)

## 2. Goals & non-goals

**Goals**
- Cover environment CRUD, typed environment-variable upsert/removal, project↔environment reference
  management, and project/package parameter inspection and value-setting via the IntegrationServices
  MOM.
- Enable composable pipelines: `Get-SsisFolder | Get-SsisEnvironment`,
  `Get-SsisEnvironment | Get-SsisEnvironmentVariable`,
  `Get-SsisProject | Get-SsisParameter | Set-SsisParameter -ReferencedVariable …`,
  `Get-SsisEnvironmentReference | Remove-SsisEnvironmentReference`.
- Stay consistent with Phase 1–2 conventions (two param sets, thin testable interop seam,
  `Ssis.*`-decorated output, `ShouldProcess` on state-changers, immediate pipeline emission).

**Non-goals (YAGNI for Phase 3)**
- Executing packages / passing an environment reference at execution time (Phase 4).
- Reading decrypted **sensitive** values back. SSISDB encrypts sensitive variables/parameters
  server-side and the MOM returns them masked; `Get-*` surfaces the masked value as-is.
- A dedicated `Ssis.EnvironmentReference` *editing* surface beyond create/list/remove (references
  are immutable bindings; "change" = remove + new).
- Designing/editing parameter *definitions* (parameters are defined inside the project at build
  time; this module sets their **values**, it does not add or remove parameters).

## 3. Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| Delivery | One design spec; **two** implementation plans/PRs — 3a (environments + variables), 3b (references + parameters). |
| Approach | "Approach A" — mirror Phases 1–2 exactly: one thin `*-Ssis*Object` wrapper per MOM call; public layer owns param resolution, validation, `ShouldProcess`, decoration; unit tests mock the seam. |
| Sensitive values | A `[switch] -Sensitive` on `Set-SsisEnvironmentVariable` (and the sensitive flag honored for parameters) flags server-side encryption; the value is passed as a plain `[object]`/`[string]`. `Get-*` never returns the decrypted value. |
| Env-variable typing | `Set-SsisEnvironmentVariable` **infers** the SSIS `System.TypeCode` from the supplied value's .NET type; an explicit `-DataType` overrides/disambiguates. A pure private helper `ConvertTo-SsisTypeCode` performs the mapping. |
| Reference kind | `New-SsisEnvironmentReference` infers **relative vs absolute** from `-EnvironmentFolder`: omitted → relative (environment in the project's own folder); supplied → absolute (environment in the named folder). |
| Parameter value | `Set-SsisParameter` exposes mutually-exclusive `-Value` (literal) and `-ReferencedVariable` (binds to an environment variable name); project-level by default, `-Package` targets a package-scoped parameter. |
| Get-Reference | Add `Get-SsisEnvironmentReference` (11th command) for symmetry and pipeline-to-Remove. |

## 4. Architecture

### 4.1 Reuse of the Phase 0–2 foundation (unchanged)

Public functions resolve the connection via the existing `Connect-SsisCatalog`, the catalog via
`Get-SsisCatalogObject`, a named folder via `Get-SsisFolderObject`, and (for 3b) a project/package
via the Phase 2 `Get-SsisProjectObject` / `Get-SsisPackageObject`. Output is decorated with the
existing `Add-SsisTypeName`. No foundation or Phase 1/2 code changes.

### 4.2 The one architectural difference from Phase 2 — explicit persistence

Phase 2's MOM mutations (`DeployProject`, `Drop`, `GetProjectBytes`) persist immediately. Phase 3's
objects do **not**; they require an explicit persist call on the owning object:

| Operation | MOM persistence |
|---|---|
| Create an environment | construct `EnvironmentInfo(folder, name, description)` then `.Create()` |
| Remove an environment | `environment.Drop()` |
| Add/update an environment variable | mutate `environment.Variables` then `environment.Alter()` |
| Remove an environment variable | `environment.Variables.Remove(name)` then `environment.Alter()` |
| Add an environment reference | `project.References.Add(env[, folder])` then `project.Alter()` |
| Remove an environment reference | `project.References.Remove(...)` then `project.Alter()` |
| Set a parameter value | `parameter.Set(valueType, value)` then `project.Alter()` |

**Each interop wrapper owns its persist call** (`Create`/`Alter`/`Drop`), so the public layer never
touches MOM persistence semantics. After a mutating wrapper succeeds, the public command **re-reads**
the object (via the matching `Get-*Object` wrapper) and returns the fresh `Ssis.*`-decorated result —
the same re-fetch pattern as `Publish-SsisProject`.

### 4.3 Parameter sets

Every command exposes the Phase 2 real-parameter-set shape:
- **`ByInstance`** (default): `-SqlInstance` (`[object]`, no `ValueFrom*` attribute so piped objects
  route to `ByObject`) `+ -SqlCredential` (optional) + scope/name params.
- **`ByObject`**: `-InputObject` (`ValueFromPipeline`) binds a piped `Ssis.*` MOM object; skips
  `Connect-SsisCatalog`/`Get-SsisCatalogObject`, reaching the catalog via the object's own `.Parent`
  chain.

`Set-SsisParameter`'s literal-vs-referenced choice is a **second, independent** dimension from the
connection set. To avoid a four-way parameter-set explosion (`ByInstance×{Literal,Referenced}` …),
`-Value` and `-ReferencedVariable` belong to both sets and are enforced **mutually exclusive at
runtime** (supplying both, or neither, is a terminating parameter error).

## 5. Command surface

`*` marks parameters mandatory within that set. `-SqlInstance` is `[object]` (string, SMO `Server`,
or `IntegrationServices`); `-SqlCredential` is optional everywhere (integrated auth by default). The
`ByObject` set binds a piped `Ssis.*` MOM object via `-InputObject` (`ValueFromPipeline`).

### 5.1 Plan 3a — Environments & variables

| Command | ByInstance set | ByObject set (piped) | ShouldProcess | Returns |
|---|---|---|---|---|
| `Get-SsisEnvironment` | `-SqlInstance`*, `-Folder`, `-Name` | `Ssis.Folder`, `-Name` | — | `Ssis.Environment` |
| `New-SsisEnvironment` | `-SqlInstance`*, `-Folder`*, `-Name`*, `-Description` | `Ssis.Folder`, `-Name`*, `-Description` | Low | `Ssis.Environment` |
| `Remove-SsisEnvironment` | `-SqlInstance`*, `-Folder`*, `-Name`* | `Ssis.Environment` | High | void |
| `Get-SsisEnvironmentVariable` | `-SqlInstance`*, `-Folder`*, `-Environment`*, `-Name` | `Ssis.Environment`, `-Name` | — | `Ssis.EnvironmentVariable` |
| `Set-SsisEnvironmentVariable` | `-SqlInstance`*, `-Folder`*, `-Environment`*, `-Name`*, `-Value`, `-DataType`, `-Sensitive`, `-Description` | `Ssis.Environment`, `-Name`*, `-Value`, `-DataType`, `-Sensitive`, `-Description` | Low | `Ssis.EnvironmentVariable` |
| `Remove-SsisEnvironmentVariable` | `-SqlInstance`*, `-Folder`*, `-Environment`*, `-Name`* | `Ssis.EnvironmentVariable` | High | void |

**Behaviors:**
- **`Get-SsisEnvironment`** — `-Folder` optional → enumerate every folder's environments
  (loop folders from `Get-SsisFolderObject`, emit each environment immediately); `-Folder` given →
  that folder; `-Name` → a single environment (warn + return nothing when absent, matching
  `Get-SsisProject`). ByObject: a piped `Ssis.Folder` lists its environments.
- **`New-SsisEnvironment`** — creates an environment in the target folder (named folder on an
  instance, or a piped `Ssis.Folder`); re-reads and returns the new `Ssis.Environment`.
- **`Remove-SsisEnvironment`** — drops the environment; `ConfirmImpact = 'High'`.
- **`Get-SsisEnvironmentVariable`** — lists a target environment's variables, or one by `-Name`
  (warn + nothing when absent). ByObject: a piped `Ssis.Environment`.
- **`Set-SsisEnvironmentVariable`** — **upsert**: updates the variable's value when it exists,
  otherwise adds it. The SSIS `System.TypeCode` is **inferred** from `-Value`'s .NET type and
  overridden by `-DataType`. `-Sensitive` flags server-side encryption. Persists via
  `environment.Alter()`; re-reads and returns the `Ssis.EnvironmentVariable`. (Targeting an
  environment, not an existing variable, so a piped `Ssis.Environment` is the ByObject input.)
- **`Remove-SsisEnvironmentVariable`** — removes the variable and `Alter()`s the environment.
  ByObject pipes the **variable** itself (`Get-SsisEnvironmentVariable | Remove-SsisEnvironmentVariable`),
  reaching its environment via `.Parent`. `ConfirmImpact = 'High'`.

### 5.2 Plan 3b — References & parameters

| Command | ByInstance set | ByObject set (piped) | ShouldProcess | Returns |
|---|---|---|---|---|
| `Get-SsisEnvironmentReference` | `-SqlInstance`*, `-Folder`*, `-Project`* | `Ssis.Project` | — | `Ssis.EnvironmentReference` |
| `New-SsisEnvironmentReference` | `-SqlInstance`*, `-Folder`*, `-Project`*, `-Environment`*, `-EnvironmentFolder` | `Ssis.Project`, `-Environment`*, `-EnvironmentFolder` | Low | `Ssis.EnvironmentReference` |
| `Remove-SsisEnvironmentReference` | `-SqlInstance`*, `-Folder`*, `-Project`*, `-Environment`*, `-EnvironmentFolder` | `Ssis.EnvironmentReference` | High | void |
| `Get-SsisParameter` | `-SqlInstance`*, `-Folder`*, `-Project`*, `-Package`, `-Name` | `Ssis.Project` \| `Ssis.Package`, `-Name` | — | `Ssis.Parameter` |
| `Set-SsisParameter` | `-SqlInstance`*, `-Folder`*, `-Project`*, `-Package`, `-Name`*, `-Value` \| `-ReferencedVariable` | `Ssis.Parameter`, `-Value` \| `-ReferencedVariable` | Low | `Ssis.Parameter` |

**Behaviors:**
- **`Get-SsisEnvironmentReference`** — lists a project's environment references. ByObject: a piped
  `Ssis.Project`.
- **`New-SsisEnvironmentReference`** — `-EnvironmentFolder` omitted → **relative** reference
  (environment in the project's own folder); supplied → **absolute** reference to that folder's
  environment. Persists via `project.References.Add(...)` + `project.Alter()`; re-reads and returns
  the new `Ssis.EnvironmentReference`. ByObject: a piped `Ssis.Project`.
- **`Remove-SsisEnvironmentReference`** — removes the matching reference and `Alter()`s the project.
  ByObject pipes the **reference** (`Get-SsisEnvironmentReference | Remove-SsisEnvironmentReference`),
  reaching the project via `.Parent`. `ConfirmImpact = 'High'`.
- **`Get-SsisParameter`** — `-Package` omitted → **project-level** parameters; supplied → that
  package's parameters. `-Name` → a single parameter (warn + nothing when absent). ByObject: a piped
  `Ssis.Project` (project params) or `Ssis.Package` (package params).
- **`Set-SsisParameter`** — sets the parameter value as a literal (`-Value`) or a reference to an
  environment variable (`-ReferencedVariable`); the two are **mutually exclusive** (both or neither →
  terminating error). Maps to `parameter.Set(Literal|Referenced, value)` + `project.Alter()`;
  re-reads and returns the `Ssis.Parameter`. ByObject pipes the `Ssis.Parameter` itself.

## 6. Interop seam (private `*-Ssis*Object` wrappers)

Each distinct MOM call gets one thin wrapper that touches **only** the MOM and owns its persist call,
so it is the integration-covered seam (exactly like Phases 1–2). Public functions own all param
resolution, validation, the `-Value`/`-ReferencedVariable` guard, `ShouldProcess`, and decoration.

### 6.1 Plan 3a

| Wrapper | MOM call | Signature → returns |
|---|---|---|
| `Get-SsisEnvironmentObject` | `folder.Environments` / `[name]` | `-Folder <CatalogFolder> [-Name]` → `EnvironmentInfo`(s), or `$null` when a named environment is absent |
| `New-SsisEnvironmentObject` | `EnvironmentInfo(folder, name, desc).Create()` | `-Folder <CatalogFolder> -Name <string> [-Description]` → void |
| `Remove-SsisEnvironmentObject` | `environment.Drop()` | `-Environment <EnvironmentInfo>` → void |
| `Get-SsisEnvironmentVariableObject` | `environment.Variables` / `[name]` | `-Environment <EnvironmentInfo> [-Name]` → `EnvironmentVariableInfo`(s), or `$null` |
| `Set-SsisEnvironmentVariableObject` | add/update in `.Variables` + `environment.Alter()` | `-Environment <EnvironmentInfo> -Name <string> -Value <object> -TypeCode <TypeCode> -Sensitive <bool> [-Description]` → void |
| `Remove-SsisEnvironmentVariableObject` | `environment.Variables.Remove(name)` + `environment.Alter()` | `-Environment <EnvironmentInfo> -Name <string>` → void |

### 6.2 Plan 3b

| Wrapper | MOM call | Signature → returns |
|---|---|---|
| `Get-SsisEnvironmentReferenceObject` | `project.References` (+ locate by env/folder) | `-Project <ProjectInfo> [-Environment] [-EnvironmentFolder]` → `EnvironmentReference`(s), or `$null` |
| `New-SsisEnvironmentReferenceObject` | `project.References.Add(env[, folder])` + `project.Alter()` | `-Project <ProjectInfo> -Environment <string> [-EnvironmentFolder]` → void |
| `Remove-SsisEnvironmentReferenceObject` | `project.References.Remove(...)` + `project.Alter()` | `-Project <ProjectInfo> -Environment <string> [-EnvironmentFolder]` → void |
| `Get-SsisParameterObject` | `project.Parameters` / `package.Parameters` / `[name]` | `-Container <ProjectInfo\|PackageInfo> [-Name]` → `ParameterInfo`(s), or `$null` |
| `Set-SsisParameterObject` | `parameter.Set(valueType, value)` + persist on owning project | `-Parameter <ParameterInfo> -ValueType <ParameterValueType> -Value <object>` → void |

### 6.3 Pure (non-interop) helper

`ConvertTo-SsisTypeCode` — maps a supplied value's .NET type, or an explicit `-DataType` name, to a
`System.TypeCode` (e.g. `[int]`→`Int32`, `[string]`→`String`, `[bool]`→`Boolean`,
`[datetime]`→`DateTime`). It touches no MOM, so it is **fully unit-testable** (real coverage, unlike
the integration-only interop wrappers). Used by `Set-SsisEnvironmentVariable`.

**State-changing wrappers** (`New-`/`Set-`/`Remove-` verbs) carry the same
`[SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', …)]` justification as the
Phase 1/2 seam — `ShouldProcess` lives in the public layer. (`Get-` and `ConvertTo-` wrappers do not
trigger the rule.)

## 7. Output objects & format views

Return native MOM objects decorated with a `PSTypeName` via the existing `Add-SsisTypeName`; native
members stay accessible. Four new views appended to `source/IntegrationServicesTools.format.ps1xml`
(already shipped via `FormatsToProcess`). `Folder`/`Environment`/`Project`/`Scope`/`ReferenceType`/
`Variables` columns are `<ScriptBlock>` properties derived from `.Parent`/counts:

- **`Ssis.Environment`** (`EnvironmentInfo`) — `Name`, `Folder` (`$_.Parent.Name`), `Description`,
  `Variables` (`$_.Variables.Count`).
- **`Ssis.EnvironmentVariable`** (`EnvironmentVariableInfo`) — `Name`, `Environment`
  (`$_.Parent.Name`), `DataType` (`$_.Type`), `Value`, `Sensitive`, `Description`.
- **`Ssis.EnvironmentReference`** (`EnvironmentReference`) — `Project` (`$_.Parent.Name`),
  `Environment` (`$_.EnvironmentName`), `EnvironmentFolder` (`$_.EnvironmentFolderName`),
  `ReferenceType` (Relative/Absolute, from `$_.ReferenceType`).
- **`Ssis.Parameter`** (`ParameterInfo`) — `Name`, `Scope` (project/package, derived from `.Parent`),
  `DataType`, `ValueType` (Literal/Referenced), `Value` (`$_.Value`/`$_.ReferencedVariableName`),
  `Sensitive`, `Required`.

Exact MOM property names are pinned during TDD against the real assembly; the view **intent** above is
the contract.

## 8. Testing strategy

TDD (RED → GREEN → REFACTOR), Pester v5. Every new public **and** private function gets its own
`<Name>.tests.ps1`, full comment-based help (incl. `.OUTPUTS`), and clean PSScriptAnalyzer.

**Unit tests** (mock the interop seam; no SQL Server) — per command:
- Parameter-set binding (`ByInstance` vs `ByObject`/`-InputObject`) and mandatory enforcement.
- Connection resolution via mocked `Connect-SsisCatalog` / `Get-SsisCatalogObject` /
  `Get-SsisFolderObject` / `Get-SsisProjectObject` / `Get-SsisPackageObject`; the ByObject path skips
  `Connect-SsisCatalog`.
- Catalog-wide / folder-wide enumeration loops and streams each object (no accumulation).
- `Set-SsisEnvironmentVariable` upsert: updates an existing variable vs adds a new one; type
  inference and `-DataType` override (asserted through the `ConvertTo-SsisTypeCode` mapping).
- `Set-SsisParameter` mutual-exclusion guard: both `-Value`+`-ReferencedVariable`, or neither, errors
  and makes no `Set` call; each alone maps to the right `ParameterValueType`.
- `New-SsisEnvironmentReference` relative-vs-absolute selection from `-EnvironmentFolder`.
- `ShouldProcess` gating: `-WhatIf` makes no mutating call; `-Confirm:$false` proceeds.
- Object decoration (`Ssis.Environment` / `…Variable` / `…Reference` / `Ssis.Parameter`);
  warn-and-return on not-found.

**`ConvertTo-SsisTypeCode`** gets a focused unit test matrix (each supported .NET type and
`-DataType` string → expected `TypeCode`; unknown `-DataType` → terminating error).

**Integration tests** (`-Tag Integration`, gated on `$env:SSIS_TEST_INSTANCE`, skip cleanly when
unset): a full lifecycle against a real SSISDB, **reusing the Phase 2 `.ispac` fixture** (references
and parameters require a deployed project):
deploy fixture → `New-SsisEnvironment` → `Set-SsisEnvironmentVariable` (literal + sensitive) →
`Get-SsisEnvironmentVariable` → `New-SsisEnvironmentReference` → `Get-SsisEnvironmentReference` →
`Set-SsisParameter -ReferencedVariable` (and a `-Value` literal) → `Get-SsisParameter` →
`Remove-SsisEnvironmentReference` → `Remove-SsisEnvironmentVariable` → `Remove-SsisEnvironment`.
These exercise all eleven new interop wrappers, which the **85% coverage gate** requires (the wrappers
open real MOM connections and are integration-only, per parent spec §8). Each plan (3a, 3b) ships its
own integration test file; 3b's reuses 3a's environment-creation helpers where practical.

**QA tests** (existing): help quality, PSScriptAnalyzer, manifest correctness must continue to pass;
`PSUseOutputTypeCorrectly` remains excluded.

## 9. Acceptance criteria

**Plan 3a**
- `New-SsisEnvironment -SqlInstance <inst> -Folder <f> -Name <e>` creates an environment and returns
  an `Ssis.Environment`; `Get-SsisEnvironment` returns environments catalog-wide, folder-scoped, or a
  single one by `-Name`; `Get-SsisFolder | Get-SsisEnvironment` works.
- `Set-SsisEnvironmentVariable` upserts a typed variable (type inferred from `-Value`, overridable by
  `-DataType`), honors `-Sensitive`, and returns an `Ssis.EnvironmentVariable`;
  `Get-SsisEnvironmentVariable` lists them; `… | Remove-SsisEnvironmentVariable` removes one.
- `Remove-SsisEnvironment` drops the environment and honors `-WhatIf`/`-Confirm` (`High`).

**Plan 3b**
- `New-SsisEnvironmentReference` creates a relative reference by default and an absolute one when
  `-EnvironmentFolder` is given; `Get-SsisEnvironmentReference` lists a project's references;
  `Get-SsisEnvironmentReference | Remove-SsisEnvironmentReference` removes one (`High`).
- `Get-SsisParameter` returns project-level parameters by default and package-level with `-Package`;
  `Get-SsisProject | Get-SsisParameter` works.
- `Set-SsisParameter -Value` sets a literal and `Set-SsisParameter -ReferencedVariable` binds to an
  environment variable; supplying both or neither errors; returns an `Ssis.Parameter`.

**Both**
- Unit tests pass with the seam mocked; integration tests pass against a configured instance and skip
  cleanly when none is configured; QA tests pass.
- New format views render concise default tables for all four new `Ssis.*` types.

## 10. Risks & open items

1. **MOM property/method names** — `EnvironmentInfo`/`EnvironmentVariableInfo`/`EnvironmentReference`/
   `ParameterInfo` member names (`Create`/`Alter`/`Drop`, `Variables.Add(name, TypeCode, value,
   sensitive, description)`, `References.Add` overloads, `ParameterInfo.Set(ParameterValueType,
   value)`, `EnvironmentName`/`EnvironmentFolderName`/`ReferenceType`, `Value`/`ReferencedVariableName`)
   are **pinned during TDD** against the real assembly; the design fixes intent and shapes, not exact
   identifiers (same posture as Phase 2 §9).
2. **Sensitive read-back** — by SSISDB design the decrypted value cannot be read back; tests assert
   the masked/empty value, not a round-trip of the secret.
3. **Two-dimensional parameter binding** — `Set-SsisParameter`'s value-type is enforced by a runtime
   guard rather than parameter sets; the unit tests must cover both-supplied and neither-supplied
   error paths explicitly.
4. **Coverage gate** — as in Phases 1–2, the 85% threshold is met only when Integration tests run
   against a real SSISDB; the eleven new interop wrappers are integration-only. `ConvertTo-SsisTypeCode`
   is the one new fully-unit-testable helper.
5. **Reference persistence quirk** — adding/removing a reference and then `Alter()`-ing the project may
   require re-reading the project for the references collection to reflect the change; the re-fetch
   step in the public command must account for this (verified during TDD).
