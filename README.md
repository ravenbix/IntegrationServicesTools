<!-- Generated file — do not edit directly. Edit README.template.md, then run ./build.ps1 -Tasks Generate_Readme. -->
# IntegrationServicesTools

[![Build Status](https://img.shields.io/badge/build-pending-lightgrey.svg)](#)
[![PowerShell Gallery](https://img.shields.io/badge/PSGallery-pending-lightgrey.svg)](#)
[![Downloads](https://img.shields.io/badge/downloads-pending-lightgrey.svg)](#)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1%20Desktop-blue.svg)](#requirements)

> PowerShell commands for administering the SQL Server Integration Services (SSIS) catalog — the SSISDB — under the Project Deployment Model.

## Overview

IntegrationServicesTools wraps the `Microsoft.SqlServer.Management.IntegrationServices`
managed object model in idiomatic PowerShell. It lets you create and configure the SSISDB
catalog, manage folders, deploy and export `.ispac` projects, and administer environments,
environment references, and parameter values — all without hand-writing T-SQL or clicking
through SQL Server Management Studio.

It targets administrators and DevOps engineers who automate SSIS deployments and want
composable, pipeline-friendly commands that return real objects.

## Features

- **Catalog administration** — create, inspect, and configure the SSISDB catalog.
- **Folder management** — create, update, and remove catalog folders.
- **Project lifecycle** — deploy (`.ispac`) and export projects, list packages, remove projects.
- **Environments** — create environments and manage their variables.
- **Environment references & parameters** — wire projects to environments and override parameter values.
- **Pipeline-native** — every command emits typed `Ssis.*` objects you can pipe between commands.
- **Safe by default** — state-changing commands support `-WhatIf` and `-Confirm`; removals are high-impact.

## Requirements

- **Windows PowerShell 5.1** (Desktop edition). PowerShell 7 is not supported.
- **SQL Server 2012 or later** with an SSISDB catalog (Project Deployment Model). LocalDB cannot host SSISDB.
- **[dbatools.library](https://www.powershellgallery.com/packages/dbatools.library)** — ships the
  SSIS managed object model assemblies this module loads at import. Install with
  `Install-Module dbatools.library`.
- **Windows integrated authentication** by default; SQL logins are supported via `-SqlCredential`.

## Installation

```powershell
# Prerequisite: the SSIS object model assemblies
Install-Module dbatools.library

# From the PowerShell Gallery (once published)
Install-Module IntegrationServicesTools

# Or build from source
git clone https://github.com/ravenbix/IntegrationServicesTools.git
cd IntegrationServicesTools
./build.ps1 -ResolveDependency -Tasks build
Import-Module ./output/module/IntegrationServicesTools/*/IntegrationServicesTools.psd1
```

## Quick start

```powershell
$instance = 'localhost\SQL2019'

# Create the SSISDB catalog (the catalog password protects its master key)
New-SsisCatalog -SqlInstance $instance -CatalogPassword (Read-Host -AsSecureString)

# Create a folder, then deploy a project into it from an .ispac file
New-SsisFolder -SqlInstance $instance -Name 'Finance' -Description 'Finance ETL'
Publish-SsisProject -SqlInstance $instance -Folder 'Finance' -Path 'C:\build\DailyLoad.ispac'

# Inspect what landed in the catalog
Get-SsisProject -SqlInstance $instance -Folder 'Finance'
```

## Concepts

- **Two parameter sets.** Every command accepts either `-SqlInstance` (`ByInstance`, with optional
  `-SqlCredential`) or a piped `Ssis.*` object that carries its own connection (`ByObject`), so you
  can fluently compose pipelines.
- **Typed output.** Commands return native object-model instances decorated with a `PSTypeName`
  (`Ssis.Catalog`, `Ssis.Folder`, `Ssis.Project`, …). Custom table views are shipped via the
  module's format file; all native members remain accessible.
- **ShouldProcess.** State-changing commands support `-WhatIf`/`-Confirm`; `Remove-*` commands are
  high-impact and prompt by default.

## Command reference

IntegrationServicesTools exposes 30 commands.

### Catalog
- **Get-SsisCatalog** — Gets the SSISDB catalog from a SQL Server instance.
- **New-SsisCatalog** — Creates the SSISDB catalog on a SQL Server instance.
- **Set-SsisCatalog** — Configures properties of the SSISDB catalog on a SQL Server instance.

### Folder
- **Get-SsisFolder** — Gets folders from the SSISDB catalog on a SQL Server instance.
- **New-SsisFolder** — Creates a folder in the SSISDB catalog on a SQL Server instance.
- **Set-SsisFolder** — Updates the description of a folder in the SSISDB catalog.
- **Remove-SsisFolder** — Removes a folder from the SSISDB catalog on a SQL Server instance.

### Project
- **Get-SsisProject** — Gets projects from the SSISDB catalog on a SQL Server instance.
- **Publish-SsisProject** — Deploys an .ispac project into a folder of the SSISDB catalog.
- **Export-SsisProject** — Exports an SSISDB project to an .ispac file on disk.
- **Remove-SsisProject** — Removes a project from a folder in the SSISDB catalog.

### Package
- **Get-SsisPackage** — Gets packages from projects in the SSISDB catalog on a SQL Server instance.

### Environment
- **Get-SsisEnvironment** — Gets environments from the SSISDB catalog on a SQL Server instance.
- **Get-SsisEnvironmentReference** — Gets the environment references defined on an SSISDB project.
- **Get-SsisEnvironmentVariable** — Gets variables from an environment in the SSISDB catalog on a SQL Server instance.
- **New-SsisEnvironment** — Creates an environment in a folder of the SSISDB catalog.
- **New-SsisEnvironmentReference** — Creates an environment reference from an SSISDB project to an environment.
- **Set-SsisEnvironmentVariable** — Adds or updates a variable on an SSISDB environment.
- **Remove-SsisEnvironment** — Removes an environment from the SSISDB catalog on a SQL Server instance.
- **Remove-SsisEnvironmentReference** — Removes an environment reference from an SSISDB project.
- **Remove-SsisEnvironmentVariable** — Removes a variable from an SSISDB environment on a SQL Server instance.

### Parameter
- **Get-SsisParameter** — Gets parameters from a project or package in the SSISDB catalog.
- **Set-SsisParameter** — Sets the value of a project or package parameter in the SSISDB catalog.

### Execution
- **Get-SsisExecution** — Gets package executions from the SSISDB catalog on a SQL Server instance.
- **Start-SsisExecution** — Starts an SSISDB package execution.
- **Stop-SsisExecution** — Stops a running SSISDB execution.
- **Wait-SsisExecution** — Waits for an SSISDB execution to reach a terminal state.

### ExecutionMessage
- **Get-SsisExecutionMessage** — Gets the message log of an SSISDB execution.

### Operation
- **Get-SsisOperation** — Gets operations (executions, deployments, validations) from the SSISDB catalog.
- **Wait-SsisOperation** — Waits for an SSISDB operation to reach a terminal state.

## Usage examples

### Deploy and export a project

```powershell
$instance = 'localhost\SQL2019'

# Deploy an .ispac into a catalog folder (the project name defaults to the .ispac name)
Publish-SsisProject -SqlInstance $instance -Folder 'Finance' -Path 'C:\build\DailyLoad.ispac'

# Export a deployed project back out to an .ispac in an existing directory
Export-SsisProject -SqlInstance $instance -Folder 'Finance' -Name 'DailyLoad' -Path 'C:\backups'

# List the packages inside a project
Get-SsisPackage -SqlInstance $instance -Folder 'Finance' -Project 'DailyLoad'
```

### Create an environment and set variables

```powershell
$instance = 'localhost\SQL2019'

# An environment lives inside a folder
New-SsisEnvironment -SqlInstance $instance -Folder 'Finance' -Name 'Production'

# Add variables; -Value drives the inferred type, or set it explicitly with -DataType
$splatServer = @{
    SqlInstance = $instance
    Folder      = 'Finance'
    Environment = 'Production'
    Name        = 'TargetServer'
    Value       = 'sql-prod-01'
    DataType    = 'String'
}
Set-SsisEnvironmentVariable @splatServer

# A sensitive variable is stored encrypted in the catalog
$splatPassword = @{
    SqlInstance = $instance
    Folder      = 'Finance'
    Environment = 'Production'
    Name        = 'ApiKey'
    Value       = 's3cr3t'
    Sensitive   = $true
}
Set-SsisEnvironmentVariable @splatPassword
```

### Wire a project to an environment and bind a parameter

```powershell
$instance = 'localhost\SQL2019'

# Reference the environment from the project (same folder by default)
$splatReference = @{
    SqlInstance = $instance
    Folder      = 'Finance'
    Project     = 'DailyLoad'
    Environment = 'Production'
}
New-SsisEnvironmentReference @splatReference

# Bind a project parameter to an environment variable...
$splatBind = @{
    SqlInstance        = $instance
    Folder             = 'Finance'
    Project            = 'DailyLoad'
    Name               = 'ServerName'
    ReferencedVariable = 'TargetServer'
}
Set-SsisParameter @splatBind

# ...or override a parameter with a literal value
Set-SsisParameter -SqlInstance $instance -Folder 'Finance' -Project 'DailyLoad' -Name 'BatchSize' -Value 5000
```

### Compose with the pipeline

```powershell
$instance = 'localhost\SQL2019'

# Pipe a folder's projects straight into export
Get-SsisProject -SqlInstance $instance -Folder 'Finance' |
    Export-SsisProject -Path 'C:\backups'
```

## Authentication

By default the module connects with the current Windows identity (integrated authentication).
To use a SQL login, pass a credential:

```powershell
$instance = 'localhost\SQL2019'
$cred = Get-Credential
Get-SsisCatalog -SqlInstance $instance -SqlCredential $cred
```

## Contributing & development

This module is built on the [Sampler](https://github.com/gaelcolas/Sampler) scaffold.

```powershell
./build.ps1 -ResolveDependency -Tasks build   # build
./build.ps1 -Tasks test                        # QA + unit tests
./build.ps1 -Tasks Generate_Readme             # regenerate this README from the template
```

Development follows test-driven development and [Conventional Commits](https://www.conventionalcommits.org/).
See [CLAUDE.md](CLAUDE.md) for the full style guide. **Edit `README.template.md`, not `README.md`** —
the latter is generated.

## Testing

- **Unit tests** mock the interop seam and run without SQL Server.
- **Integration tests** are opt-in and require a real SSISDB; set `$env:SSIS_TEST_INSTANCE` to enable
  them. They skip cleanly when it is unset.

## Status

See [CHANGELOG.md](CHANGELOG.md) for released and unreleased changes.

## License & acknowledgements

Licensed under the MIT License — see [LICENSE](LICENSE).

Built with the [Sampler](https://github.com/gaelcolas/Sampler) module scaffold. The SSIS managed
object model assemblies are provided by [dbatools.library](https://github.com/dataplat/dbatools.library).
