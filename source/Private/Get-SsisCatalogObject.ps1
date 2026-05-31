function Get-SsisCatalogObject
{
    <#
        .SYNOPSIS
            Returns the SSISDB Catalog object from an IntegrationServices connection.

        .DESCRIPTION
            Looks up the named catalog (default 'SSISDB') in the IntegrationServices.Catalogs
            collection and returns it, or $null when the catalog has not yet been created on the
            server. Internal interop helper, not exported from the module.

        .EXAMPLE
            $catalog = Get-SsisCatalogObject -IntegrationServices $integrationServices

            Returns the SSISDB catalog object, or $null when it does not exist.

        .PARAMETER IntegrationServices
            The IntegrationServices object (from Connect-SsisCatalog) representing the target server.

        .PARAMETER Name
            The catalog name to look up. The SSIS catalog is always named 'SSISDB', so this defaults
            to that value and rarely needs to be changed.
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Catalog')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $IntegrationServices,

        [Parameter()]
        [string]
        $Name = 'SSISDB'
    )

    process
    {
        if ($IntegrationServices.Catalogs.Contains($Name))
        {
            return $IntegrationServices.Catalogs[$Name]
        }

        return $null
    }
}
