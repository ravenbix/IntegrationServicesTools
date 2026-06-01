function Get-SsisEnvironmentObject
{
    <#
        .SYNOPSIS
            Returns environment object(s) from an SSISDB catalog folder.

        .DESCRIPTION
            Returns the named environment from the folder's Environments collection, or all environments
            when no name is given. Returns $null when a named environment does not exist. Internal
            interop helper, not exported from the module.

        .EXAMPLE
            $environment = Get-SsisEnvironmentObject -Folder $folder -Name 'Prod'

            Returns the Prod environment, or $null when it does not exist.

        .PARAMETER Folder
            The SSISDB CatalogFolder object whose environments to read, as returned by Get-SsisFolderObject.

        .PARAMETER Name
            The environment name to return. When omitted, every environment in the folder is returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.EnvironmentInfo')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Folder,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Folder.Environments.Contains($Name))
            {
                return $Folder.Environments[$Name]
            }

            return $null
        }

        return $Folder.Environments
    }
}
