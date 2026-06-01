<#
    .SYNOPSIS
        Generates the tiny ISTools_TestProject.ispac fixture used by the project integration test.

    .DESCRIPTION
        Builds a minimal, genuine SSIS project deployment file (.ispac) containing a single empty
        package, using the Microsoft.SqlServer.Dts.Runtime managed API shipped with dbatools.library.
        This produces a real .ispac that the SSISDB catalog's deploy validation accepts, without
        needing Visual Studio or the SSIS extension.

        The script reuses the IntegrationServicesTools module's COMPILED assembly resolver (by
        importing the built module first), so it must be run from the repository root AFTER the
        module has been built (./build.ps1 -Tasks build). It deliberately does not register its own
        scriptblock AssemblyResolve handler, which would StackOverflow.

        Run this once and commit the resulting .ispac so the integration lifecycle test can run.

    .EXAMPLE
        ./build.ps1 -Tasks build
        ./tests/Integration/fixtures/New-TestProjectIspac.ps1

        Builds the module, then writes ISTools_TestProject.ispac next to this script.

    .PARAMETER OutputPath
        The full path to write the .ispac to. Defaults to ISTools_TestProject.ispac alongside this
        script, which is where the integration test expects it.

    .OUTPUTS
        System.IO.FileInfo
#>
[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
param
(
    [Parameter()]
    [string]
    $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'ISTools_TestProject.ispac')
)

$ErrorActionPreference = 'Stop'

# Repo root is three levels up from tests/Integration/fixtures.
$repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path

$moduleOutput = Join-Path -Path $repoRoot -ChildPath 'output\module'
$requiredModules = Join-Path -Path $repoRoot -ChildPath 'output\RequiredModules'

if (-not (Test-Path -Path $moduleOutput))
{
    throw "Built module not found at '$moduleOutput'. Run './build.ps1 -Tasks build' from the repo root first."
}

# Importing the built module registers the module's compiled assembly resolver and loads the SSIS
# managed object model from dbatools.library. The compiled resolver then satisfies ManagedDTS's
# transitive dependencies on demand without recursing.
$env:PSModulePath = $moduleOutput + [System.IO.Path]::PathSeparator +
    $requiredModules + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module -Name 'IntegrationServicesTools' -Force -ErrorAction Stop

$libraryBase = (Get-ChildItem -Path (Join-Path -Path $requiredModules -ChildPath 'dbatools.library') -Directory |
    Sort-Object -Property Name -Descending |
    Select-Object -First 1).FullName
$libFolder = Join-Path -Path $libraryBase -ChildPath 'desktop\lib'
$null = [System.Reflection.Assembly]::LoadFrom((Join-Path -Path $libFolder -ChildPath 'Microsoft.SqlServer.ManagedDTS.dll'))

if (Test-Path -Path $OutputPath)
{
    Remove-Item -Path $OutputPath -Force
}

# CreateProject(path) backs the project with the target .ispac; Save() persists it there.
$project = [Microsoft.SqlServer.Dts.Runtime.Project]::CreateProject($OutputPath)

try
{
    $project.Name = 'ISTools_TestProject'

    $package = [Microsoft.SqlServer.Dts.Runtime.Package]::new()
    $package.Name = 'Package'

    $null = $project.PackageItems.Add($package, 'Package.dtsx')
    $project.Save()
}
finally
{
    $project.Dispose()
}

Get-Item -Path $OutputPath
