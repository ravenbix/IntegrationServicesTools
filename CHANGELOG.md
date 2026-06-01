# Changelog for IntegrationServicesTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

