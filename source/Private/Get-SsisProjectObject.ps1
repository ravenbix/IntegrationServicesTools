function Get-SsisProjectObject
{
    <#
        .SYNOPSIS
            Returns project object(s) from an SSISDB catalog folder.

        .DESCRIPTION
            Returns the named project from the folder's Projects collection, or all projects when no
            name is given. Returns $null when a named project does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $project = Get-SsisProjectObject -Folder $folder -Name 'Sales'

            Returns the Sales project, or $null when it does not exist.

        .PARAMETER Folder
            The SSISDB CatalogFolder object whose projects to read, as returned by Get-SsisFolderObject.

        .PARAMETER Name
            The project name to return. When omitted, every project in the folder is returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ProjectInfo')]
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
            if ($Folder.Projects.Contains($Name))
            {
                return $Folder.Projects[$Name]
            }

            return $null
        }

        return $Folder.Projects
    }
}
