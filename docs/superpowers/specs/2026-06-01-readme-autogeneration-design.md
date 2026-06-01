# Design — Continuously updated, professional README

**Date:** 2026-06-01
**Status:** Approved (pending spec review)
**Topic:** Auto-generated command index inside a comprehensive, professional README

## Problem

The current `README.md` is the untouched Sampler placeholder. As each phase adds public
commands, any hand-written command listing would drift out of date. We want two things at once:

1. A genuinely **professional, comprehensive** README that reads like a real module front page.
2. A **drift-proof** command listing that regenerates from the source of truth and is enforced by
   a test, so it can never fall behind the actual public surface.

## Approach (locked decisions)

- **Mechanism:** automated regeneration via a build task, plus a CI/QA drift check that fails the
  run if the committed README is stale.
- **Whole-file generation:** `README.md` is a build artifact produced from `README.template.md`.
  Humans edit the template, never `README.md` directly.
- **Generated content:** only the **command index** (grouped by noun, with synopsis and a total
  count). All other prose is authored once in the template.
- **Badges:** included now as placeholders (build status, PS Gallery version, downloads) plus
  badges that are true today (license, "Windows PowerShell 5.1").
- **Status/roadmap:** not an in-README roadmap; a short status line links to `CHANGELOG.md`.
- **Index grouping:** `Environment`, `EnvironmentVariable`, and `EnvironmentReference` collapse
  under a single **Environment** heading.

## Architecture — one generator, two consumers

```
source/Public/*.ps1 ──► [ConvertTo-SsisReadme] ──► full README string
   (source of truth)            (pure function)            │
README.template.md  ──────────────┘                        │
   (prose + <!-- SSIS:COMMANDS --> token)                  │
                                                            ├─► build task Generate_Readme → writes README.md
                                                            └─► QA test Readme.tests.ps1   → compares to README.md
```

Both consumers call the **same** pure function, so they cannot disagree about what "correct"
means.

## Components

### `README.template.md` (repo root)

Holds the entire README as hand-written Markdown, with a single placeholder line:

```
<!-- SSIS:COMMANDS -->
```

This token is replaced with the generated command-index block. The template is the file a human
edits. Section layout:

| # | Section | Contents | Source |
|---|---------|----------|--------|
| — | Header | Title, one-line description, badge row | template |
| 1 | Overview | What it is, the problem it solves, who it's for | template |
| 2 | Features | Catalog/folder admin, project deploy & export, environments/variables, references, parameter overrides; pipeline-native `Ssis.*` objects; `-WhatIf`/`-Confirm` safety | template |
| 3 | Requirements | Windows PowerShell 5.1 (Desktop), SQL Server 2012+ with SSISDB, `dbatools.library`, Windows integrated auth | template |
| 4 | Installation | `Install-Module` (when published) + build-from-source; `dbatools.library` prerequisite | template |
| 5 | Quick start | One realistic end-to-end snippet: create folder → publish `.ispac` → set environment + reference | template |
| 6 | Concepts | ByInstance vs ByObject parameter sets, pipeline composition, `Ssis.*` typed output + formatting, ShouldProcess/ConfirmImpact | template |
| 7 | Command reference | Grouped-by-noun index with synopsis + total count | **generated** |
| 8 | Usage examples | Short worked examples per area (folders, projects, environments, references, parameters) | template |
| 9 | Authentication | Integrated auth default; `-SqlCredential` usage | template |
| 10 | Contributing & development | `./build.ps1` build/test, TDD, Conventional Commits, link to CLAUDE.md | template |
| 11 | Testing | Unit vs Integration split, `$env:SSIS_TEST_INSTANCE` opt-in | template |
| 12 | License & acknowledgements | License; credit dbatools.library + Sampler | template |

### `build/Build-SsisReadme.ps1`

A plain build-tooling script (not shipped in the module — it lives outside `source/`, so
ModuleBuilder never merges it and the Sampler QA enumeration never flags it). Defines two
functions:

- **`ConvertTo-SsisReadme`** — *pure*. Inputs: template path (or content) and a public-source
  folder path. Reads the template, enumerates `*.ps1` in the source folder, parses each with the
  PowerShell AST and `GetHelpContent()` to read the function name and `.SYNOPSIS`, builds the
  grouped index block, substitutes the `<!-- SSIS:COMMANDS -->` token, and returns the complete
  README string. No file writes, no module import, no SQL — directly unit-testable.
- **`Update-SsisReadme`** — calls `ConvertTo-SsisReadme` and writes the result to `README.md`
  (UTF-8, no BOM, matching repo encoding). The only side-effecting wrapper.

Uses the project's AST + `GetHelpContent()` pattern already established in
`tests/QA/module.tests.ps1`.

