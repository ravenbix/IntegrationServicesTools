function Get-SsisExecutionMessageObject
{
    <#
        .SYNOPSIS
            Returns the message log recorded for an SSISDB execution.

        .DESCRIPTION
            Returns the execution's Messages collection (OperationMessage objects). Reading the
            collection re-reads the messages from the server. Internal interop helper, not exported
            from the module.

        .EXAMPLE
            $messages = Get-SsisExecutionMessageObject -Execution $execution

            Returns every message logged for the execution.

        .PARAMETER Execution
            The ExecutionOperation whose messages to read, as returned by Get-SsisExecutionObject.

        .OUTPUTS
            Microsoft.SqlServer.Management.IntegrationServices.OperationMessage
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.SqlServer.Management.IntegrationServices.OperationMessage')]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Execution
    )

    process
    {
        return $Execution.Messages
    }
}
