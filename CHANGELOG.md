# Changelog for IntegrationServicesTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Corrected ServerOperationStatus enum member names used by Wait-SsisExecution (terminalStates),
  Get-SsisExecution (ValidateSet), and Stop-SsisExecution (help text) to match the real MOM values:
  Success (was Succeeded), Canceled (was Cancelled), UnexpectTerminated (was EndedUnexpectedly),
  Completion (was Completed). Prevents Wait-SsisExecution from polling to timeout on successful runs.
- Start-SsisExecutionObject now passes a concrete Collection[ExecutionValueParameterSet] to
  PackageInfo.Execute instead of a raw ArrayList, matching the MOM overload signature.

### Added

- Wait-SsisExecution command.
- Stop-SsisExecution command.
- Start-SsisExecution command.
- Get-SsisExecution command.
- Continuously generated README: a professional README.template.md plus a Generate_Readme
  build task and QA drift test (with an Assert_Readme_Clean build gate) that regenerate and
  verify the command reference from source/Public.
- Set-SsisParameter command.
- Get-SsisParameter command.
- Remove-SsisEnvironmentReference command.
- New-SsisEnvironmentReference command.
- Get-SsisEnvironmentReference command.
- Remove-SsisEnvironmentVariable command.
- Set-SsisEnvironmentVariable command.
- Get-SsisEnvironmentVariable command.
- Remove-SsisEnvironment command.
- New-SsisEnvironment command.
- Get-SsisEnvironment command.
- Remove-SsisProject command.
- Export-SsisProject command.
- Publish-SsisProject command.
- Get-SsisPackage command.
- Get-SsisProject command.
- Set-SsisFolder and Remove-SsisFolder commands.
- New-SsisFolder command.
- Get-SsisFolder command.
- Set-SsisCatalog command.
- New-SsisCatalog command.
- Get-SsisCatalog command.
- Module foundation: load the SSIS object model from dbatools.library; dbatools-style connection helper.

### Changed

- New-SsisCatalog keeps the catalog encryption password as a SecureString end-to-end, converting
  to the plain string the object model requires only at the point of the call.

### Deprecated

- For soon-to-be removed features.

### Removed

- Placeholder Get-Something / Get-PrivateFunction sample functions.

### Fixed

- Publish-SsisProject no longer leaks the deploy Operation into its output; the interop wrapper
  discards the value returned by CatalogFolder.DeployProject so the command emits only the
  Ssis.Project. Caught by the project integration lifecycle test against a real SSISDB.
- Declare `Configuration` and `Metadata` required modules so the build bootstrap installs
  ModuleBuilder's dependencies (the build previously failed resolving them).
- Load the SSIS assemblies through a compiled assembly resolver instead of a PowerShell
  scriptblock, fixing a StackOverflow that occurred when PSScriptAnalyzer ran while the module
  was imported.

### Security

- In case of vulnerabilities.

