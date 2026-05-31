# IntegrationServicesTools — Phase 2 Design Spec: Projects & Packages

**Date:** 2026-05-31
**Status:** Approved (pending written-spec review)
**Module:** `IntegrationServicesTools`
**Parent spec:** `2026-05-31-ssis-tools-module-design.md` (§5, §9 Phase 2)

## 1. Summary

Phase 2 adds the **Projects/Packages** functional area to the module: deploying `.ispac`
projects into the SSISDB catalog, listing and retrieving them, removing them, and listing the
packages inside a project. It extends the Phase 0/1 foundation (assembly loading,
`Connect-SsisCatalog`, the catalog/folder interop seam, `Add-SsisTypeName`, `format.ps1xml`)
without changing it.

Five public commands:

- `Get-SsisProject` — list/get projects (catalog-wide or folder-scoped).
- `Publish-SsisProject` — deploy an `.ispac` into a folder.
- `Export-SsisProject` — retrieve a project's `.ispac` to disk.
- `Remove-SsisProject` — drop a project.
- `Get-SsisPackage` — list/get packages within a project.

## 2. Goals & non-goals

**Goals**
- Cover project deploy/retrieve/list/remove and package listing via the IntegrationServices MOM.
- Enable a composable pipeline: `Get-SsisFolder | Get-SsisProject | Get-SsisPackage`, and
  `Get-SsisProject | Export-SsisProject -Path <dir>`.
- Stay consistent with Phase 1 conventions (two param sets, thin testable interop seam,
  `Ssis.*`-decorated output, `ShouldProcess` on state-changers, immediate pipeline emission).

