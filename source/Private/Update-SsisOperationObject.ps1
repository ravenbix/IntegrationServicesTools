function Update-SsisOperationObject
{
    <#
        .SYNOPSIS
            Refreshes an SSISDB operation from the server and returns it.

        .DESCRIPTION
            Calls Refresh() on the Operation so its Status and timing properties reflect the current
            server state, then returns the same object. Used as the poll primitive by
            Wait-SsisOperation. Internal interop helper, not exported from the module.

        .EXAMPLE
            $operation = Update-SsisOperationObject -Operation $operation

            Refreshes the operation and returns it with up-to-date Status.

        .PARAMETER Operation
            The Operation object to refresh, as returned by Get-SsisOperationObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.Operation
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The Update verb triggers this rule, but Refresh() only re-reads server state and changes nothing, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.Operation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Operation
    )

    process
    {
        $Operation.Refresh()
        return $Operation
    }
}
