# Changelog for IntegrationServicesTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Set-SsisCatalog command.
- New-SsisCatalog command.
- Get-SsisCatalog command.
- Module foundation: load the SSIS object model from dbatools.library; dbatools-style connection helper.

### Changed

- For changes in existing functionality.

### Deprecated

- For soon-to-be removed features.

### Removed

- Placeholder Get-Something / Get-PrivateFunction sample functions.

### Fixed

- Declare `Configuration` and `Metadata` required modules so the build bootstrap installs
  ModuleBuilder's dependencies (the build previously failed resolving them).
- Load the SSIS assemblies through a compiled assembly resolver instead of a PowerShell
  scriptblock, fixing a StackOverflow that occurred when PSScriptAnalyzer ran while the module
  was imported.

### Security

- In case of vulnerabilities.