### Build task `Generate_Readme`

An Invoke-Build task (Sampler-discovered `*.build.ps1` in the build root, e.g.
`Readme.build.ps1`) that dot-sources `build/Build-SsisReadme.ps1` and calls `Update-SsisReadme`.

- Added to the `build` workflow in `build.yaml` so `./build.ps1 -Tasks build` refreshes the README.
- Independently runnable on demand: `./build.ps1 -Tasks Generate_Readme`.

### QA drift test `tests/QA/Readme.tests.ps1`

Dot-sources `build/Build-SsisReadme.ps1`, regenerates the README into a string with
`ConvertTo-SsisReadme`, and asserts it equals the committed `README.md`. Tagged so it runs with
the existing QA suite and fails the build if the README is stale. Failure message tells the
developer to run `./build.ps1 -Tasks Generate_Readme` and commit.

## Generated block format

A top-of-file banner marks `README.md` as generated. Because generation is whole-file, this
banner is simply the first line of `README.template.md` and round-trips unchanged — the generator
does not inject it separately:

```
<!-- This file is generated from README.template.md. Do not edit by hand. Run ./build.ps1 -Tasks Generate_Readme. -->
```

The index itself:

```markdown
## Command reference

IntegrationServicesTools exposes 23 commands.

### Catalog
- **Get-SsisCatalog** — Returns the SSISDB catalog on an instance.
- **New-SsisCatalog** — Creates the SSISDB catalog on an instance.
- **Set-SsisCatalog** — Updates SSISDB catalog properties.

### Environment
- **Get-SsisEnvironment** — ...
- **New-SsisEnvironment** — ...
- **Set-SsisEnvironmentVariable** — ...
- **Get-SsisEnvironmentReference** — ...
...
```

**Grouping rule:** the noun is the token after `Ssis` in `<Verb>-Ssis<Noun>`. Any noun beginning
with `Environment` is grouped under the single **Environment** heading; otherwise the group is the
noun itself.

**Group order:** a fixed precedence that reads in workflow order — Catalog, Folder, Project,
Package, Environment, Parameter — with any unrecognized noun appended alphabetically (so new
phases still appear without code changes).

**Command order within a group:** verb precedence Get, New, Set, Publish, Export, Start, Stop,
Wait, Remove, then alphabetical for any other verb. Synopsis text comes verbatim from each
function's `.SYNOPSIS`.

## Error handling

- **Missing `<!-- SSIS:COMMANDS -->` token** in the template → `throw`. This is a build
  misconfiguration and should fail loudly.
- **A public function missing `.SYNOPSIS`** → the entry renders with an empty synopsis (em dash
  with no text) rather than crashing. The existing `helpQuality` QA test is the real guard for
  missing synopses, so the generator does not duplicate that enforcement.
- **No public functions found** → emit the heading and a count of 0 rather than throwing (keeps
  the tool usable on a fresh/empty checkout).

## Testing (TDD)

- **Unit** (`tests/Unit/Build-SsisReadme.tests.ps1`): dot-source `build/Build-SsisReadme.ps1`;
  feed `ConvertTo-SsisReadme` a fixture template plus a temp folder of stub `*.ps1` files with
  known synopses. Assert: correct total count; `Environment*` collapsed into one group; group and
  verb ordering; synopsis extraction; token substitution; `throw` on a template missing the token;
  count-0 path on an empty source folder. No SQL, no module import.
- **QA** (`tests/QA/Readme.tests.ps1`): the drift test described above.

Both the build task and the QA test exercise the same `ConvertTo-SsisReadme`, so a green QA run
means the committed README provably matches the source.

## Out of scope (YAGNI)

- No changelog/"what's new" section generated into the README (status is a link to `CHANGELOG.md`).
- No install/requirements block generated from the manifest.
- No full per-parameter reference (the synopsis index is enough; full help ships separately).
- No git pre-commit hook (the QA drift check is the enforcement layer).
- No in-README roadmap.

## File inventory

| Path | New/changed | Purpose |
|------|-------------|---------|
| `README.template.md` | new | Hand-authored README prose + `<!-- SSIS:COMMANDS -->` token |
| `README.md` | regenerated | Build artifact; no longer hand-edited |
| `build/Build-SsisReadme.ps1` | new | `ConvertTo-SsisReadme` (pure) + `Update-SsisReadme` (writer) |
| `Readme.build.ps1` | new | Invoke-Build `Generate_Readme` task |
| `build.yaml` | changed | Add `Generate_Readme` to the `build` workflow |
| `tests/Unit/Build-SsisReadme.tests.ps1` | new | Unit tests for the generator |
| `tests/QA/Readme.tests.ps1` | new | Drift check |
