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

## Motivation

Administering the SSISDB catalog usually means clicking through SQL Server Management
Studio dialogs or hand-writing calls to the `catalog.*` stored procedures — neither of
which composes, scripts, or version-controls cleanly. IntegrationServicesTools closes
that gap: it exposes the Integration Services managed object model as idiomatic,
pipeline-friendly PowerShell so catalog setup, project deployment, environment wiring,
and parameter binding become repeatable, reviewable automation instead of manual steps.

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

### Supported SQL Server versions

The module targets the on-premises database engine and supports every release that ships
the SSISDB catalog:

| SQL Server release | Database engine version | SSISDB (Project Deployment Model) |
| --- | --- | --- |
| 2012 | 11.0 | Yes (SSISDB introduced) |
| 2014 | 12.0 | Yes |
| 2016 | 13.0 | Yes |
| 2017 | 14.0 | Yes |
| 2019 | 15.0 | Yes |
| 2022 | 16.0 | Yes |
| 2025 | 17.0 | Yes |

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

IntegrationServicesTools exposes 31 commands.

### Catalog

| Command | Synopsis |
| --- | --- |
| **[Get-SsisCatalog](source/Public/Get-SsisCatalog.ps1)** | Gets the SSISDB catalog from a SQL Server instance. |
| **[New-SsisCatalog](source/Public/New-SsisCatalog.ps1)** | Creates the SSISDB catalog on a SQL Server instance. |
| **[Set-SsisCatalog](source/Public/Set-SsisCatalog.ps1)** | Configures properties of the SSISDB catalog on a SQL Server instance. |

### Folder

| Command | Synopsis |
| --- | --- |
| **[Get-SsisFolder](source/Public/Get-SsisFolder.ps1)** | Gets folders from the SSISDB catalog on a SQL Server instance. |
| **[New-SsisFolder](source/Public/New-SsisFolder.ps1)** | Creates a folder in the SSISDB catalog on a SQL Server instance. |
| **[Set-SsisFolder](source/Public/Set-SsisFolder.ps1)** | Updates the description of a folder in the SSISDB catalog. |
| **[Remove-SsisFolder](source/Public/Remove-SsisFolder.ps1)** | Removes a folder from the SSISDB catalog on a SQL Server instance. |

### Project

| Command | Synopsis |
| --- | --- |
| **[Get-SsisProject](source/Public/Get-SsisProject.ps1)** | Gets projects from the SSISDB catalog on a SQL Server instance. |
| **[Publish-SsisProject](source/Public/Publish-SsisProject.ps1)** | Deploys an .ispac project into a folder of the SSISDB catalog. |
| **[Export-SsisProject](source/Public/Export-SsisProject.ps1)** | Exports an SSISDB project to an .ispac file on disk. |
| **[Remove-SsisProject](source/Public/Remove-SsisProject.ps1)** | Removes a project from a folder in the SSISDB catalog. |

### Package

| Command | Synopsis |
| --- | --- |
| **[Get-SsisPackage](source/Public/Get-SsisPackage.ps1)** | Gets packages from projects in the SSISDB catalog on a SQL Server instance. |

### Environment

| Command | Synopsis |
| --- | --- |
| **[Get-SsisEnvironment](source/Public/Get-SsisEnvironment.ps1)** | Gets environments from the SSISDB catalog on a SQL Server instance. |
| **[Get-SsisEnvironmentReference](source/Public/Get-SsisEnvironmentReference.ps1)** | Gets the environment references defined on an SSISDB project. |
| **[Get-SsisEnvironmentVariable](source/Public/Get-SsisEnvironmentVariable.ps1)** | Gets variables from an environment in the SSISDB catalog on a SQL Server instance. |
| **[New-SsisEnvironment](source/Public/New-SsisEnvironment.ps1)** | Creates an environment in a folder of the SSISDB catalog. |
| **[New-SsisEnvironmentReference](source/Public/New-SsisEnvironmentReference.ps1)** | Creates an environment reference from an SSISDB project to an environment. |
| **[Set-SsisEnvironmentVariable](source/Public/Set-SsisEnvironmentVariable.ps1)** | Adds or updates a variable on an SSISDB environment. |
| **[Remove-SsisEnvironment](source/Public/Remove-SsisEnvironment.ps1)** | Removes an environment from the SSISDB catalog on a SQL Server instance. |
| **[Remove-SsisEnvironmentReference](source/Public/Remove-SsisEnvironmentReference.ps1)** | Removes an environment reference from an SSISDB project. |
| **[Remove-SsisEnvironmentVariable](source/Public/Remove-SsisEnvironmentVariable.ps1)** | Removes a variable from an SSISDB environment on a SQL Server instance. |

### Parameter

| Command | Synopsis |
| --- | --- |
| **[Get-SsisParameter](source/Public/Get-SsisParameter.ps1)** | Gets parameters from a project or package in the SSISDB catalog. |
| **[Set-SsisParameter](source/Public/Set-SsisParameter.ps1)** | Sets the value of a project or package parameter in the SSISDB catalog. |

### Execution

| Command | Synopsis |
| --- | --- |
| **[Get-SsisExecution](source/Public/Get-SsisExecution.ps1)** | Gets package executions from the SSISDB catalog on a SQL Server instance. |
| **[Start-SsisExecution](source/Public/Start-SsisExecution.ps1)** | Starts an SSISDB package execution. |
| **[Stop-SsisExecution](source/Public/Stop-SsisExecution.ps1)** | Stops a running SSISDB execution. |
| **[Wait-SsisExecution](source/Public/Wait-SsisExecution.ps1)** | Waits for an SSISDB execution to reach a terminal state. |

### ExecutionMessage

| Command | Synopsis |
| --- | --- |
| **[Get-SsisExecutionMessage](source/Public/Get-SsisExecutionMessage.ps1)** | Gets the message log of an SSISDB execution. |

### Operation

| Command | Synopsis |
| --- | --- |
| **[Get-SsisOperation](source/Public/Get-SsisOperation.ps1)** | Gets operations (executions, deployments, validations) from the SSISDB catalog. |
| **[Wait-SsisOperation](source/Public/Wait-SsisOperation.ps1)** | Waits for an SSISDB operation to reach a terminal state. |

### Validation

| Command | Synopsis |
| --- | --- |
| **[Start-SsisValidation](source/Public/Start-SsisValidation.ps1)** | Validates an SSISDB project or package. |

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

## Code of Conduct

This project adopts the [Contributor Covenant](CODE_OF_CONDUCT.md) code of conduct. By
participating, you are expected to uphold it.

## Security

To report a security vulnerability, follow the process in [SECURITY.md](SECURITY.md) —
please do not open a public issue for security bugs.

## License & acknowledgements

Licensed under the MIT License — see [LICENSE](LICENSE).

Built with the [Sampler](https://github.com/gaelcolas/Sampler) module scaffold. The SSIS managed
object model assemblies are provided by [dbatools.library](https://github.com/dataplat/dbatools.library).
