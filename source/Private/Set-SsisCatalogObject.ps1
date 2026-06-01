function Set-SsisCatalogObject
{
    <#
        .SYNOPSIS
            Applies property changes to an SSISDB Catalog object and persists them.

        .DESCRIPTION
            Sets each supplied property on the Catalog object then calls Alter() to persist the
            changes to the server. Only the properties present in the Property hashtable are changed.
            Internal interop helper, not exported from the module.

        .EXAMPLE
            Set-SsisCatalogObject -Catalog $catalog -Property @{ MaxProjectVersions = 5 }

            Sets MaxProjectVersions to 5 and persists the change.

        .EXAMPLE
            $splatProperty = @{
                OperationLogRetentionTime = 365
                OperationCleanupEnabled   = $true
            }
            Set-SsisCatalogObject -Catalog $catalog -Property $splatProperty

            Sets several catalog properties in one call before persisting them with a single Alter().

        .PARAMETER Catalog
            The Catalog object to modify, as returned by Get-SsisCatalogObject.

        .PARAMETER Property
            A hashtable of catalog property names to values to assign before calling Alter(), for
            example @{ OperationLogRetentionTime = 365; OperationCleanupEnabled = $true }.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin interop wrapper; ShouldProcess is implemented by the public command (Set-SsisCatalog) that calls this seam.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Catalog')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $Property
    )

    process
    {
        foreach ($key in $Property.Keys)
        {
            $Catalog.$key = $Property[$key]
        }

        $Catalog.Alter()
        return $Catalog
    }
}
