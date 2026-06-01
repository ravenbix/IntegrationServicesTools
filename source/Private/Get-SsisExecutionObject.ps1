function Get-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Returns SSISDB executions from a catalog, optionally a single one by id.

        .DESCRIPTION
            Returns the catalog's Executions collection, or a single ExecutionOperation when
            -ExecutionId is supplied (indexed from the collection). Internal interop helper, not
            exported from the module.

        .EXAMPLE
            $executions = Get-SsisExecutionObject -Catalog $catalog

            Returns every execution recorded in the catalog.

        .EXAMPLE
            $execution = Get-SsisExecutionObject -Catalog $catalog -ExecutionId 42

            Returns the execution with id 42.

        .PARAMETER Catalog
            The SSISDB Catalog object whose executions to read, as returned by Get-SsisCatalogObject.

        .PARAMETER ExecutionId
            The numeric id of a single execution to return. When omitted, the whole collection is
            returned.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Catalog,

        [Parameter()]
        [long]
        $ExecutionId
    )

    process
    {
        if ($PSBoundParameters.ContainsKey('ExecutionId'))
        {
            return $Catalog.Executions[$ExecutionId]
        }

        return $Catalog.Executions
    }
}
