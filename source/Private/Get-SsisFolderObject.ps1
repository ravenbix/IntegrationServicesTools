function Get-SsisFolderObject
{
    <#
        .SYNOPSIS
            Returns catalog folder object(s) from an SSISDB Catalog.

        .DESCRIPTION
            Returns the named folder from the catalog's Folders collection, or all folders when no
            name is given. Returns $null when a named folder does not exist. Internal interop helper,
            not exported from the module.

        .EXAMPLE
            $folder = Get-SsisFolderObject -Catalog $catalog -Name 'Finance'

            Returns the Finance folder, or $null when it does not exist.

        .EXAMPLE
            $folders = Get-SsisFolderObject -Catalog $catalog

            Returns every folder in the catalog's Folders collection when no name is given.

        .PARAMETER Catalog
            The SSISDB Catalog object, as returned by Get-SsisCatalogObject.

        .PARAMETER Name
            The folder name to return. When omitted, every folder in the catalog is returned.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.CatalogFolder')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter()]
        [string]
        $Name
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            if ($Catalog.Folders.Contains($Name))
            {
                return $Catalog.Folders[$Name]
            }

            return $null
        }

        return $Catalog.Folders
    }
}
