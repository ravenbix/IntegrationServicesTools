# Integration test fixtures

## ISTools_TestProject.ispac

`Ssis.Project.Integration.tests.ps1` requires a real `.ispac` file named **`ISTools_TestProject.ispac`**
placed in this directory.

### What it must be

A genuine SSIS project build artifact produced by Visual Studio with the SQL Server Integration
Services extension. The MOM's `DeployProject` method validates the package structure on deploy, so a
hand-crafted or manually zipped file will be rejected. The project need only contain one trivial
package (an empty Control Flow is sufficient).

### How to produce it

1. Open Visual Studio (any edition) with the SSIS extension installed.
2. Create a new **Integration Services Project** (any name — the catalog project name is set from
   the file name, not the project-internal name).
3. Add a single package (the default `Package.dtsx` with no tasks is fine).
4. Build the project (`Build > Build Solution`). This produces an `.ispac` file in the project's
   `bin\Development\` folder.
5. Copy that `.ispac` to this directory and rename it `ISTools_TestProject.ispac`.

### Behaviour when the fixture is absent

`Ssis.Project.Integration.tests.ps1` checks for this file in `BeforeDiscovery`. When it is absent
(or when `$env:SSIS_TEST_INSTANCE` is unset), the entire Describe block is **skipped** — not
failed. The test suite stays green without the fixture; it simply cannot exercise the live deploy
path until the file is present and a test instance is configured.
