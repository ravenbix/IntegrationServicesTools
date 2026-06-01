function Get-SsisOperationObject
{
    <#
        .SYNOPSIS
            Returns SSISDB operations from a catalog, optionally a single one by id.

        .DESCRIPTION
            Returns the catalog's Operations collection, or a single Operation when -OperationId is
            supplied (indexed from the collection). Operations include executions, deployments, and
            validations. Internal interop helper, not exported from the module.

        .EXAMPLE
            $operations = Get-SsisOperationObject -Catalog $catalog

            Returns every operation recorded in the catalog.

        .EXAMPLE
            $operation = Get-SsisOperationObject -Catalog $catalog -OperationId 7

            Returns the operation with id 7.

        .PARAMETER Catalog
            The SSISDB Catalog object whose operations to read, as returned by Get-SsisCatalogObject.

        .PARAMETER OperationId
            The numeric id of a single operation to return. When omitted, the whole collection is
            returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.Operation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Operation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter()]
        [long]
        $OperationId
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('OperationId'))
        {
            return $Catalog.Operations[$OperationId]
        }

        return $Catalog.Operations
    }
}