**Non-goals (YAGNI for Phase 2)**
- Deploy-operation monitoring / progress objects (deferred to Phase 4's `Get-SsisOperation`).
  `Publish-SsisProject` treats deploy as synchronous.
- Project/package parameter and environment-reference management (Phase 3).
- Executing packages (Phase 4).
- Editing package internals (out of module scope entirely, per parent spec §2).

## 3. Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| Delivery | All five commands in a single plan/PR. |
| Approach | "Approach A" — mirror Phase 1 exactly: one thin `*-Ssis*Object` wrapper per MOM call; file I/O lives in the public layer; deploy is synchronous; no operation object surfaced. |
| Deploy name | `Publish-SsisProject` defaults the catalog project name to the `.ispac` filename (without extension); `-Name` overrides. |
| Export path | `Export-SsisProject -Path` is a **directory**; the file is auto-named `<project>.ispac`; `-Force` overwrites an existing file; returns the written file's `System.IO.FileInfo`. |
| Folder scope | `Get-SsisProject` / `Get-SsisPackage` `-Folder` (and `-Project`) are **optional**; omitting them enumerates catalog-wide. |
| Param sets | Real PowerShell parameter sets (`ByInstance` + `ByObject` with `-InputObject`), a deliberate evolution of Phase 1's overloaded-`[object]` pattern, required for `folder→project→package` pipeline composition. |
| Test fixture | Commit a tiny prebuilt `.ispac` under `tests/Integration/fixtures/` as test data (documented exception to the "no binaries" rule, which targets assemblies/the MOM). |

## 4. Command surface

`*` marks parameters mandatory within that set. `-SqlInstance` remains `[object]` (string,
SMO `Server`, or `IntegrationServices`); `-SqlCredential` is optional everywhere (integrated auth
by default). The `ByObject` set binds a piped `Ssis.*` MOM object via `-InputObject`
(`ValueFromPipeline`).

| Command | ByInstance set | ByObject set (`-InputObject`) | ShouldProcess | Returns |
|---|---|---|---|---|
| `Get-SsisProject` | `-SqlInstance`*, `-SqlCredential`, `-Folder`, `-Name` | `Ssis.Folder`, `-Name` | — | `Ssis.Project` |
| `Publish-SsisProject` | `-SqlInstance`*, `-SqlCredential`, `-Folder`*, `-Path`*, `-Name` | `Ssis.Folder`, `-Path`*, `-Name` | `Low` | `Ssis.Project` |
| `Export-SsisProject` | `-SqlInstance`*, `-SqlCredential`, `-Folder`*, `-Name`*, `-Path`*, `-Force` | `Ssis.Project`, `-Path`*, `-Force` | `Low` | `FileInfo` |
| `Remove-SsisProject` | `-SqlInstance`*, `-SqlCredential`, `-Folder`*, `-Name`* | `Ssis.Project` | `High` | `void` |
| `Get-SsisPackage` | `-SqlInstance`*, `-SqlCredential`, `-Folder`, `-Project`, `-Name` | `Ssis.Project`, `-Name` | — | `Ssis.Package` |

### 4.1 Behaviors

- **`Get-SsisProject`** — With `-Folder`, scoped to that folder; with `-Name`, a single project
  (warn + return nothing if absent, matching `Get-SsisFolder`). Without `-Folder`, enumerate every
  project in every folder. ByObject: a piped `Ssis.Folder` lists that folder's projects.
- **`Publish-SsisProject`** — Reads `.ispac` bytes from `-Path`, derives the project name from the
  filename (or `-Name`), and deploys into the target folder (named `-Folder` on an instance, or a
  piped `Ssis.Folder`). Deploy is synchronous; on success the project is re-fetched and returned as
  `Ssis.Project` (so the returned object reflects the new version / `LastDeployedTime`).
- **`Export-SsisProject`** — Retrieves the project's bytes and writes `<project>.ispac` into the
  `-Path` directory. Errors if the file exists unless `-Force`. Returns the written `FileInfo`.
- **`Remove-SsisProject`** — Drops the project. `ConfirmImpact = 'High'`; prompts by default.
- **`Get-SsisPackage`** — With `-Folder`/`-Project`/`-Name`, scopes down to a project or single
  package; omitting them enumerates broadly (catalog-wide when `-Folder` omitted). ByObject: a piped
  `Ssis.Project` lists that project's packages.

## 5. Interop seam (private `*-Ssis*Object` wrappers)

Each distinct MOM call gets one thin wrapper that touches **only** the MOM (so it is the
integration-covered seam, exactly like Phase 1). Public functions own all param resolution,
file I/O, `ShouldProcess`, and decoration.

| Wrapper | MOM call | Signature → returns |
|---|---|---|
| `Get-SsisProjectObject` | `folder.Projects` / `folder.Projects[name]` | `-Folder <CatalogFolder> [-Name]` → `ProjectInfo`(s), or `$null` when a named project is absent |
| `Publish-SsisProjectObject` | `folder.DeployProject(name, bytes)` | `-Folder <CatalogFolder> -Name <string> -ProjectBytes <byte[]>` → void |
| `Export-SsisProjectObject` | `project.GetProjectBytes()` | `-Project <ProjectInfo>` → `byte[]` |
| `Remove-SsisProjectObject` | `project.Drop()` | `-Project <ProjectInfo>` → void |
| `Get-SsisPackageObject` | `project.Packages` / `project.Packages[name]` | `-Project <ProjectInfo> [-Name]` → `PackageInfo`(s), or `$null` |

**Reuse of the Phase 1 seam — no new resolution logic.** Public functions resolve the connection
via the existing `Connect-SsisCatalog`, the catalog via `Get-SsisCatalogObject`, and a named folder
via the existing `Get-SsisFolderObject`. Catalog-wide enumeration (when `-Folder`/`-Project` are
omitted) lives in the public function: loop folders from `Get-SsisFolderObject`, call the relevant
wrapper per folder/project, and **emit each object immediately** (no accumulation). The ByObject
path uses the piped MOM object directly — it skips `Connect-SsisCatalog`/`Get-SsisCatalogObject`,
reaching the catalog via the object's own `.Parent` chain when needed.

**State-changing wrappers** (`Publish-SsisProjectObject`, `Remove-SsisProjectObject`) carry the
same `[SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', …)]` justification as
`New-SsisFolderObject` — `ShouldProcess` lives in the public layer.

**File I/O stays in the public layer** (Approach A): `Publish-SsisProject` does
`[System.IO.File]::ReadAllBytes($Path)` before calling the seam; `Export-SsisProject` does
`[System.IO.File]::WriteAllBytes(...)` with the bytes the seam returns. This keeps the seam
pure-MOM and the file logic unit-testable.

## 6. Output objects & format views

Return native MOM objects decorated with a `PSTypeName` via the existing `Add-SsisTypeName`; native
members stay accessible. Two new views appended to `source/IntegrationServicesTools.format.ps1xml`
(already shipped via `FormatsToProcess`):

- **`Ssis.Project`** (wraps `ProjectInfo`) — table: `Name`, `Folder` (`$_.Parent.Name`),
  `Version` (`VersionMajor.VersionMinor`), `LastDeployedTime`, `Description`.
- **`Ssis.Package`** (wraps `PackageInfo`) — table: `Name`, `Project` (`$_.Parent.Name`),
  `EntryPoint`, `Description`.

The `Folder`/`Project`/`Version` columns are `<ScriptBlock>` properties in the ps1xml (they derive
from `.Parent` / version components). Exact MOM property names are pinned during TDD against the
real assembly; the view intent above is the contract.

`Publish-SsisProject` returns the freshly re-fetched, decorated `Ssis.Project`. `Export-SsisProject`
returns a plain `System.IO.FileInfo` (no PSTypeName — a standard framework type with its own
formatting).

## 7. Testing strategy

TDD (RED → GREEN → REFACTOR), Pester v5. Every new public **and** private function gets its own
`<Name>.tests.ps1`, full comment-based help (incl. `.OUTPUTS`), and clean PSScriptAnalyzer.

**Unit tests** (mock the interop seam; no SQL Server) — per command:
- Parameter-set binding (`ByInstance` vs `ByObject`/`-InputObject`) and mandatory enforcement
  (`-Folder` on Publish/Export/Remove; `-Name` on Export/Remove).
- Connection resolution via mocked `Connect-SsisCatalog` / `Get-SsisCatalogObject` /
  `Get-SsisFolderObject`; the ByObject path skips `Connect-SsisCatalog`.
- Catalog-wide enumeration loops folders and streams each project/package.
- `ShouldProcess` gating: `-WhatIf` makes no mutating call; `-Confirm:$false` proceeds.
- Object decoration (`Ssis.Project` / `Ssis.Package`); warn-and-return on not-found.
- `Publish` name-defaulting from the filename; `Export` directory auto-naming and `-Force`
  overwrite guard — both with `[System.IO.File]` mocked so unit tests never touch disk.

**Integration tests** (`-Tag Integration`, gated on `$env:SSIS_TEST_INSTANCE`, skip cleanly when
unset): full lifecycle against a real SSISDB — `Publish` the fixture `.ispac` into a test folder →
`Get-SsisProject` → `Get-SsisPackage` → `Export-SsisProject` to a temp dir → `Remove-SsisProject`.
These exercise all five interop wrappers, which the **85% coverage gate** requires (the wrappers
open real MOM connections and are integration-only, per parent spec §8).

**Test `.ispac` fixture.** A tiny, purpose-built `.ispac` (a single trivial package) is committed
under `tests/Integration/fixtures/`. This is **test data**, an explicit exception to the
"never commit binaries" rule (which targets assemblies / the MOM). The fixture is a genuine SSIS
project build artifact so the MOM's deploy validation accepts it; producing it requires SSIS/Visual
Studio tooling as a one-time step (noted for the implementation plan).

**QA tests** (existing): help quality, PSScriptAnalyzer, manifest correctness must continue to pass;
`PSUseOutputTypeCorrectly` remains excluded.

## 8. Acceptance criteria

- `Publish-SsisProject -SqlInstance <inst> -Folder <f> -Path <ispac>` deploys the project and
  returns an `Ssis.Project`; project name defaults to the filename and `-Name` overrides it.
- `Get-SsisProject` returns `Ssis.Project` objects catalog-wide or folder-scoped, and a single
  project by `-Name` (warn + nothing when absent); `Get-SsisFolder | Get-SsisProject` works.
- `Get-SsisPackage` returns `Ssis.Package` objects for a project; `Get-SsisProject | Get-SsisPackage`
  works.
- `Export-SsisProject -Path <dir>` writes `<project>.ispac` and returns its `FileInfo`; honors
  `-Force`; `Get-SsisProject | Export-SsisProject -Path <dir>` exports in bulk.
- `Remove-SsisProject` drops the project and honors `-WhatIf`/`-Confirm` (`ConfirmImpact High`).
- Unit tests pass with the seam mocked; integration tests pass against a configured instance and
  skip cleanly when none is configured; QA tests pass.
- New format views render concise default tables for `Ssis.Project` and `Ssis.Package`.

## 9. Risks & open items

1. **MOM property/method names** — `ProjectInfo`/`PackageInfo` member names (e.g. version fields,
   `GetProjectBytes`, `DeployProject` signature) are pinned during TDD against the real assembly; the
   design fixes intent and shapes, not exact identifiers.
2. **`.ispac` fixture provenance** — requires a one-time SSIS/Visual Studio build to produce a
   MOM-acceptable package; the plan must capture how it was generated and where it lives.
3. **Coverage gate** — as in Phase 1, the 85% threshold is met only when Integration tests run
   against a real SSISDB; the five new interop wrappers are integration-only.
4. **CLAUDE.md note** — the committed binary test fixture is a sanctioned exception; record it so the
   "no binaries" rule isn't read as violated.
