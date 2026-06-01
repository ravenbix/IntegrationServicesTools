function Update-SsisExecutionObject
{
    <#
        .SYNOPSIS
            Refreshes an SSISDB execution from the server and returns it.

        .DESCRIPTION
            Calls Refresh() on the ExecutionOperation so its Status and timing properties reflect the
            current server state, then returns the same object. Used as the poll primitive by
            Wait-SsisExecution. Internal interop helper, not exported from the module.

        .EXAMPLE
            $execution = Update-SsisExecutionObject -Execution $execution

            Refreshes the execution and returns it with up-to-date Status.

        .PARAMETER Execution
            The ExecutionOperation object to refresh, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.ExecutionOperation')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        $Execution.Refresh()
        return $Execution
    }
}
