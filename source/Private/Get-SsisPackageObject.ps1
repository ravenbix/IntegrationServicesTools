function Get-SsisPackageObject
{
    <#
        .SYNOPSIS
            Returns package object(s) from an SSISDB project.

        .DESCRIPTION
            Returns the named package from the project's Packages collection, or all packages when no
            name is given. Returns $null when a named package does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $package = Get-SsisPackageObject -Project $project -Name 'Load.dtsx'

            Returns the Load.dtsx package, or $null when it does not exist.

        .PARAMETER Project
            The SSISDB ProjectInfo object whose packages to read, as returned by Get-SsisProjectObject.

        .PARAMETER Name
            The package name to return. When omitted, every package in the project is returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.PackageInfo
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.PackageInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Project,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Project.Packages.Contains($Name))
            {
                return $Project.Packages[$Name]
            }

            return $null
        }

        return $Project.Packages
    }
}
